class Oauth::AuthorizationCode < ApplicationRecord
  self.table_name = "oauth_authorization_codes"

  EXPIRATION_TIME = 10.minutes

  belongs_to :client, class_name: "Oauth::Client"
  belongs_to :identity

  before_validation :set_code, on: :create
  before_validation :set_expiration, on: :create
  before_validation :normalize_scope

  validates :code, :redirect_uri, :code_challenge, :code_challenge_method, :scope, :resource, :expires_at, presence: true
  validates :code, uniqueness: true
  validates :code_challenge_method, inclusion: { in: %w[ S256 ] }
  validate :scope_is_supported
  validate :redirect_uri_is_registered

  scope :active, -> { where(used_at: nil).where("expires_at > ?", Time.current) }

  def active?
    used_at.nil? && expires_at.future?
  end

  def use
    update!(used_at: Time.current)
  end

  def verifies_pkce?(verifier)
    code_challenge == self.class.challenge_for(verifier)
  end

  def self.challenge_for(verifier)
    Base64.urlsafe_encode64(Digest::SHA256.digest(verifier.to_s), padding: false)
  end

  private
    def set_code
      self.code ||= SecureRandom.urlsafe_base64(32)
    end

    def set_expiration
      self.expires_at ||= EXPIRATION_TIME.from_now
    end

    def normalize_scope
      self.scope = Oauth::Scope.normalize(scope) if Oauth::Scope.valid?(scope)
    end

    def redirect_uri_is_registered
      errors.add(:redirect_uri, "is not registered") if client && !client.redirect_uri_allowed?(redirect_uri)
    end

    def scope_is_supported
      errors.add(:scope, "is not supported") unless Oauth::Scope.valid?(scope)
    end
end
