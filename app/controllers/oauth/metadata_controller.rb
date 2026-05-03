class Oauth::MetadataController < Oauth::BaseController
  allow_unauthenticated_access

  def protected_resource
    render json: {
      resource: mcp_resource_url,
      authorization_servers: [ issuer_url ],
      scopes_supported: Oauth::Scope::SUPPORTED,
      bearer_methods_supported: [ "header" ],
      resource_documentation: issuer_url
    }
  end

  def authorization_server
    render json: {
      issuer: issuer_url,
      authorization_endpoint: oauth_authorize_url(script_name: nil),
      token_endpoint: oauth_token_url(script_name: nil),
      registration_endpoint: oauth_register_url(script_name: nil),
      response_types_supported: [ "code" ],
      grant_types_supported: [ "authorization_code" ],
      code_challenge_methods_supported: [ "S256" ],
      token_endpoint_auth_methods_supported: [ "none" ],
      scopes_supported: Oauth::Scope::SUPPORTED
    }
  end
end
