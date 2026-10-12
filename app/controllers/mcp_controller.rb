class McpController < ApplicationController
  skip_before_action :require_account
  skip_before_action :require_authentication
  skip_before_action :ensure_can_access_account
  skip_forgery_protection

  before_action :validate_origin
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
    response.headers["Cache-Control"] = "no-store"

    if unsupported_protocol_header?
      error = json_rpc_error(json_rpc_id(message), -32022, "Unsupported protocol version", modern: true)
      error[:error][:data] = { requested: request.headers["MCP-Protocol-Version"], supported: Mcp::Server::SUPPORTED_PROTOCOL_VERSIONS }
      render status: :bad_request, json: error
    elsif validation_error = stateless_request_error(message)
      render status: :bad_request, json: json_rpc_error(json_rpc_id(message), *validation_error, modern: true)
    elsif mcp_response = mcp_server.handle(message)
      status = modern_protocol? && mcp_response.dig(:error, :code) == -32601 ? :not_found : :ok
      render status: status, json: mcp_response
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
        protocol_version: request.headers["MCP-Protocol-Version"].presence || Mcp::Server::LEGACY_PROTOCOL_VERSION,
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

    def json_rpc_error(id, code, message, modern: modern_protocol?)
      { jsonrpc: "2.0", id: id, error: { code: code, message: message } }.tap do |payload|
        payload.delete(:id) if modern && id.nil?
      end
    end

    def unsupported_protocol_header?
      request.headers["MCP-Protocol-Version"].present? &&
        !Mcp::Server.supports_protocol_version?(request.headers["MCP-Protocol-Version"])
    end

    def modern_protocol?
      request.headers["MCP-Protocol-Version"] == Mcp::Server::PROTOCOL_VERSION
    end

    def stateless_request_error(message)
      params = message["params"] if message.is_a?(Hash)
      metadata = params["_meta"] if params.is_a?(Hash)
      body_version = metadata["io.modelcontextprotocol/protocolVersion"] if metadata.is_a?(Hash)
      has_protocol_metadata = metadata.is_a?(Hash) &&
        (metadata.key?("io.modelcontextprotocol/protocolVersion") || metadata.key?("io.modelcontextprotocol/clientCapabilities"))
      return unless modern_protocol? || has_protocol_metadata

      unless message.is_a?(Hash) && message["jsonrpc"] == "2.0" && message["method"].is_a?(String)
        return [ -32600, "Invalid Request" ]
      end
      unless message["id"].is_a?(String) || message["id"].is_a?(Numeric)
        return [ -32600, "Invalid Request" ]
      end
      return [ -32602, "Invalid request metadata" ] unless params.is_a?(Hash) && metadata.is_a?(Hash)
      return [ -32602, "Protocol version metadata is required" ] unless body_version.is_a?(String) && body_version.present?

      unless modern_protocol? && body_version == request.headers["MCP-Protocol-Version"] &&
          message["method"] == request.headers["Mcp-Method"]
        return [ -32020, "Header mismatch" ]
      end

      name_key = { "tools/call" => "name", "resources/read" => "uri", "prompts/get" => "name" }[message["method"]]
      if name_key && (!params[name_key].is_a?(String) || params[name_key].blank? || decoded_name_header != params[name_key])
        return [ -32020, "Header mismatch: Mcp-Name" ]
      end

      unless metadata["io.modelcontextprotocol/clientCapabilities"].is_a?(Hash)
        [ -32602, "Client capabilities must be an object" ]
      end
    end

    def decoded_name_header
      value = request.headers["Mcp-Name"].to_s
      return unless value.match?(/\A[\x20-\x7e\t]*\z/) && value == value.strip

      if value.start_with?("=?base64?") && value.end_with?("?=")
        Base64.strict_decode64(value.delete_prefix("=?base64?").delete_suffix("?=")).force_encoding(Encoding::UTF_8)
      else
        value
      end
    rescue ArgumentError
      nil
    end

    def validate_origin
      head :forbidden if request.headers["Origin"].present? && request.headers["Origin"] != request.base_url
    end

    def json_rpc_id(message)
      id = message["id"] if message.is_a?(Hash)
      id if id.is_a?(String) || id.is_a?(Numeric)
    end
end
