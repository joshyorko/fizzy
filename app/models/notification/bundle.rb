class Notification::Bundle < ApplicationRecord
  belongs_to :user

  enum :status, %i[ pending processing delivered ]

  before_create :set_default_window

  scope :due, -> { pending.where("ends_at <= ?", Time.current) }
  scope :containing, -> (notification) { where("starts_at <= ? AND ends_at >= ?", notification.created_at, notification.created_at) }

  class << self
    def deliver_all
      due.in_batches do |batch|
        DeliverJob.perform_all_later batch
      end
    end

    def deliver_all_later
      DeliverAllJob.perform_later
    end
  end

  def notifications
    user.notifications.where(created_at: window)
  end

  def deliver
    processing!

    BundleMailer.notification(self).deliver if has_unread_notifications?

    delivered!
  end

  def deliver_later
    DeliverJob.perform_later(self)
  end

  private
    AGGREGATION_PERIOD = 4.hours

    def set_default_window
      self.starts_at ||= Time.current
      self.ends_at ||= AGGREGATION_PERIOD.from_now
    end

    def window
      starts_at..ends_at
    end

    def has_unread_notifications?
      notifications.unread.any?
    end
end
