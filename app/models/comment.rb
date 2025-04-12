class Comment < ApplicationRecord
  include Messageable, Notifiable, Searchable

  belongs_to :creator, class_name: "User", default: -> { Current.user }
  has_many :reactions, dependent: :delete_all

  has_markdown :body
  searchable_by :body_plain_text, using: :comments_search_index, as: :body

  # FIXME: Not a fan of this. Think all references to comment should come directly from the message.
  scope :belonging_to_card, ->(card) { joins(:message).where(messages: { card_id: card.id }) }

  before_destroy :cleanup_events

  # Called when a new comment is captured as a message during creation
  def created_via_message
    card.watch_by creator
    card.track_event :commented, comment_id: id
  end

  def to_partial_path
    "cards/#{super}"
  end

  private
    def cleanup_events
      # Delete events that reference through event_summary
      if message&.event_summary.present?
        Event.where(summary: message.event_summary).destroy_all
      end

      # Delete events that reference directly in particulars
      Event.where(particulars: { comment_id: id }).destroy_all
    end
end
