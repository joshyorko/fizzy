class Oauth::AuthorizationsController < Oauth::BaseController
  layout "public"

  content_security_policy only: :show do |policy|
    policy.form_action :self, "https://chatgpt.com", "https://chat.openai.com"
  end

  before_action :set_authorization_request

  def show
  end

  def create
    authorization_code = @client.authorization_codes.create!(
      identity: Current.identity,
      redirect_uri: @redirect_uri,
      code_challenge: @code_challenge,
      code_challenge_method: @code_challenge_method,
      scope: @scope,
      resource: @resource
    )

    redirect_to redirect_uri_with(code: authorization_code.code, state: @state), allow_other_host: true
  end

  private
    def set_authorization_request
      @client = Oauth::Client.find_by!(client_id: params[:client_id])
      @redirect_uri = params[:redirect_uri].to_s
      @requested_scope = params[:scope].presence || @client.scope
      @scope = Oauth::Scope.normalize(@requested_scope) if Oauth::Scope.valid?(@requested_scope)
      @state = params[:state]
      @resource = params[:resource].to_s
      @code_challenge = params[:code_challenge].to_s
      @code_challenge_method = params[:code_challenge_method].to_s

      if !Oauth::Scope.valid?(@requested_scope)
        invalid_scope
      elsif !valid_authorization_request?
        head :bad_request
      end
    end

    def valid_authorization_request?
      params[:response_type] == "code" &&
        @client.redirect_uri_allowed?(@redirect_uri) &&
        requested_scope_allowed? &&
        @resource == mcp_resource_url &&
        @code_challenge.present? &&
        @code_challenge_method == "S256"
    end

    def requested_scope_allowed?
      (@scope.split - @client.scope.split).empty?
    end

    def invalid_scope
      render status: :bad_request, json: { error: "invalid_scope" }
    end

    def redirect_uri_with(params)
      uri = URI.parse(@redirect_uri)
      query = Rack::Utils.parse_nested_query(uri.query).merge(params.compact)
      uri.query = query.to_query
      uri.to_s
    end

    def request_authentication
      session[:return_to_after_authenticating] = request.url
      redirect_to_login_url
    end
end
