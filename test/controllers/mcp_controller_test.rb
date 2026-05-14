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

  test "discovery advertises tools resources and oauth metadata" do
    untenanted do
      get mcp_discovery_path
    end

    assert_response :success
    discovery = @response.parsed_body
    assert_equal "Fizzy", discovery["title"]
    assert_equal "2025-11-25", discovery["protocolVersion"]
    assert discovery.dig("capabilities", "tools").present?
    assert discovery.dig("capabilities", "resources").present?
    assert_equal oauth_authorization_server_url(script_name: nil), discovery["authorization_server"]
    assert_equal oauth_protected_resource_url(script_name: nil), discovery["protected_resource"]
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

  test "chatgpt current protocol can initialize and list tools" do
    untenanted do
      post mcp_path,
        params: json_rpc("initialize", params: {
          protocolVersion: "2025-11-25",
          capabilities: {
            experimental: {
              "openai/visibility" => { enabled: true }
            },
            extensions: {
              "io.modelcontextprotocol/ui" => {
                mimeTypes: [ "text/html;profile=mcp-app" ]
              }
            }
          },
          clientInfo: { name: "openai-mcp (ChatGPT)", version: "1.0.0" }
        }).to_json,
        headers: json_headers(@read_token)
    end

    assert_response :success
    assert_equal "2025-11-25", @response.parsed_body.dig("result", "protocolVersion")

    untenanted do
      post mcp_path, params: json_rpc("tools/list").to_json,
        headers: json_headers(@read_token).merge("MCP-Protocol-Version" => "2025-11-25")
    end

    assert_response :success
    assert @response.parsed_body.dig("result", "tools").any? { |tool| tool["name"] == "account_list" }
  end

  test "unsupported initialize protocol version is rejected" do
    untenanted do
      post mcp_path, params: json_rpc("initialize", params: { protocolVersion: "2024-11-05" }).to_json,
        headers: json_headers(@read_token)
    end

    assert_response :success
    assert_equal -32602, @response.parsed_body.dig("error", "code")
    assert_equal "Unsupported protocol version", @response.parsed_body.dig("error", "message")
  end

  test "unsupported protocol header is rejected after initialize" do
    untenanted do
      post mcp_path, params: json_rpc("tools/list").to_json,
        headers: json_headers(@read_token).merge("MCP-Protocol-Version" => "2024-11-05")
    end

    assert_response :bad_request
    assert_equal -32602, @response.parsed_body.dig("error", "code")
  end

  test "read token cannot call write tool" do
    untenanted do
      post mcp_path,
        params: tool_call("card_create", account_id: @account_id, board_id: boards(:writebook).id, title: "Nope").to_json,
        headers: json_headers(@read_token)
    end

    assert_response :forbidden
  end

  test "read token cannot create a board" do
    untenanted do
      post mcp_path,
        params: tool_call("board_create", account_id: @account_id, name: "Nope").to_json,
        headers: json_headers(@read_token)
    end

    assert_response :forbidden
  end

  test "write tools advertise read and write scopes with golden ticket fields" do
    untenanted do
      post mcp_path, params: json_rpc("tools/list").to_json, headers: json_headers(@write_token)
    end

    assert_response :success
    tools = @response.parsed_body.dig("result", "tools")
    board_create = tools.find { |tool| tool["name"] == "board_create" }
    card_update = tools.find { |tool| tool["name"] == "card_update" }

    assert_equal [ "read", "write" ], board_create.dig("securitySchemes", 0, "scopes")
    assert_equal false, board_create.dig("annotations", "readOnlyHint")
    assert_equal [ "account_id", "name" ], board_create.dig("inputSchema", "required")
    assert_equal "array", board_create.dig("inputSchema", "properties", "columns", "type")
    assert_equal [ "read", "write" ], card_update.dig("securitySchemes", 0, "scopes")
    assert_equal [ "read", "write" ], card_update.dig("_meta", "securitySchemes", 0, "scopes")
    assert_equal false, card_update.dig("annotations", "readOnlyHint")
    assert_equal false, card_update.dig("annotations", "destructiveHint")
    assert_includes card_update.dig("inputSchema", "properties", "description", "description"), "HTML"
    assert_equal "array", card_update.dig("inputSchema", "properties", "tag_titles", "type")
    assert_equal "array", card_update.dig("inputSchema", "properties", "steps", "type")
    assert_equal "boolean", card_update.dig("inputSchema", "properties", "golden", "type")
    assert tools.any? { |tool| tool["name"] == "move_card" }
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

  test "write token can create a board with columns and then create a card on it" do
    assert_difference -> { Board.count }, +1 do
      assert_difference -> { Column.count }, +2 do
        untenanted do
          post mcp_path,
            params: tool_call("board_create",
              account_id: @account_id,
              title: "Agent Heartbeat",
              description: "<p>Tracks agent heartbeat work.</p>",
              columns: [ "Inbox", "Done" ]
            ).to_json,
            headers: json_headers(@write_token)
        end
      end
    end

    assert_response :success
    payload = @response.parsed_body.dig("result", "structuredContent")
    board = Board.find(payload.dig("board", "id"))

    assert_equal "Agent Heartbeat", board.name
    assert_equal "Tracks agent heartbeat work.", board.public_description.to_plain_text
    assert_equal users(:david), board.creator
    assert board.all_access?
    assert_includes payload.dig("board", "url"), board.id
    assert_equal [ "Inbox", "Done" ], payload["columns"].map { |column| column["name"] }

    assert_difference -> { board.cards.count }, +1 do
      untenanted do
        post mcp_path,
          params: tool_call("card_create",
            account_id: @account_id,
            board_id: board.id,
            title: "Heartbeat card"
          ).to_json,
          headers: json_headers(@write_token)
      end
    end

    assert_response :success
    assert_equal "Heartbeat card", board.cards.last.title
  end

  test "write token can create a golden ticket card with html tags and steps" do
    assert_difference -> { boards(:writebook).cards.count }, +1 do
      untenanted do
        post mcp_path,
          params: tool_call("card_create",
            account_id: @account_id,
            board_id: boards(:writebook).id,
            title: "Agent golden ticket",
            description: "<p>Use <strong>board instructions</strong>.</p><ul><li>Keep card updated</li></ul>",
            tag_titles: [ "#agent-instructions", "#move-to-done" ],
            steps: [ "Research context", "Update Fizzy" ],
            golden: true
          ).to_json,
          headers: json_headers(@write_token)
      end
    end

    assert_response :success
    card = boards(:writebook).cards.find_by!(title: "Agent golden ticket")
    assert_includes card.description.to_s, "<strong>board instructions</strong>"
    assert_includes card.description.to_s, "<li>Keep card updated</li>"
    assert_equal [ "agent-instructions", "move-to-done" ], card.tags.pluck(:title).sort
    assert_equal [ "Research context", "Update Fizzy" ], card.steps.order(:created_at, :id).pluck(:content)
    assert card.golden?

    payload = @response.parsed_body.dig("result", "structuredContent", "card")
    assert_equal true, payload["golden"]
    assert_includes payload["description_html"], "<strong>board instructions</strong>"
    assert_equal [ "#agent-instructions", "#move-to-done" ], payload["tags"].sort
    assert_equal [ "Research context", "Update Fizzy" ], payload["steps"].map { |step| step["content"] }
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

  test "write token can update html description and golden ticket metadata idempotently" do
    card = cards(:text)

    untenanted do
      post mcp_path,
        params: tool_call("card_update",
          account_id: @account_id,
          card_id: card.id,
          description: "<p>Follow <a href=\"https://example.com\">ticket source</a>.</p>",
          tag_titles: [ "#agent-instructions" ],
          steps: [ "Check ticket email" ],
          golden: true
        ).to_json,
        headers: json_headers(@write_token)
    end

    assert_response :success
    card.reload
    assert_includes card.description.to_s, %(<a href="https://example.com">ticket source</a>)
    assert_includes card.tags.pluck(:title), "agent-instructions"
    assert_equal [ "Check ticket email" ], card.steps.pluck(:content)
    assert card.golden?

    assert_no_difference -> { card.steps.count } do
      untenanted do
        post mcp_path,
          params: tool_call("card_update",
            account_id: @account_id,
            card_id: card.id,
            tag_titles: [ "#agent-instructions" ],
            steps: [ "Check ticket email" ],
            golden: true
          ).to_json,
          headers: json_headers(@write_token)
      end
    end

    assert_response :success
  end

  test "write token can move a card by ergonomic targets and column id" do
    card = cards(:logo)

    untenanted do
      post mcp_path,
        params: tool_call("move_card", account_id: @account_id, card_id: card.id, target: "next").to_json,
        headers: json_headers(@write_token)
    end

    assert_response :success
    assert_equal columns(:writebook_in_progress), card.reload.column

    untenanted do
      post mcp_path,
        params: tool_call("move_card", account_id: @account_id, card_id: card.id, target: "backlog").to_json,
        headers: json_headers(@write_token)
    end

    assert_response :success
    assert_equal columns(:writebook_triage), card.reload.column

    untenanted do
      post mcp_path,
        params: tool_call("move_card", account_id: @account_id, card_id: card.id, target: "Review").to_json,
        headers: json_headers(@write_token)
    end

    assert_response :success
    assert_equal columns(:writebook_review), card.reload.column

    untenanted do
      post mcp_path,
        params: tool_call("move_card", account_id: @account_id, card_id: card.id, column_id: columns(:writebook_on_hold).id, target: "ignored").to_json,
        headers: json_headers(@write_token)
    end

    assert_response :success
    assert_equal columns(:writebook_on_hold), card.reload.column

    untenanted do
      post mcp_path,
        params: tool_call("move_card", account_id: @account_id, card_id: card.id, target: "done").to_json,
        headers: json_headers(@write_token)
    end

    assert_response :success
    assert card.reload.closed?
  end

  test "write token can move a card with destination alias" do
    card = cards(:logo)

    untenanted do
      post mcp_path,
        params: tool_call("move_card", account_id: @account_id, card_id: card.id, destination: "next").to_json,
        headers: json_headers(@write_token)
    end

    assert_response :success
    assert_equal columns(:writebook_in_progress), card.reload.column
  end

  test "read token cannot move a card" do
    untenanted do
      post mcp_path,
        params: tool_call("move_card", account_id: @account_id, card_id: cards(:logo).id, target: "next").to_json,
        headers: json_headers(@read_token)
    end

    assert_response :forbidden
  end

  test "resources list and read account board and card resources" do
    untenanted do
      post mcp_path, params: json_rpc("resources/list").to_json, headers: json_headers(@write_token)
    end

    assert_response :success
    resources = @response.parsed_body.dig("result", "resources")
    assert resources.any? { |resource| resource["uri"] == "fizzy://accounts" }
    assert resources.any? { |resource| resource["uri"] == "fizzy://accounts/#{accounts(:'37s').id}/overview" }

    assert_resource_read "fizzy://accounts", "accounts"
    assert_resource_read "fizzy://accounts/#{accounts(:'37s').id}/overview", "account"
    assert_resource_read "fizzy://accounts/#{accounts(:'37s').id}/boards/#{boards(:writebook).id}", "board"
    assert_resource_read "fizzy://accounts/#{accounts(:'37s').id}/cards/#{cards(:logo).id}", "card"
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

    def assert_resource_read(uri, expected_key)
      untenanted do
        post mcp_path, params: json_rpc("resources/read", params: { uri: uri }).to_json, headers: json_headers(@write_token)
      end

      assert_response :success
      content = @response.parsed_body.dig("result", "contents").first
      assert_equal uri, content["uri"]
      assert_equal "application/json", content["mimeType"]
      assert JSON.parse(content["text"])[expected_key].present?
    end
end
