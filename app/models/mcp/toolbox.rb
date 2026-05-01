class Mcp::Toolbox
  class Error < StandardError
    attr_reader :code

    def initialize(message, code: -32000)
      @code = code
      super(message)
    end
  end

  class Forbidden < Error
    def initialize(message = "Insufficient scope")
      super(message, code: -32003)
    end
  end

  WRITE_TOOLS = %w[ card_create card_update comment_create ].freeze

  class << self
    def tool_definitions
      [
        read_tool("search", "Search cards", "Search accessible Fizzy cards.", {
          query: string_schema("Search terms"),
          account_id: string_schema("Account id or account slug"),
          limit: integer_schema("Maximum results")
        }, required: [ "query" ]),
        read_tool("fetch", "Fetch card", "Fetch one accessible Fizzy card for search result hydration.", {
          id: string_schema("Card id returned by search"),
          account_id: string_schema("Account id or account slug")
        }, required: [ "id" ]),
        read_tool("identity_show", "Show identity", "Show the linked Fizzy identity.", {}),
        read_tool("account_list", "List accounts", "List active Fizzy accounts available to the identity.", {}),
        read_tool("board_list", "List boards", "List accessible boards in an account.", {
          account_id: string_schema("Account id or account slug"),
          limit: integer_schema("Maximum results")
        }, required: [ "account_id" ]),
        read_tool("board_show", "Show board", "Show one accessible board.", {
          account_id: string_schema("Account id or account slug"),
          board_id: string_schema("Board id")
        }, required: [ "account_id", "board_id" ]),
        read_tool("column_list", "List columns", "List columns on an accessible board.", {
          account_id: string_schema("Account id or account slug"),
          board_id: string_schema("Board id")
        }, required: [ "account_id", "board_id" ]),
        read_tool("card_list", "List cards", "List accessible cards in an account, board, or column.", {
          account_id: string_schema("Account id or account slug"),
          board_id: string_schema("Board id"),
          column_id: string_schema("Column id"),
          limit: integer_schema("Maximum results")
        }, required: [ "account_id" ]),
        read_tool("card_show", "Show card", "Show one accessible card.", {
          account_id: string_schema("Account id or account slug"),
          card_id: string_schema("Card id or card number")
        }, required: [ "card_id" ]),
        write_tool("card_create", "Create card", "Create a published card on an accessible board.", {
          account_id: string_schema("Account id or account slug"),
          board_id: string_schema("Board id"),
          column_id: string_schema("Column id"),
          title: string_schema("Card title"),
          description: string_schema("Card description")
        }, required: [ "account_id", "board_id", "title" ]),
        write_tool("card_update", "Update card", "Update title, description, or column for an accessible card.", {
          account_id: string_schema("Account id or account slug"),
          card_id: string_schema("Card id or card number"),
          title: string_schema("Card title"),
          description: string_schema("Card description"),
          column_id: string_schema("Column id")
        }, required: [ "card_id" ]),
        read_tool("comment_list", "List comments", "List comments on an accessible card.", {
          account_id: string_schema("Account id or account slug"),
          card_id: string_schema("Card id or card number"),
          limit: integer_schema("Maximum results")
        }, required: [ "card_id" ]),
        write_tool("comment_create", "Create comment", "Create a comment on an accessible card.", {
          account_id: string_schema("Account id or account slug"),
          card_id: string_schema("Card id or card number"),
          body: string_schema("Comment body")
        }, required: [ "card_id", "body" ])
      ]
    end

    private
      def read_tool(name, title, description, properties, required: [])
        tool(name, title, description, properties, required: required, scopes: [ "read" ], read_only: true)
      end

      def write_tool(name, title, description, properties, required: [])
        tool(name, title, description, properties, required: required, scopes: [ "write" ], read_only: false)
      end

      def tool(name, title, description, properties, required:, scopes:, read_only:)
        security_schemes = [ { type: "oauth2", scopes: scopes } ]

        {
          name: name,
          title: title,
          description: description,
          inputSchema: {
            type: "object",
            properties: properties,
            required: required
          },
          annotations: { readOnlyHint: read_only },
          securitySchemes: security_schemes,
          _meta: { securitySchemes: security_schemes }
        }
      end

      def string_schema(description)
        { type: "string", description: description }
      end

      def integer_schema(description)
        { type: "integer", description: description, minimum: 1, maximum: 50 }
      end
  end

  def initialize(access_token:, url_context:)
    @access_token = access_token
    @identity = access_token.identity
    @url_context = url_context
  end

  def call(name, arguments)
    raise Error.new("Unknown tool", code: -32602) unless tool_name?(name)
    raise Forbidden if write_tool?(name) && !@access_token.write?

    result public_send(name, arguments.to_h)
  end

  def search(arguments)
    query = required_argument(arguments, "query")
    limit = limit_for(arguments)

    cards = if account_identifier(arguments).present?
      with_account(account_identifier(arguments)) { |account, user| search_cards(user, query, limit) }
    else
      each_account.flat_map { |account, user| with_current(account, user) { search_cards(user, query, limit) } }.first(limit)
    end

    {
      results: cards.map { |account, card| search_result_hash(account, card) }
    }
  end

  def fetch(arguments)
    account, _user, card = find_card(arguments.merge("card_id" => required_argument(arguments, "id")))

    {
      id: card.id,
      title: card.title,
      text: card.description.to_plain_text,
      url: card_url(account, card),
      metadata: card_metadata(account, card)
    }
  end

  def identity_show(_arguments)
    {
      id: @identity.id,
      email_address: @identity.email_address
    }
  end

  def account_list(_arguments)
    {
      accounts: each_account.map { |account, user| account_hash(account, user) }
    }
  end

  def board_list(arguments)
    with_account(required_account_identifier(arguments)) do |_account, user|
      {
        boards: user.boards.ordered_by_recently_accessed.includes(:creator).limit(limit_for(arguments)).map { |board| board_hash(board) }
      }
    end
  end

  def board_show(arguments)
    with_account(required_account_identifier(arguments)) do |_account, user|
      board = user.boards.find(required_argument(arguments, "board_id"))

      {
        board: board_hash(board),
        columns: board.columns.sorted.map { |column| column_hash(column) }
      }
    end
  end

  def column_list(arguments)
    with_account(required_account_identifier(arguments)) do |_account, user|
      board = user.boards.find(required_argument(arguments, "board_id"))

      {
        columns: board.columns.sorted.map { |column| column_hash(column) }
      }
    end
  end

  def card_list(arguments)
    with_account(required_account_identifier(arguments)) do |account, user|
      cards = user.accessible_cards.published.preloaded.latest
      cards = cards.where(board_id: arguments["board_id"]) if arguments["board_id"].present?
      cards = cards.where(column_id: arguments["column_id"]) if arguments["column_id"].present?

      {
        cards: cards.limit(limit_for(arguments)).map { |card| card_hash(account, card) }
      }
    end
  end

  def card_show(arguments)
    account, _user, card = find_card(arguments)

    {
      card: card_hash(account, card),
      text: card.description.to_plain_text,
      metadata: card_metadata(account, card)
    }
  end

  def card_create(arguments)
    with_account(required_account_identifier(arguments)) do |account, user|
      board = user.boards.find(required_argument(arguments, "board_id"))
      attributes = {
        title: required_argument(arguments, "title"),
        description: arguments["description"],
        creator: user,
        status: "published"
      }

      attributes[:column] = board.columns.find(arguments["column_id"]) if arguments["column_id"].present?
      card = board.cards.create!(attributes)

      {
        card: card_hash(account, card.reload),
        metadata: card_metadata(account, card)
      }
    end
  end

  def card_update(arguments)
    with_found_card(arguments) do |account, _user, card|
      attributes = arguments.slice("title", "description")

      if arguments.key?("column_id")
        attributes[:column] = arguments["column_id"].present? ? card.board.columns.find(arguments["column_id"]) : nil
      end

      card.update!(attributes)

      {
        card: card_hash(account, card.reload),
        metadata: card_metadata(account, card)
      }
    end
  end

  def comment_list(arguments)
    account, _user, card = find_card(arguments)

    {
      comments: card.comments.chronologically.preloaded.limit(limit_for(arguments)).map { |comment| comment_hash(account, comment) }
    }
  end

  def comment_create(arguments)
    with_found_card(arguments) do |account, user, card|
      comment = card.comments.create!(creator: user, body: required_argument(arguments, "body"))

      {
        comment: comment_hash(account, comment.reload)
      }
    end
  end

  private
    def result(payload)
      {
        content: [ { type: "text", text: JSON.pretty_generate(payload) } ],
        structuredContent: payload,
        isError: false
      }
    end

    def tool_name?(name)
      self.class.tool_definitions.any? { |tool| tool[:name] == name }
    end

    def write_tool?(name)
      name.in?(WRITE_TOOLS)
    end

    def search_cards(user, query, limit)
      search_records = Search::Record.for(user.account_id).search(query, user: user).limit(limit)
      cards = search_records.map(&:card).uniq
      cards = fallback_search_cards(user, query, limit) if cards.empty?
      cards.map { |card| [ user.account, card ] }
    end

    def fallback_search_cards(user, query, limit)
      user.accessible_cards.published.preloaded.latest.select do |card|
        card.title.to_s.match?(/#{Regexp.escape(query)}/i) ||
          card.description.to_plain_text.match?(/#{Regexp.escape(query)}/i)
      end.first(limit)
    end

    def find_card(arguments)
      with_found_card(arguments) { |account, user, card| [ account, user, card ] }
    end

    def with_found_card(arguments)
      if account_identifier(arguments).present?
        with_account(account_identifier(arguments)) do |account, user|
          yield account, user, find_card_for_user(user, required_argument(arguments, "card_id"))
        end
      else
        each_account.each do |account, user|
          result = with_current(account, user) do
            if card = find_card_for_user(user, required_argument(arguments, "card_id"), raise_on_missing: false)
              yield account, user, card
            end
          end

          return result if result
        end

        raise Error.new("Card not found", code: -32004)
      end
    end

    def find_card_for_user(user, identifier, raise_on_missing: true)
      relation = user.accessible_cards.published.preloaded
      card = relation.find_by(id: identifier) || relation.find_by(number: identifier)
      raise Error.new("Card not found", code: -32004) if raise_on_missing && card.blank?
      card
    end

    def with_account(identifier)
      account = find_account(identifier)
      user = @identity.users.active.find_by(account: account)

      if account && user
        with_current(account, user) { yield account, user }
      else
        raise Error.new("Account not found", code: -32004)
      end
    end

    def with_current(account, user, &)
      Current.with(account: account, identity: @identity, user: user, &)
    end

    def find_account(identifier)
      raw_identifier = identifier.to_s.delete_prefix("/")
      @identity.accounts.active.find_by(id: raw_identifier) ||
        @identity.accounts.active.find_by(external_account_id: raw_identifier)
    end

    def each_account
      @identity.users_with_active_accounts.active.includes(:account).map { |user| [ user.account, user ] }
    end

    def required_account_identifier(arguments)
      account_identifier(arguments).presence || raise(Error.new("account_id is required", code: -32602))
    end

    def account_identifier(arguments)
      arguments["account_id"] || arguments["account_slug"]
    end

    def required_argument(arguments, key)
      arguments[key].presence || raise(Error.new("#{key} is required", code: -32602))
    end

    def limit_for(arguments, default: 25, maximum: 50)
      (arguments["limit"].presence || default).to_i.clamp(1, maximum)
    end

    def search_result_hash(account, card)
      {
        id: card.id,
        title: card.title,
        url: card_url(account, card),
        metadata: card_metadata(account, card)
      }
    end

    def account_hash(account, user)
      {
        id: account.id,
        external_account_id: account.external_account_id.to_s,
        name: account.name,
        slug: account.slug,
        user: {
          id: user.id,
          name: user.name,
          role: user.role
        }
      }
    end

    def board_hash(board)
      {
        id: board.id,
        name: board.name,
        all_access: board.all_access?,
        created_at: board.created_at.utc.iso8601,
        auto_postpone_period_in_days: board.auto_postpone_period_in_days
      }
    end

    def column_hash(column)
      {
        id: column.id,
        name: column.name,
        color: column.color,
        created_at: column.created_at.utc.iso8601
      }
    end

    def card_hash(account, card)
      {
        id: card.id,
        number: card.number,
        title: card.title,
        status: card.status,
        description: card.description.to_plain_text,
        url: card_url(account, card),
        board: board_hash(card.board),
        column: card.column && column_hash(card.column),
        created_at: card.created_at.utc.iso8601,
        last_active_at: card.last_active_at.utc.iso8601
      }
    end

    def card_metadata(account, card)
      {
        account_id: account.id,
        external_account_id: account.external_account_id.to_s,
        account_name: account.name,
        board_id: card.board_id,
        board_name: card.board.name,
        card_number: card.number,
        status: card.status
      }
    end

    def comment_hash(account, comment)
      {
        id: comment.id,
        body: comment.body.to_plain_text,
        creator: {
          id: comment.creator.id,
          name: comment.creator.name
        },
        card_id: comment.card_id,
        url: @url_context.card_comment_url(comment.card, comment, script_name: account.slug),
        created_at: comment.created_at.utc.iso8601,
        updated_at: comment.updated_at.utc.iso8601
      }
    end

    def card_url(account, card)
      @url_context.card_url(card, script_name: account.slug)
    end
end
