class Oauth::Client < ApplicationRecord
  self.table_name = "oauth_clients"

  has_many :authorization_codes, class_name: "Oauth::AuthorizationCode", dependent: :destroy
  has_many :access_tokens, class_name: "Identity::AccessToken", dependent: :nullify

  before_validation :set_client_id, on: :create
  before_validation :normalize_attributes

  validates :client_id, :redirect_uris, :token_endpoint_auth_method, :scope, presence: true
  validates :client_id, uniqueness: true
  validates :token_endpoint_auth_method, inclusion: { in: %w[ none ] }
  validate :scope_is_supported
  validate :redirect_uris_are_absolute

  def redirect_uri_allowed?(redirect_uri)
    redirect_uri.to_s.in?(redirect_uris)
  end

  private
    def set_client_id
      self.client_id ||= "fzy_#{SecureRandom.urlsafe_base64(24)}"
    end

    def normalize_attributes
      self.redirect_uris = normalize_array(redirect_uris)
      self.grant_types = normalize_array(grant_types.presence || %w[ authorization_code ])
      self.response_types = normalize_array(response_types.presence || %w[ code ])
      self.scope = Oauth::Scope.normalize(scope_or_default) if Oauth::Scope.valid?(scope_or_default)
      self.token_endpoint_auth_method = "none"
    end

    def scope_or_default
      scope.presence || Oauth::Scope::DEFAULT
    end

    def normalize_array(value)
      case value
      when String
        value.start_with?("[") ? JSON.parse(value) : value.split
      else
        Array(value)
      end.map(&:to_s).reject(&:blank?).uniq
    rescue JSON::ParserError
      []
    end

    def redirect_uris_are_absolute
      redirect_uris.each do |redirect_uri|
        uri = URI.parse(redirect_uri)
        unless uri.absolute? && uri.fragment.blank? && allowed_redirect_uri_scheme?(uri)
          errors.add(:redirect_uris, "must use https, loopback http, or a native app scheme")
        end
      rescue URI::InvalidURIError
        errors.add(:redirect_uris, "must be valid")
      end
    end

    def allowed_redirect_uri_scheme?(uri)
      https_uri?(uri) || loopback_http_uri?(uri) || native_app_uri?(uri)
    end

    def https_uri?(uri)
      uri.scheme == "https"
    end

    def loopback_http_uri?(uri)
      uri.scheme == "http" && uri.host.in?(%w[ localhost 127.0.0.1 ::1 ])
    end

    def native_app_uri?(uri)
      uri.host.blank? && uri.scheme.present? && !uri.scheme.in?(%w[ http https javascript data file ])
    end

    def scope_is_supported
      errors.add(:scope, "is not supported") unless Oauth::Scope.valid?(scope)
    end
end
