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

    if unsupported_protocol_header?
      render status: :bad_request, json: json_rpc_error(json_rpc_id(message), -32602, "Unsupported protocol version")
    elsif response = Mcp::Server.new(access_token: @access_token, url_context: self).handle(message)
      render json: response
    else
      head :accepted
    end
  rescue JSON::ParserError
    render status: :bad_request, json: json_rpc_error(nil, -32700, "Parse error")
  rescue Mcp::Server::Forbidden => error
    render status: :forbidden, json: error.response
  end

  def destroy
    head :method_not_allowed
  end

  private
    def authenticate_access_token
      if bearer_token.present? && (@access_token = Identity::AccessToken.find_by(token: bearer_token))
        Current.identity = @access_token.identity
      else
        response.headers["WWW-Authenticate"] = %(Bearer realm="Fizzy MCP", resource_metadata="#{oauth_protected_resource_url(script_name: nil)}")
        render status: :unauthorized, json: { error: "unauthorized" }
      end
    end

    def bearer_token
      request.authorization.to_s[/\ABearer (.+)\z/i, 1]
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

    def json_rpc_id(message)
      message["id"] if message.is_a?(Hash)
    end
end
