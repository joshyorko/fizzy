class Mcp::Server
  PROTOCOL_VERSION = "2025-11-25"
  SUPPORTED_PROTOCOL_VERSIONS = [ PROTOCOL_VERSION, "2025-06-18" ].freeze

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

  def self.supports_protocol_version?(protocol_version)
    protocol_version.blank? || protocol_version.in?(SUPPORTED_PROTOCOL_VERSIONS)
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
        protocol_version = message.dig("params", "protocolVersion")

        if self.class.supports_protocol_version?(protocol_version)
          response(message["id"], initialize_result(protocol_version))
        else
          error(message["id"], -32602, "Unsupported protocol version")
        end
      when "ping"
        response(message["id"], {})
      when "tools/list"
        response(message["id"], { tools: Mcp::Toolbox.tool_definitions })
      when "tools/call"
        response(message["id"], toolbox.call(message.dig("params", "name"), message.dig("params", "arguments") || {}))
      when "resources/list"
        response(message["id"], { resources: resources.list })
      when "resources/read"
        response(message["id"], resources.read(message.dig("params", "uri")))
      else
        error(message["id"], -32601, "Method not found")
      end
    rescue Mcp::Toolbox::Forbidden => exception
      raise Forbidden, error(message["id"], -32003, exception.message)
    rescue Mcp::Toolbox::Error => exception
      error(message["id"], exception.code, exception.message)
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

    def error(id, code, message)
      { jsonrpc: "2.0", id: id, error: { code: code, message: message } }
    end
end
