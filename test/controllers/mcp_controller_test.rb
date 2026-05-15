require "test_helper"

class McpControllerTest < ActionDispatch::IntegrationTest
  setup do
    @read_token = fixture_access_token(:jasons_api_token)
    @write_token = fixture_access_token(:davids_api_token)
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

  test "oauth bearer token must match the mcp resource audience" do
    client = Oauth::Client.create!(
      client_name: "ChatGPT",
      redirect_uris: [ "https://chat.openai.com/aip/plugin/oauth/callback" ],
      scope: "read write"
    )
    wrong_resource_token = identities(:david).access_tokens.create!(
      description: "Wrong audience",
      permission: "write",
      oauth_client: client,
      resource: "https://example.test/mcp"
    ).token

    untenanted do
      post mcp_path, params: json_rpc("initialize").to_json, headers: json_headers(wrong_resource_token)
    end

    assert_response :unauthorized

    right_resource_token = identities(:david).access_tokens.create!(
      description: "Right audience",
      permission: "write",
      oauth_client: client,
      resource: mcp_url(script_name: nil)
    ).token

    untenanted do
      post mcp_path, params: json_rpc("initialize").to_json, headers: json_headers(right_resource_token)
    end

    assert_response :success
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

    assert_insufficient_scope_tool_result
  end

  test "read token cannot create a board" do
    untenanted do
      post mcp_path,
        params: tool_call("board_create", account_id: @account_id, name: "Nope").to_json,
        headers: json_headers(@read_token)
    end

    assert_insufficient_scope_tool_result
  end

  test "read token cannot update a column" do
    untenanted do
      post mcp_path,
        params: tool_call("column_update",
          account_id: @account_id,
          board_id: boards(:writebook).id,
          column_id: columns(:writebook_triage).id,
          color: "Aqua"
        ).to_json,
        headers: json_headers(@read_token)
    end

    assert_insufficient_scope_tool_result
  end

  test "write tools advertise read and write scopes with golden ticket fields" do
    untenanted do
      post mcp_path, params: json_rpc("tools/list").to_json, headers: json_headers(@write_token)
    end

    assert_response :success
    tools = @response.parsed_body.dig("result", "tools")
    tools.each { |tool| assert_openai_tool_schema_compatible(tool) }
    board_create = tools.find { |tool| tool["name"] == "board_create" }
    column_update = tools.find { |tool| tool["name"] == "column_update" }
    card_update = tools.find { |tool| tool["name"] == "card_update" }

    assert_equal [ "read", "write" ], board_create.dig("securitySchemes", 0, "scopes")
    assert_equal false, board_create.dig("annotations", "readOnlyHint")
    assert_equal false, board_create.dig("annotations", "openWorldHint")
    assert_match(/\AUse this when/, board_create["description"])
    assert_equal [ "account_id", "name" ], board_create.dig("inputSchema", "required")
    assert_nil board_create.dig("inputSchema", "anyOf")
    assert_equal "array", board_create.dig("inputSchema", "properties", "columns", "type")
    assert_equal "string", board_create.dig("inputSchema", "properties", "columns", "items", "type")
    assert_includes board_create.dig("inputSchema", "properties", "columns", "description"), "plain column name strings"
    assert_includes board_create.dig("inputSchema", "properties", "columns", "description"), "Do not include"
    assert_equal [ "read", "write" ], column_update.dig("securitySchemes", 0, "scopes")
    assert_equal false, column_update.dig("annotations", "readOnlyHint")
    assert_equal false, column_update.dig("annotations", "destructiveHint")
    assert_equal [ "account_id", "board_id", "column_id" ], column_update.dig("inputSchema", "required")
    assert_nil column_update.dig("inputSchema", "anyOf")
    assert_includes column_update.dig("inputSchema", "properties", "color", "description"), "Aqua"
    assert_includes column_update.dig("inputSchema", "properties", "color", "description"), "var(--color-card-5)"
    assert_equal [ "read", "write" ], card_update.dig("securitySchemes", 0, "scopes")
    assert_equal [ "read", "write" ], card_update.dig("_meta", "securitySchemes", 0, "scopes")
    assert_equal false, card_update.dig("annotations", "readOnlyHint")
    assert_equal true, card_update.dig("annotations", "destructiveHint")
    assert_equal false, card_update.dig("annotations", "openWorldHint")
    assert_includes card_update.dig("inputSchema", "properties", "description", "description"), "HTML"
    assert_equal "array", card_update.dig("inputSchema", "properties", "tag_titles", "type")
    assert_equal "array", card_update.dig("inputSchema", "properties", "steps", "type")
    assert_equal "boolean", card_update.dig("inputSchema", "properties", "golden", "type")
    assert tools.any? { |tool| tool["name"] == "move_card" }
  end

  test "tools list can disable advertised mcp tools from environment" do
    with_env "FIZZY_MCP_DISABLED_TOOLS", "_board_create, card_update" do
      untenanted do
        post mcp_path, params: json_rpc("tools/list").to_json, headers: json_headers(@write_token)
      end
    end

    assert_response :success
    tool_names = @response.parsed_body.dig("result", "tools").pluck("name")

    assert_not_includes tool_names, "board_create"
    assert_not_includes tool_names, "card_update"
    assert_includes tool_names, "board_list"
  end

  test "tools advertise output schemas for structured content" do
    untenanted do
      post mcp_path, params: json_rpc("tools/list").to_json, headers: json_headers(@write_token)
    end

    assert_response :success
    tools = @response.parsed_body.dig("result", "tools")

    assert tools.all? { |tool| tool["outputSchema"].present? }, "Every tool should advertise outputSchema"

    account_list = tools.find { |tool| tool["name"] == "account_list" }
    board_create = tools.find { |tool| tool["name"] == "board_create" }
    column_update = tools.find { |tool| tool["name"] == "column_update" }
    fetch = tools.find { |tool| tool["name"] == "fetch" }
    search = tools.find { |tool| tool["name"] == "search" }

    assert_equal [ "query" ], search.dig("inputSchema", "properties").keys
    assert_equal [ "id" ], fetch.dig("inputSchema", "properties").keys
    assert_equal "array", account_list.dig("outputSchema", "properties", "accounts", "type")
    assert_equal "array", board_create.dig("outputSchema", "properties", "columns", "type")
    assert_equal "array", board_create.dig("outputSchema", "properties", "system_columns", "type")
    assert_equal "string", board_create.dig("outputSchema", "properties", "board", "properties", "public_description_html", "type")
    assert_equal "object", column_update.dig("outputSchema", "properties", "column", "type")
    assert_equal "string", column_update.dig("outputSchema", "properties", "column", "properties", "color", "type")
    assert_equal "string", fetch.dig("outputSchema", "properties", "text", "type")
    assert_equal "object", fetch.dig("outputSchema", "properties", "metadata", "type")
  end

  test "column list returns colors matching its output schema" do
    untenanted do
      post mcp_path, params: json_rpc("tools/list").to_json, headers: json_headers(@write_token)
    end

    assert_response :success
    column_list = @response.parsed_body.dig("result", "tools").find { |tool| tool["name"] == "column_list" }
    assert_equal "string", column_list.dig("outputSchema", "properties", "columns", "items", "properties", "color", "type")

    untenanted do
      post mcp_path,
        params: tool_call("column_list", account_id: @account_id, board_id: boards(:writebook).id).to_json,
        headers: json_headers(@write_token)
    end

    assert_response :success
    color = @response.parsed_body.dig("result", "structuredContent", "columns").first["color"]
    assert_kind_of String, color
    assert_equal [ "Maybe?", "Not Now", "Done" ], @response.parsed_body.dig("result", "structuredContent", "system_columns")
  end

  test "write token can update a column color" do
    column = columns(:writebook_in_progress)

    untenanted do
      post mcp_path,
        params: tool_call("column_update",
          account_id: @account_id,
          board_id: boards(:writebook).id,
          column_id: column.id,
          name: "Doing",
          color: "Aqua"
        ).to_json,
        headers: json_headers(@write_token)
    end

    assert_response :success
    assert_equal "Doing", column.reload.name
    assert_equal Color.for_value("var(--color-card-5)"), column.color
    assert_equal "Doing", @response.parsed_body.dig("result", "structuredContent", "column", "name")
    assert_equal "var(--color-card-5)", @response.parsed_body.dig("result", "structuredContent", "column", "color")
  end

  test "column update rejects unknown colors" do
    column = columns(:writebook_in_progress)

    untenanted do
      post mcp_path,
        params: tool_call("column_update",
          account_id: @account_id,
          board_id: boards(:writebook).id,
          column_id: column.id,
          color: "chartreuse"
        ).to_json,
        headers: json_headers(@write_token)
    end

    assert_response :success
    assert_equal -32602, @response.parsed_body.dig("error", "code")
    assert_match "color must be one of", @response.parsed_body.dig("error", "message")
    assert_equal "var(--color-card-2)", column.reload.color.to_s
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
              columns: [ "Inbox", "Review" ]
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
    assert_equal [ "Inbox", "Review" ], payload["columns"].map { |column| column["name"] }
    assert_equal [ "Maybe?", "Not Now", "Done" ], payload["system_columns"]

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

  test "board create accepts common column object input and skips system columns" do
    assert_difference -> { Board.count }, +1 do
      assert_difference -> { Column.count }, +3 do
        untenanted do
          post mcp_path,
            params: tool_call("board_create",
              account_id: @account_id,
              name: "ChatGPT Board",
              columns: [
                { name: "To Do", color: "Gray" },
                { title: "In Progress", color: "var(--color-card-5)" },
                "Review",
                "Done",
                "Not Now",
                "Maybe"
              ]
            ).to_json,
            headers: json_headers(@write_token)
        end
      end
    end

    assert_response :success
    payload = @response.parsed_body.dig("result", "structuredContent")
    board = Board.find(payload.dig("board", "id"))

    assert_equal [ "To Do", "In Progress", "Review" ], board.columns.sorted.pluck(:name)
    assert_equal [ "To Do", "In Progress", "Review" ], payload["columns"].map { |column| column["name"] }
    assert_equal [ "var(--color-card-1)", "var(--color-card-5)", "var(--color-card-default)" ], payload["columns"].map { |column| column["color"] }
    assert_equal [ "Maybe?", "Not Now", "Done" ], payload["system_columns"]
  end

  test "board create keeps one requested workflow column separate from system columns" do
    assert_difference -> { Board.count }, +1 do
      assert_difference -> { Column.count }, +1 do
        untenanted do
          post mcp_path,
            params: tool_call("board_create",
              account_id: @account_id,
              name: "Sauce Board",
              columns: [ "Maybe?", "AwesomeSauce", "Not Now", "Done" ]
            ).to_json,
            headers: json_headers(@write_token)
        end
      end
    end

    assert_response :success
    payload = @response.parsed_body.dig("result", "structuredContent")
    board = Board.find(payload.dig("board", "id"))

    assert_equal [ "AwesomeSauce" ], board.columns.sorted.pluck(:name)
    assert_equal [ "AwesomeSauce" ], payload["columns"].map { |column| column["name"] }
    assert_equal [ "Maybe?", "Not Now", "Done" ], payload["system_columns"]
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
    payload = @response.parsed_body.dig("result", "structuredContent")
    assert_equal "Done", payload.dig("card", "status")
    assert_equal "Done", payload.dig("metadata", "status")
    assert_nil payload.dig("card", "column")

    untenanted do
      post mcp_path,
        params: tool_call("move_card", account_id: @account_id, card_id: card.id, target: "maybe").to_json,
        headers: json_headers(@write_token)
    end

    assert_response :success
    assert card.reload.awaiting_triage?
    payload = @response.parsed_body.dig("result", "structuredContent")
    assert_equal "Maybe?", payload.dig("card", "status")
    assert_nil payload.dig("card", "column")
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

  test "write token can move a card to not now" do
    card = cards(:text)

    assert_difference -> { card.reload.events.where(action: "card_postponed").count }, +1 do
      untenanted do
        post mcp_path,
          params: tool_call("move_card", account_id: @account_id, card_id: card.id, target: "not_now").to_json,
          headers: json_headers(@write_token)
      end
    end

    assert_response :success
    assert card.reload.postponed?
    payload = @response.parsed_body.dig("result", "structuredContent")
    assert_equal "Not Now", payload.dig("card", "status")
    assert_nil payload.dig("card", "column")
  end

  test "card update column id uses board transitions" do
    card = cards(:buy_domain)

    assert_difference -> { card.reload.events.where(action: "card_triaged").count }, +1 do
      untenanted do
        post mcp_path,
          params: tool_call("card_update", account_id: @account_id, card_id: card.id, column_id: columns(:writebook_review).id).to_json,
          headers: json_headers(@write_token)
      end
    end

    assert_response :success
    assert_equal columns(:writebook_review), card.reload.column

    assert_difference -> { card.reload.events.where(action: "card_sent_back_to_triage").count }, +1 do
      untenanted do
        post mcp_path,
          params: tool_call("card_update", account_id: @account_id, card_id: card.id, column_id: nil).to_json,
          headers: json_headers(@write_token)
      end
    end

    assert_response :success
    assert card.reload.awaiting_triage?
    assert_equal "Maybe?", @response.parsed_body.dig("result", "structuredContent", "card", "status")
  end

  test "numeric card ids require account id" do
    second_user = accounts(:initech).users.create!(name: "David", identity: identities(:david), role: "member", verified_at: Time.current)
    Access.find_or_create_by!(account: accounts(:initech), user: second_user, board: boards(:miltons_wish_list))

    untenanted do
      post mcp_path,
        params: tool_call("card_update", card_id: "1", title: "Wrong card").to_json,
        headers: json_headers(@write_token)
    end

    assert_response :success
    assert_equal -32602, @response.parsed_body.dig("error", "code")
    assert_equal "account_id is required when card_id is a card number", @response.parsed_body.dig("error", "message")
    assert_equal "The logo isn't big enough", cards(:logo).reload.title
    assert_equal "I want to play my radio at a reasonable volume", cards(:radio).reload.title
  end

  test "read token cannot move a card" do
    untenanted do
      post mcp_path,
        params: tool_call("move_card", account_id: @account_id, card_id: cards(:logo).id, target: "next").to_json,
        headers: json_headers(@read_token)
    end

    assert_insufficient_scope_tool_result
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

  test "resources use system columns and visible card statuses" do
    cards(:logo).close(user: users(:david))
    cards(:text).postpone(user: users(:david))

    board_payload = assert_resource_read "fizzy://accounts/#{accounts(:'37s').id}/boards/#{boards(:writebook).id}", "board"
    assert_equal [ "Maybe?", "Not Now", "Done" ], board_payload["system_columns"]

    closed_payload = assert_resource_read "fizzy://accounts/#{accounts(:'37s').id}/cards/#{cards(:logo).id}", "card"
    assert_equal "Done", closed_payload.dig("card", "status")
    assert_nil closed_payload.dig("card", "column_id")

    postponed_payload = assert_resource_read "fizzy://accounts/#{accounts(:'37s').id}/cards/#{cards(:text).id}", "card"
    assert_equal "Not Now", postponed_payload.dig("card", "status")
    assert_nil postponed_payload.dig("card", "column_id")

    maybe_payload = assert_resource_read "fizzy://accounts/#{accounts(:'37s').id}/cards/#{cards(:buy_domain).id}", "card"
    assert_equal "Maybe?", maybe_payload.dig("card", "status")
    assert_nil maybe_payload.dig("card", "column_id")
  end

  test "malformed json rpc requests return invalid request errors" do
    untenanted do
      post mcp_path, params: "[]", headers: json_headers(@write_token)
    end

    assert_response :success
    assert_equal -32600, @response.parsed_body.first.dig("error", "code")

    untenanted do
      post mcp_path,
        params: json_rpc("tools/call", params: { name: "account_list", arguments: [] }).to_json,
        headers: json_headers(@write_token)
    end

    assert_response :success
    assert_equal -32602, @response.parsed_body.dig("error", "code")
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
      JSON.parse(content["text"]).tap { |payload| assert payload[expected_key].present? }
    end

    def assert_insufficient_scope_tool_result
      assert_response :success
      result = @response.parsed_body["result"]
      assert_equal true, result["isError"]
      assert_equal "Insufficient scope", result.dig("content", 0, "text")
      assert_match "insufficient_scope", result.dig("_meta", "mcp/www_authenticate")
      assert_match "resource_metadata=", result.dig("_meta", "mcp/www_authenticate")
    end

    def assert_openai_tool_schema_compatible(tool)
      schema = tool["inputSchema"]
      assert_equal "object", schema["type"], "#{tool["name"]} inputSchema must be an object"

      unsupported_paths = unsupported_json_schema_keyword_paths(schema, "#{tool["name"]}.inputSchema")
      assert_empty unsupported_paths, "OpenAI rejects these MCP input schema keywords: #{unsupported_paths.join(", ")}"
    end

    def unsupported_json_schema_keyword_paths(value, path)
      case value
      when Hash
        value.flat_map do |key, nested|
          paths = %w[ oneOf anyOf allOf enum not ].include?(key.to_s) ? [ "#{path}.#{key}" ] : []
          paths + unsupported_json_schema_keyword_paths(nested, "#{path}.#{key}")
        end
      when Array
        value.each_with_index.flat_map { |nested, index| unsupported_json_schema_keyword_paths(nested, "#{path}[#{index}]") }
      else
        []
      end
    end

    def with_env(name, value)
      previous = ENV[name]
      ENV[name] = value
      yield
    ensure
      ENV[name] = previous
    end
end
