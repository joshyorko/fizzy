class McpController < ApplicationController
  skip_before_action :require_account
  skip_before_action :require_authentication
  skip_before_action :ensure_can_access_account
  skip_forgery_protection

  before_action :authenticate_access_token, except: :discovery

  def discovery
    render json: {
      name: "fizzy",
      title: "Fizzy",
      version: "1.0.0",
      protocolVersion: Mcp::Server::PROTOCOL_VERSION,
      capabilities: {
        tools: { listChanged: false },
        resources: { listChanged: false }
      },
      endpoint: mcp_url(script_name: nil),
      authorization_server: oauth_authorization_server_url(script_name: nil),
      protected_resource: oauth_protected_resource_url(script_name: nil)
    }
  end

  def show
    head :method_not_allowed
  end

  def create
    message = parsed_message

    if unsupported_protocol_header? || invalid_stateless_headers?
      render status: :bad_request, json: json_rpc_error(json_rpc_id(message), -32602, "Unsupported protocol version")
    elsif mcp_response = mcp_server.handle(message)
      render json: mcp_response
    else
      head :accepted
    end
  rescue JSON::ParserError
    render status: :bad_request, json: json_rpc_error(nil, -32700, "Parse error")
  end

  def destroy
    head :method_not_allowed
  end

  private
    def mcp_server
      Mcp::Server.new(
        access_token: @access_token,
        url_context: self,
        auth_challenge: bearer_challenge(
          error: "insufficient_scope",
          error_description: "Read and write scope required",
          scope: "read write"
        )
      )
    end

    def authenticate_access_token
      if @access_token = Identity::AccessToken.authenticate(bearer_token, resource: mcp_resource_url)
        Current.identity = @access_token.identity
      else
        response.headers["WWW-Authenticate"] = bearer_challenge(error: "invalid_token", error_description: "Missing or invalid bearer token")
        render status: :unauthorized, json: { error: "unauthorized" }
      end
    end

    def bearer_challenge(error: nil, error_description: nil, scope: nil)
      [
        %(Bearer realm="Fizzy MCP"),
        %(resource_metadata="#{oauth_protected_resource_url(script_name: nil)}"),
        (%(error="#{error}") if error.present?),
        (%(error_description="#{error_description}") if error_description.present?),
        (%(scope="#{scope}") if scope.present?)
      ].compact.join(", ")
    end

    def bearer_token
      request.authorization.to_s[/\ABearer (.+)\z/i, 1]
    end

    def mcp_resource_url
      mcp_url(script_name: nil)
    end

    def parsed_message
      JSON.parse(request.raw_post)
    end

    def json_rpc_error(id, code, message)
      { jsonrpc: "2.0", id: id, error: { code: code, message: message } }
    end

    def unsupported_protocol_header?
      request.headers["MCP-Protocol-Version"].present? &&
        !Mcp::Server.supports_protocol_version?(request.headers["MCP-Protocol-Version"])
    end

    def invalid_stateless_headers?
      if request.headers["MCP-Protocol-Version"] == Mcp::Server::PROTOCOL_VERSION
        request.headers["Mcp-Method"].blank? || request.headers["Mcp-Name"].blank?
      else
        false
      end
    end

    def json_rpc_id(message)
      message["id"] if message.is_a?(Hash)
    end
end
