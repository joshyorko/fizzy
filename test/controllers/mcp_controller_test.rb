require "test_helper"

class McpControllerTest < ActionDispatch::IntegrationTest
  setup do
    @read_token = identity_access_tokens(:jasons_api_token).token
    @write_token = identity_access_tokens(:davids_api_token).token
    @account_id = accounts(:'37s').external_account_id.to_s
  end

  test "unauthenticated requests return oauth challenge" do
    untenanted do
      post mcp_path, params: json_rpc("initialize").to_json, headers: json_headers
    end

    assert_response :unauthorized
    assert_match "resource_metadata=", @response.headers["WWW-Authenticate"]
    assert_match oauth_protected_resource_url(script_name: nil), @response.headers["WWW-Authenticate"]
  end

  test "invalid bearer token is rejected" do
    untenanted do
      post mcp_path, params: json_rpc("initialize").to_json, headers: json_headers("nonsense")
    end

    assert_response :unauthorized
  end

  test "read token can initialize and call read tool" do
    untenanted do
      post mcp_path, params: json_rpc("initialize", params: { protocolVersion: "2025-06-18" }).to_json,
        headers: json_headers(@read_token)
    end

    assert_response :success
    assert_equal "2025-06-18", @response.parsed_body.dig("result", "protocolVersion")

    untenanted do
      post mcp_path, params: tool_call("account_list").to_json, headers: json_headers(@read_token)
    end

    assert_response :success
    assert_kind_of Array, @response.parsed_body.dig("result", "structuredContent", "accounts")
  end

  test "read token cannot call write tool" do
    untenanted do
      post mcp_path,
        params: tool_call("card_create", account_id: @account_id, board_id: boards(:writebook).id, title: "Nope").to_json,
        headers: json_headers(@read_token)
    end

    assert_response :forbidden
  end

  test "write token can create a card" do
    assert_difference -> { boards(:writebook).cards.count }, +1 do
      untenanted do
        post mcp_path,
          params: tool_call("card_create",
            account_id: @account_id,
            board_id: boards(:writebook).id,
            title: "MCP card",
            description: "Created from ChatGPT"
          ).to_json,
          headers: json_headers(@write_token)
      end
    end

    assert_response :success
    card = Card.order(:created_at).last
    assert_equal "MCP card", card.title
    assert_equal "Created from ChatGPT", card.description.to_plain_text
  end

  test "write token can create a comment" do
    assert_difference -> { cards(:logo).comments.count }, +1 do
      untenanted do
        post mcp_path,
          params: tool_call("comment_create", account_id: @account_id, card_id: cards(:logo).id, body: "Looks good.").to_json,
          headers: json_headers(@write_token)
      end
    end

    assert_response :success
    assert_equal "Looks good.", cards(:logo).comments.last.body.to_plain_text
  end

  test "write token can update a card inside account context" do
    untenanted do
      post mcp_path,
        params: tool_call("card_update", account_id: @account_id, card_id: cards(:logo).id, title: "Larger logo").to_json,
        headers: json_headers(@write_token)
    end

    assert_response :success
    assert_equal "Larger logo", cards(:logo).reload.title
  end

  test "search and fetch return company knowledge compatible payloads" do
    cards(:logo).update!(description: "The mark should be larger.")
    cards(:logo).reindex

    untenanted do
      post mcp_path,
        params: tool_call("search", account_id: @account_id, query: "logo", limit: 5).to_json,
        headers: json_headers(@write_token)
    end

    assert_response :success
    result = @response.parsed_body.dig("result", "structuredContent", "results").first
    assert_equal cards(:logo).id, result["id"]
    assert result["url"].present?

    untenanted do
      post mcp_path,
        params: tool_call("fetch", id: result["id"]).to_json,
        headers: json_headers(@write_token)
    end

    assert_response :success
    fetched = @response.parsed_body.dig("result", "structuredContent")
    assert_equal cards(:logo).id, fetched["id"]
    assert_equal cards(:logo).title, fetched["title"]
    assert fetched["metadata"].present?
  end

  private
    def json_headers(token = nil)
      { "CONTENT_TYPE" => "application/json", "ACCEPT" => "application/json" }.tap do |headers|
        headers["Authorization"] = "Bearer #{token}" if token
      end
    end

    def json_rpc(method, params: {}, id: 1)
      { jsonrpc: "2.0", id: id, method: method, params: params }
    end

    def tool_call(name, **arguments)
      json_rpc("tools/call", params: { name: name, arguments: arguments })
    end
end
