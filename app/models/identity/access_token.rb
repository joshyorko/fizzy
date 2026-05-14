require "digest"

class Identity::AccessToken < ApplicationRecord
  PERSONAL_EXPIRES_IN = 1.year
  OAUTH_EXPIRES_IN = 90.days

  belongs_to :identity
  belongs_to :oauth_client, class_name: "Oauth::Client", optional: true

  before_validation :generate_token_digest, on: :create
  before_validation :set_default_expiration, on: :create

  enum :permission, %w[ read write ].index_by(&:itself), default: :read

  validates :token_digest, presence: true, uniqueness: true

  scope :personal, -> { where(oauth_client_id: nil) }
  scope :oauth, -> { where.not(oauth_client_id: nil) }
  scope :active, -> { where(revoked_at: nil).where("expires_at IS NULL OR expires_at > ?", Time.current) }

  attr_reader :token

  def self.authenticate(token, resource: nil)
    return if token.blank?

    active.find_by(token_digest: digest(token))&.tap do |access_token|
      unless access_token.usable_for?(resource: resource)
        return
      end

      access_token.record_use
    end
  end

  def self.digest(token)
    Digest::SHA256.hexdigest(token.to_s)
  end

  def self.generate_token
    "fzy_#{SecureRandom.urlsafe_base64(32)}"
  end

  def allows?(method)
    usable_for?(resource: nil) && (method.in?(%w[ GET HEAD ]) || write?)
  end

  def usable_for?(resource:)
    return false if revoked? || expired?

    if oauth?
      resource.present? && self.resource == resource
    else
      true
    end
  end

  def oauth?
    oauth_client_id.present?
  end

  def expired?
    expires_at.present? && expires_at.past?
  end

  def revoked?
    revoked_at.present?
  end

  def revoke
    update!(revoked_at: Time.current)
  end

  def record_use
    update_column(:last_used_at, Time.current)
  end

  private
    def generate_token_digest
      return if token_digest.present?

      @token = self.class.generate_token
      self.token_digest = self.class.digest(@token)
    end

    def set_default_expiration
      self.expires_at ||= (oauth? ? OAUTH_EXPIRES_IN : PERSONAL_EXPIRES_IN).from_now
    end
end
