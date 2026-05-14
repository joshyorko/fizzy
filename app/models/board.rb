class Board < ApplicationRecord
  include Accessible, AutoPostponing, Board::Storage, Broadcastable, Cards, Entropic, Filterable, Publishable, ::Storage::Tracked, Triageable

  SYSTEM_COLUMN_NAMES = {
    "maybe" => "Maybe?",
    "not now" => "Not Now",
    "done" => "Done"
  }.freeze

  belongs_to :creator, class_name: "User", default: -> { Current.user }
  belongs_to :account, default: -> { creator.account }

  has_rich_text :public_description

  has_many :tags, -> { distinct }, through: :cards
  has_many :events
  has_many :webhooks, dependent: :destroy

  scope :alphabetically, -> { order("lower(name)") }
  scope :ordered_by_recently_accessed, -> { merge(Access.ordered_by_recently_accessed) }

  def self.system_column_names
    SYSTEM_COLUMN_NAMES.values
  end

  def self.system_column_name_for(name)
    SYSTEM_COLUMN_NAMES[normalize_system_column_name(name)]
  end

  def self.system_column_name?(name)
    system_column_name_for(name).present?
  end

  def self.normalize_system_column_name(name)
    name.to_s.downcase.tr("_-", " ").delete("?").squish
  end
end
