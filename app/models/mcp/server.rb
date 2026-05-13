class Mcp::Server
  PROTOCOL_VERSION = "2025-06-18"

  class Forbidden < StandardError
    attr_reader :response

    def initialize(response)
      @response = response
    end
  end

  def initialize(access_token:, url_context:, protocol_version: nil)
    @access_token = access_token
    @url_context = url_context
    @protocol_version = protocol_version
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
        if supported_protocol_version?(message.dig("params", "protocolVersion"))
          response(message["id"], initialize_result)
        else
          error(message["id"], -32602, "Unsupported protocol version")
        end
      when "ping"
        return unsupported_protocol_version_error(message) unless header_protocol_version_supported?

        response(message["id"], {})
      when "tools/list"
        return unsupported_protocol_version_error(message) unless header_protocol_version_supported?

        response(message["id"], { tools: Mcp::Toolbox.tool_definitions })
      when "tools/call"
        return unsupported_protocol_version_error(message) unless header_protocol_version_supported?

        response(message["id"], toolbox.call(message.dig("params", "name"), message.dig("params", "arguments") || {}))
      when "resources/list"
        return unsupported_protocol_version_error(message) unless header_protocol_version_supported?

        response(message["id"], { resources: resources.list })
      when "resources/read"
        return unsupported_protocol_version_error(message) unless header_protocol_version_supported?

        response(message["id"], resources.read(message.dig("params", "uri")))
      else
        error(message["id"], -32601, "Method not found")
      end
    rescue Mcp::Toolbox::Forbidden => exception
      raise Forbidden, error(message["id"], -32003, exception.message)
    rescue Mcp::Toolbox::Error => exception
      error(message["id"], exception.code, exception.message)
    end

    def initialize_result
      {
        protocolVersion: PROTOCOL_VERSION,
        capabilities: {
          tools: { listChanged: false },
          resources: { listChanged: false }
        },
        serverInfo: { name: "fizzy", title: "Fizzy", version: "1.0.0" }
      }
    end

    def supported_protocol_version?(protocol_version)
      protocol_version.blank? || protocol_version == PROTOCOL_VERSION
    end

    def header_protocol_version_supported?
      supported_protocol_version?(@protocol_version)
    end

    def unsupported_protocol_version_error(message)
      error(message["id"], -32602, "Unsupported protocol version")
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

    def error(id, code, message)
      { jsonrpc: "2.0", id: id, error: { code: code, message: message } }
    end
end
