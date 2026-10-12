require "test_helper"

class McpStatelessControllerTest < ActionDispatch::IntegrationTest
  setup do
    @token = fixture_access_token(:davids_api_token)
  end

  test "discovery needs no initialization or name header" do
    post_request "server/discover"

    assert_response :success
    result = response.parsed_body.fetch("result")
    assert_includes result["supportedVersions"], "2026-07-28"
    assert_equal "complete", result["resultType"]
    assert_equal "fizzy", result.dig("_meta", "io.modelcontextprotocol/serverInfo", "name")
    assert_equal "private", result["cacheScope"]
    assert_operator result["ttlMs"], :>=, 0
    assert_nil response.headers["Mcp-Session-Id"]
  end

  test "requests run through independent server instances" do
    token = Identity::AccessToken.authenticate(@token, resource: mcp_url(script_name: nil))
    servers = Array.new(2) do
      Mcp::Server.new(access_token: token, url_context: self, protocol_version: "2026-07-28")
    end
    Mcp::Server.expects(:new).twice.returns(*servers)

    post_request "tools/call", name: "account_list", arguments: {}
    assert_response :success
    assert_kind_of Array, response.parsed_body.dig("result", "structuredContent", "accounts")

    post_request "tools/call", name: "identity_show", arguments: {}
    assert_response :success
    assert_equal identities(:david).email_address, response.parsed_body.dig("result", "structuredContent", "email_address")
    assert_not_same servers.first, servers.last
  end

  test "catalogs are sorted and authorization private" do
    post_request "tools/list"
    assert_response :success
    result = response.parsed_body.fetch("result")
    names = result.fetch("tools").pluck("name")
    assert_equal names.sort, names
    assert_equal "private", result["cacheScope"]
    assert_equal "complete", result["resultType"]
    assert_operator result["ttlMs"], :>, 0

    post_request "resources/list"
    assert_response :success
    result = response.parsed_body.fetch("result")
    uris = result.fetch("resources").pluck("uri")
    assert_equal uris.sort, uris
    assert_equal "private", result["cacheScope"]
    assert_equal 0, result["ttlMs"]
  end

  test "resource reads use URI headers and immediately stale private caching" do
    post_request "resources/read", uri: "fizzy://accounts"
    assert_response :success
    result = response.parsed_body.fetch("result")
    assert_equal "fizzy://accounts", result.dig("contents", 0, "uri")
    assert_equal "private", result["cacheScope"]
    assert_equal 0, result["ttlMs"]
  end

  test "encoded name headers are decoded before matching" do
    post_request "tools/call", { name: "identity_show", arguments: {} },
      headers: { "Mcp-Name" => "=?base64?#{Base64.strict_encode64('identity_show')}?=" }
    assert_response :success
    assert_equal identities(:david).id, response.parsed_body.dig("result", "structuredContent", "id")
  end

  test "missing or mismatched routing headers cannot execute a write" do
    [ { "Mcp-Method" => nil }, { "Mcp-Method" => "tools/list" },
      { "Mcp-Name" => nil }, { "Mcp-Name" => "account_list" },
      { "Mcp-Name" => "=?base64?invalid!?=" } ].each do |headers|
      assert_no_difference "Card.count" do
        post_request "tools/call", {
          name: "card_create",
          arguments: { account_id: accounts(:"37s").external_account_id.to_s, board_id: boards(:writebook).id, title: "Must not run" }
        }, headers: headers
      end
      assert_response :bad_request
      assert_equal(-32020, response.parsed_body.dig("error", "code"))
    end
  end

  test "modern body metadata cannot bypass missing or legacy version headers" do
    [ nil, "2025-11-25" ].each do |version|
      post_request "tools/list", {}, headers: { "MCP-Protocol-Version" => version }
      assert_response :bad_request
      assert_equal(-32020, response.parsed_body.dig("error", "code"))
    end
  end

  test "body protocol version must match the header" do
    post_request "tools/list", { _meta: metadata.merge("io.modelcontextprotocol/protocolVersion" => "2025-11-25") }
    assert_response :bad_request
    assert_equal(-32020, response.parsed_body.dig("error", "code"))
  end

  test "client capabilities must be declared on each modern request" do
    [ nil, [], "tools", false ].each do |capabilities|
      post_request "tools/list", { _meta: metadata.merge("io.modelcontextprotocol/clientCapabilities" => capabilities) }
      assert_response :bad_request
      assert_equal(-32602, response.parsed_body.dig("error", "code"))
    end
  end

  test "unsupported version errors advertise supported versions" do
    post_request "tools/list", {}, headers: { "MCP-Protocol-Version" => "2099-01-01" }
    assert_response :bad_request
    error = response.parsed_body.fetch("error")
    assert_equal(-32022, error["code"])
    assert_equal "2099-01-01", error.dig("data", "requested")
    assert_includes error.dig("data", "supported"), "2026-07-28"
  end

  test "unknown and removed modern methods return 404" do
    %w[ unknown ping initialize ].each do |method|
      post_request method
      assert_response :not_found
      assert_equal(-32601, response.parsed_body.dig("error", "code"))
    end
  end

  test "modern requests reject batch bodies and malformed params" do
    [ [], [ request_body("tools/list") ], request_body("tools/list").merge(params: []) ].each do |message|
      untenanted { post mcp_path, params: message.to_json, headers: request_headers("tools/list", {}) }
      assert_response :bad_request
    end
  end

  test "modern missing resources use invalid params" do
    post_request "resources/read", uri: "fizzy://missing"
    assert_response :success
    assert_equal(-32602, response.parsed_body.dig("error", "code"))
  end

  test "untrusted browser origins are rejected" do
    post_request "tools/list", {}, headers: { "Origin" => "https://attacker.example" }
    assert_response :forbidden
  end

  test "read tokens still cannot write with modern metadata" do
    @token = fixture_access_token(:jasons_api_token)
    post_request "tools/call", name: "card_create", arguments: {}
    assert_response :success
    result = response.parsed_body.fetch("result")
    assert_equal true, result["isError"]
    assert_equal "complete", result["resultType"]
    assert_match "insufficient_scope", result.dig("_meta", "mcp/www_authenticate")
  end

  private
    def metadata
      { "io.modelcontextprotocol/protocolVersion" => "2026-07-28",
        "io.modelcontextprotocol/clientCapabilities" => {} }
    end

    def request_body(method, params = {})
      { jsonrpc: "2.0", id: 1, method: method, params: { _meta: metadata }.merge(params) }
    end

    def request_headers(method, params)
      { "CONTENT_TYPE" => "application/json", "ACCEPT" => "application/json, text/event-stream",
        "Authorization" => "Bearer #{@token}", "MCP-Protocol-Version" => "2026-07-28",
        "Mcp-Method" => method, "Mcp-Name" => params[:name] || params[:uri] }.compact
    end

    def post_request(method, params = {}, headers: {}, **arguments)
      params = params.merge(arguments)
      untenanted do
        post mcp_path, params: request_body(method, params).to_json,
          headers: request_headers(method, params).merge(headers)
      end
    end
end
