class Oauth::TokensController < Oauth::BaseController
  allow_unauthenticated_access
  skip_forgery_protection

  def create
    if access_token = exchange_authorization_code
      render json: {
        access_token: access_token.token,
        token_type: "Bearer",
        scope: @authorization_code.scope
      }
    else
      render status: :bad_request, json: { error: "invalid_grant" }
    end
  end

  private
    def exchange_authorization_code
      Oauth::AuthorizationCode.transaction do
        @authorization_code = Oauth::AuthorizationCode.active.lock.find_by(code: params[:code])

        if valid_token_request?
          @authorization_code.use
          @authorization_code.identity.access_tokens.create!(
            description: "MCP OAuth (#{@authorization_code.client.client_name.presence || @authorization_code.client.client_id})",
            permission: Oauth::Scope.permission_for(@authorization_code.scope)
          )
        end
      end
    end

    def valid_token_request?
      @authorization_code.present? &&
        params[:grant_type] == "authorization_code" &&
        params[:client_id] == @authorization_code.client.client_id &&
        params[:redirect_uri] == @authorization_code.redirect_uri &&
        token_resource == @authorization_code.resource &&
        @authorization_code.verifies_pkce?(params[:code_verifier])
    end

    def token_resource
      params[:resource].presence || @authorization_code.resource
    end
end
