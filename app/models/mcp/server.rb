class Mcp::Server
  PROTOCOL_VERSION = "2026-07-28"
  SUPPORTED_PROTOCOL_VERSIONS = [ PROTOCOL_VERSION, "2025-11-25", "2025-06-18" ].freeze

  def initialize(access_token:, url_context:, auth_challenge: nil)
    @access_token = access_token
    @url_context = url_context
    @auth_challenge = auth_challenge
  end

  def self.supports_protocol_version?(protocol_version)
    protocol_version.blank? || protocol_version.in?(SUPPORTED_PROTOCOL_VERSIONS)
  end

  def handle(message)
    if message.is_a?(Array)
      responses = message.presence ? message.filter_map { |entry| handle_single(entry) } : [ error(nil, -32600, "Invalid Request") ]
      responses.presence
    else
      handle_single(message)
    end
  end

  private
    def handle_single(message)
      return error(nil, -32600, "Invalid Request") unless message.is_a?(Hash)

      if notification?(message)
        nil
      else
        dispatch(message)
      end
    end

    def notification?(message)
      message["id"].nil? && message["method"].to_s.start_with?("notifications/")
    end

    def dispatch(message)
      return error(message["id"], -32600, "Invalid Request") unless message["jsonrpc"] == "2.0" && message["method"].present?

      case message["method"]
      when "server/discover"
        response(message["id"], discovery_result)
      when "initialize"
        protocol_version = message.dig("params", "protocolVersion")

        if self.class.supports_protocol_version?(protocol_version)
          response(message["id"], initialize_result(protocol_version))
        else
          error(message["id"], -32602, "Unsupported protocol version")
        end
      when "ping"
        response(message["id"], {})
      when "tools/list"
        response(message["id"], list_result(tools: Mcp::Toolbox.tool_definitions.sort_by { |tool| tool[:name] }))
      when "tools/call"
        response(message["id"], toolbox.call(message.dig("params", "name"), message.dig("params", "arguments") || {}))
      when "resources/list"
        response(message["id"], list_result(resources: resources.list.sort_by { |resource| resource[:uri] }))
      when "resources/read"
        response(message["id"], resources.read(message.dig("params", "uri")).merge(ttlMs: 60_000, cacheScope: "private"))
      else
        error(message["id"], -32601, "Method not found")
      end
    rescue Mcp::Toolbox::Forbidden => exception
      response(message["id"], tool_error_result(exception.message, www_authenticate: @auth_challenge))
    rescue Mcp::Toolbox::Error => exception
      error(message["id"], exception.code, exception.message)
    rescue ActiveRecord::RecordNotFound
      error(message["id"], -32004, "Not found")
    rescue ActiveRecord::RecordInvalid => exception
      error(message["id"], -32602, exception.record.errors.full_messages.to_sentence)
    end

    def initialize_result(protocol_version)
      {
        protocolVersion: negotiated_protocol_version(protocol_version),
        capabilities: {
          tools: { listChanged: false },
          resources: { listChanged: false }
        },
        serverInfo: { name: "fizzy", title: "Fizzy", version: "1.0.0" }
      }
    end

    def discovery_result
      initialize_result(PROTOCOL_VERSION)
    end

    def list_result(payload)
      payload.merge(ttlMs: 60_000, cacheScope: "private")
    end

    def negotiated_protocol_version(protocol_version)
      protocol_version.presence || PROTOCOL_VERSION
    end

    def toolbox
      @toolbox ||= Mcp::Toolbox.new(access_token: @access_token, url_context: @url_context)
    end

    def resources
      @resources ||= Mcp::Resources.new(access_token: @access_token, url_context: @url_context)
    end

    def response(id, result)
      { jsonrpc: "2.0", id: id, result: result }
    end

    def error(id, code, message, www_authenticate: nil)
      { jsonrpc: "2.0", id: id, error: { code: code, message: message } }.tap do |payload|
        payload[:_meta] = { "mcp/www_authenticate": www_authenticate } if www_authenticate.present?
      end
    end

    def tool_error_result(message, www_authenticate: nil)
      {
        content: [ { type: "text", text: message } ],
        isError: true
      }.tap do |payload|
        payload[:_meta] = { "mcp/www_authenticate": www_authenticate } if www_authenticate.present?
      end
    end
end
