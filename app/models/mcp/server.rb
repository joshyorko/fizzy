class Mcp::Server
  PROTOCOL_VERSION = "2025-06-18"

  class Forbidden < StandardError
    attr_reader :response

    def initialize(response)
      @response = response
    end
  end

  def initialize(access_token:, url_context:)
    @access_token = access_token
    @url_context = url_context
  end

  def handle(message)
    if message.is_a?(Array)
      responses = message.filter_map { |entry| handle_single(entry) }
      responses.presence
    else
      handle_single(message)
    end
  end

  private
    def handle_single(message)
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
      case message["method"]
      when "initialize"
        response(message["id"], initialize_result(message.dig("params", "protocolVersion")))
      when "ping"
        response(message["id"], {})
      when "tools/list"
        response(message["id"], { tools: Mcp::Toolbox.tool_definitions })
      when "tools/call"
        response(message["id"], toolbox.call(message.dig("params", "name"), message.dig("params", "arguments") || {}))
      else
        error(message["id"], -32601, "Method not found")
      end
    rescue Mcp::Toolbox::Forbidden => exception
      raise Forbidden, error(message["id"], -32003, exception.message)
    rescue Mcp::Toolbox::Error => exception
      error(message["id"], exception.code, exception.message)
    end

    def initialize_result(requested_protocol_version)
      {
        protocolVersion: requested_protocol_version.presence || PROTOCOL_VERSION,
        capabilities: { tools: { listChanged: false } },
        serverInfo: { name: "fizzy", title: "Fizzy", version: "1.0.0" }
      }
    end

    def toolbox
      @toolbox ||= Mcp::Toolbox.new(access_token: @access_token, url_context: @url_context)
    end

    def response(id, result)
      { jsonrpc: "2.0", id: id, result: result }
    end

    def error(id, code, message)
      { jsonrpc: "2.0", id: id, error: { code: code, message: message } }
    end
end
