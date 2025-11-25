class User < ApplicationRecord
  include Accessor, Assignee, Attachable, Configurable, EmailAddressChangeable,
    Mentionable, Named, Notifiable, Role, Searcher, Watcher
  include Timelined # Depends on Accessor

  has_one_attached :avatar do |attachable|
    attachable.variant :thumb, resize_to_limit: [ 256, 256 ]
  end

  belongs_to :account
  belongs_to :identity, optional: true

  has_many :comments, inverse_of: :creator, dependent: :destroy

  has_many :filters, foreign_key: :creator_id, inverse_of: :creator, dependent: :destroy
  has_many :closures, dependent: :nullify
  has_many :pins, dependent: :destroy
  has_many :pinned_cards, through: :pins, source: :card

  scope :with_avatars, -> { preload(:account, :avatar_attachment) }

  def deactivate
    transaction do
      accesses.destroy_all
      update! active: false, identity: nil
    end
  end
end
