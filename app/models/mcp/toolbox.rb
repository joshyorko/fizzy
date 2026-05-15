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

  WRITE_TOOLS = %w[ board_create column_update card_create card_update move_card comment_create ].freeze
  COLUMN_COLOR_OPTIONS = Color::COLORS.map { |color| "#{color.name} (#{color.value})" }.join(", ")

  class << self
    def tool_definitions
      [
        read_tool("search", "Search cards", "Use this when the user wants to find Fizzy cards by text.", {
          query: string_schema("Search terms")
        }, required: [ "query" ]),
        read_tool("fetch", "Fetch card", "Use this when the user wants the full details for one Fizzy card found by search.", {
          id: string_schema("Card id returned by search")
        }, required: [ "id" ]),
        read_tool("identity_show", "Show identity", "Use this when the user asks which Fizzy identity is connected.", {}),
        read_tool("account_list", "List accounts", "Use this when the user needs to choose or confirm a Fizzy account.", {}),
        read_tool("board_list", "List boards", "Use this when the user wants to see accessible Fizzy boards in an account.", {
          account_id: string_schema("Account id or account slug"),
          limit: integer_schema("Maximum results")
        }, required: [ "account_id" ]),
        read_tool("board_show", "Show board", "Use this when the user wants details and active workflow columns for one Fizzy board.", {
          account_id: string_schema("Account id or account slug"),
          board_id: string_schema("Board id")
        }, required: [ "account_id", "board_id" ]),
        read_tool("column_list", "List columns", "Use this when the user wants the active workflow columns on a Fizzy board. System columns such as Maybe?, Not Now, and Done are not user-created workflow columns.", {
          account_id: string_schema("Account id or account slug"),
          board_id: string_schema("Board id")
        }, required: [ "account_id", "board_id" ]),
        write_tool("column_update", "Update column", "Use this when the user wants to rename an active Fizzy workflow column or change its color. Use column_list first if you know the column name but not the id. System columns such as Maybe?, Not Now, and Done do not have editable colors.", {
          account_id: string_schema("Account id or account slug"),
          board_id: string_schema("Board id"),
          column_id: string_schema("Column id"),
          name: string_schema("Column name"),
          color: column_color_schema
        }, required: [ "account_id", "board_id", "column_id" ]),
        write_tool("board_create", "Create board", "Use this when the user wants a new account-wide Fizzy board. Create only active workflow columns; Fizzy automatically includes Maybe?, Not Now, and Done as system columns.", {
          account_id: string_schema("Account id or account slug"),
          name: string_schema("Board name"),
          title: string_schema("Alias for name, accepted for compatibility"),
          description: rich_text_schema("Board public description"),
          columns: column_definitions_schema("Initial active workflow columns to create. Send an array of plain column name strings like [\"To Do\", \"In Progress\", \"Review\"] or objects with name/color. Do not include Maybe?, Not Now, or Done; Fizzy automatically includes those system columns."),
          initial_columns: column_definitions_schema("Alias for columns, accepted for compatibility. Send plain column name strings or objects with name/color. Do not include Maybe?, Not Now, or Done.")
        }, required: [ "account_id", "name" ]),
        read_tool("card_list", "List cards", "Use this when the user wants accessible cards in an account, board, or active workflow column.", {
          account_id: string_schema("Account id or account slug"),
          board_id: string_schema("Board id"),
          column_id: string_schema("Column id"),
          limit: integer_schema("Maximum results")
        }, required: [ "account_id" ]),
        read_tool("card_show", "Show card", "Use this when the user wants details for one Fizzy card.", {
          account_id: string_schema("Account id or account slug"),
          card_id: string_schema("Card id or card number")
        }, required: [ "card_id" ]),
        write_tool("card_create", "Create card", "Use this when the user wants a new published card on a Fizzy board.", {
          account_id: string_schema("Account id or account slug"),
          board_id: string_schema("Board id"),
          column_id: string_schema("Column id"),
          title: string_schema("Card title"),
          description: rich_text_schema("Card description"),
          tag_titles: array_schema("Tag titles to apply, with or without leading #. Use #agent-instructions, #move-to-done, #close-on-complete, or #move-to-<column> for agent workflow cards."),
          steps: array_schema("Checklist step contents to create on the card. Existing matching steps are not duplicated."),
          golden: boolean_schema("Whether to mark the card with Fizzy's native golden marker.")
        }, required: [ "account_id", "board_id", "title" ]),
        write_tool("card_update", "Update card", "Use this when the user wants to edit a Fizzy card's title, description, active workflow column, tags, checklist steps, or golden marker.", {
          account_id: string_schema("Account id or account slug"),
          card_id: string_schema("Card id or card number"),
          title: string_schema("Card title"),
          description: rich_text_schema("Card description"),
          column_id: string_schema("Column id"),
          tag_titles: array_schema("Tag titles to apply, with or without leading #. Use #agent-instructions, #move-to-done, #close-on-complete, or #move-to-<column> for agent workflow cards."),
          steps: array_schema("Checklist step contents to create on the card. Existing matching steps are not duplicated."),
          golden: boolean_schema("Whether to mark the card with Fizzy's native golden marker.")
        }, required: [ "card_id" ], destructive: true),
        write_tool("move_card", "Move card", "Use this when the user wants to move a Fizzy card. Use target \"done\", \"not_now\", or \"maybe\" for Fizzy system columns; use column_id or an active workflow column name for ordinary board columns.", {
          account_id: string_schema("Account id or account slug"),
          card_id: string_schema("Card id or card number"),
          target: string_schema("Move target: done, not_now, maybe, backlog, next, or exact active workflow column name"),
          destination: string_schema("Alias for target, accepted for compatibility"),
          column_id: string_schema("Column id. When present, this takes precedence over target.")
        }, required: [ "card_id" ]),
        read_tool("comment_list", "List comments", "Use this when the user wants comments on a Fizzy card.", {
          account_id: string_schema("Account id or account slug"),
          card_id: string_schema("Card id or card number"),
          limit: integer_schema("Maximum results")
        }, required: [ "card_id" ]),
        write_tool("comment_create", "Create comment", "Use this when the user wants to add a comment to a Fizzy card.", {
          account_id: string_schema("Account id or account slug"),
          card_id: string_schema("Card id or card number"),
          body: rich_text_schema("Comment body")
        }, required: [ "card_id", "body" ])
      ]
    end

    private
      def read_tool(name, title, description, properties, required: [])
        tool(name, title, description, properties, required: required, scopes: [ "read" ], read_only: true)
      end

      def write_tool(name, title, description, properties, required: [], destructive: false)
        tool(name, title, description, properties, required: required, scopes: [ "read", "write" ], read_only: false, destructive: destructive)
      end

      def tool(name, title, description, properties, required:, scopes:, read_only:, destructive: false)
        security_schemes = [ { type: "oauth2", scopes: scopes } ]
        input_schema = {
          type: "object",
          properties: properties,
          required: required
        }

        {
          name: name,
          title: title,
          description: description,
          inputSchema: input_schema,
          outputSchema: output_schema_for(name),
          annotations: { readOnlyHint: read_only, destructiveHint: destructive, openWorldHint: false },
          securitySchemes: security_schemes,
          _meta: { securitySchemes: security_schemes }
        }
      end

      def string_schema(description)
        { type: "string", description: description }
      end

      def rich_text_schema(description)
        string_schema("#{description} as sanitized Action Text HTML. Plain text is accepted, but send HTML for lists, links, bold, italics, or paragraphs.")
      end

      def array_schema(description)
        { type: "array", description: description, items: { type: "string" } }
      end

      def column_definitions_schema(description)
        {
          type: "array",
          description: description,
          items: { type: "string", description: "Active workflow column name" }
        }
      end

      def column_color_schema
        {
          type: "string",
          description: "Column color. Send one of these color names or CSS values: #{COLUMN_COLOR_OPTIONS}."
        }
      end

      def boolean_schema(description)
        { type: "boolean", description: description }
      end

      def integer_schema(description)
        { type: "integer", description: description, minimum: 1, maximum: 50 }
      end

      def output_schema_for(name)
        case name
        when "search"
          object_schema(results: array_of_schema(search_result_schema))
        when "fetch"
          object_schema({
            id: string_schema("Card id"),
            title: string_schema("Card title"),
            text: string_schema("Plain-text card description"),
            html: string_schema("HTML card description"),
            url: string_schema("Canonical card URL"),
            metadata: card_metadata_schema
          })
        when "identity_show"
          object_schema({
            id: string_schema("Identity id"),
            email_address: string_schema("Identity email address")
          })
        when "account_list"
          object_schema(accounts: array_of_schema(account_schema))
        when "board_list"
          object_schema(boards: array_of_schema(board_schema))
        when "board_show"
          object_schema({
            board: board_schema,
            columns: array_of_schema(column_schema),
            system_columns: system_columns_schema
          })
        when "column_list"
          object_schema({
            columns: array_of_schema(column_schema),
            system_columns: system_columns_schema
          })
        when "board_create"
          object_schema({
            board: board_schema.merge(properties: board_schema[:properties].merge(board_description_schema[:properties])),
            columns: array_of_schema(column_schema),
            system_columns: system_columns_schema
          })
        when "column_update"
          object_schema(column: column_schema)
        when "card_list"
          object_schema(cards: array_of_schema(card_schema))
        when "card_show"
          object_schema({
            card: card_schema,
            text: string_schema("Plain-text card description"),
            metadata: card_metadata_schema
          })
        when "card_create", "card_update", "move_card"
          object_schema({
            card: card_schema,
            metadata: card_metadata_schema
          })
        when "comment_list"
          object_schema(comments: array_of_schema(comment_schema))
        when "comment_create"
          object_schema(comment: comment_schema)
        else
          raise ArgumentError, "Missing output schema for #{name}"
        end
      end

      def object_schema(properties = nil, required: nil, **keyword_properties)
        properties ||= keyword_properties

        {
          type: "object",
          properties: properties,
          required: required || properties.keys.map(&:to_s)
        }
      end

      def array_of_schema(item_schema)
        { type: "array", items: item_schema }
      end

      def nullable_schema(schema)
        schema
      end

      def system_columns_schema
        array_of_schema(string_schema("Fizzy system column name shown automatically by the board UI"))
      end

      def account_schema
        object_schema({
          id: string_schema("Account id"),
          external_account_id: string_schema("External account id"),
          name: string_schema("Account name"),
          slug: string_schema("Account URL slug"),
          user: object_schema({
            id: string_schema("User id"),
            name: string_schema("User name"),
            role: string_schema("User role")
          })
        })
      end

      def board_schema
        object_schema({
          id: string_schema("Board id"),
          name: string_schema("Board name"),
          all_access: boolean_schema("Whether all account users can access the board"),
          url: string_schema("Board URL"),
          created_at: timestamp_schema("Board creation timestamp"),
          auto_postpone_period_in_days: { type: "integer", description: "Auto-postpone period in days" }
        })
      end

      def board_description_schema
        object_schema({
          public_description: string_schema("Plain-text public board description"),
          public_description_html: string_schema("HTML public board description")
        })
      end

      def column_schema
        object_schema({
          id: string_schema("Column id"),
          name: string_schema("Column name"),
          color: string_schema("Column color"),
          created_at: timestamp_schema("Column creation timestamp")
        })
      end

      def card_schema
        object_schema({
          id: string_schema("Card id"),
          number: { type: "integer", description: "Card number" },
          title: string_schema("Card title"),
          status: string_schema("User-visible card column or status"),
          description: string_schema("Plain-text card description"),
          description_html: string_schema("HTML card description"),
          url: string_schema("Card URL"),
          board: board_schema,
          column: nullable_schema(column_schema),
          tags: array_of_schema(string_schema("Tag title with leading #")),
          golden: boolean_schema("Whether the card is marked golden"),
          steps: array_of_schema(step_schema),
          created_at: timestamp_schema("Card creation timestamp"),
          last_active_at: timestamp_schema("Card last activity timestamp")
        })
      end

      def step_schema
        object_schema({
          id: string_schema("Step id"),
          content: string_schema("Step content"),
          completed: boolean_schema("Whether the step is completed")
        })
      end

      def card_metadata_schema
        object_schema({
          account_id: string_schema("Account id"),
          external_account_id: string_schema("External account id"),
          account_name: string_schema("Account name"),
          board_id: string_schema("Board id"),
          board_name: string_schema("Board name"),
          card_number: { type: "integer", description: "Card number" },
          status: string_schema("User-visible card column or status"),
          tags: array_of_schema(string_schema("Tag title with leading #")),
          golden: boolean_schema("Whether the card is marked golden")
        })
      end

      def search_result_schema
        object_schema({
          id: string_schema("Card id"),
          title: string_schema("Card title"),
          url: string_schema("Card URL"),
          metadata: card_metadata_schema
        })
      end

      def comment_schema
        object_schema({
          id: string_schema("Comment id"),
          body: string_schema("Plain-text comment body"),
          body_html: string_schema("HTML comment body"),
          creator: object_schema({
            id: string_schema("Comment creator id"),
            name: string_schema("Comment creator name")
          }),
          card_id: string_schema("Card id"),
          url: string_schema("Comment URL"),
          created_at: timestamp_schema("Comment creation timestamp"),
          updated_at: timestamp_schema("Comment update timestamp")
        })
      end

      def timestamp_schema(description)
        { type: "string", description: description, format: "date-time" }
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
    raise Error.new("Invalid arguments", code: -32602) unless arguments.is_a?(Hash)

    result public_send(name, arguments)
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
      html: card.description.to_s,
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
        columns: board.columns.sorted.map { |column| column_hash(column) },
        system_columns: Board.system_column_names
      }
    end
  end

  def column_list(arguments)
    with_account(required_account_identifier(arguments)) do |_account, user|
      board = user.boards.find(required_argument(arguments, "board_id"))

      {
        columns: board.columns.sorted.map { |column| column_hash(column) },
        system_columns: Board.system_column_names
      }
    end
  end

  def column_update(arguments)
    with_account(required_account_identifier(arguments)) do |_account, user|
      board = user.boards.find(required_argument(arguments, "board_id"))
      column = board.columns.find(required_argument(arguments, "column_id"))
      attributes = column_update_attributes(arguments)

      column.update!(attributes)

      {
        column: column_hash(column.reload)
      }
    end
  end

  def board_create(arguments)
    with_account(required_account_identifier(arguments)) do |_account, user|
      board = nil

      Board.transaction do
        board = Board.create!(
          name: board_name(arguments),
          public_description: arguments["description"],
          creator: user,
          all_access: true
        )

        initial_column_attributes(arguments).each do |attributes|
          board.columns.create!(attributes)
        end
      end

      {
        board: board_hash(board.reload).merge(board_description_hash(board)),
        columns: board.columns.sorted.map { |column| column_hash(column) },
        system_columns: Board.system_column_names
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
      card = nil

      Card.transaction do
        card = board.cards.create!(attributes)
        apply_card_workflow(card, arguments)
      end

      {
        card: card_hash(account, card.reload),
        metadata: card_metadata(account, card)
      }
    end
  end

  def card_update(arguments)
    with_found_card(arguments) do |account, _user, card|
      attributes = arguments.slice("title", "description")

      Card.transaction do
        card.update!(attributes) if attributes.present?
        move_card_to_column_argument(card, arguments["column_id"]) if arguments.key?("column_id")
        apply_card_workflow(card, arguments)
      end

      {
        card: card_hash(account, card.reload),
        metadata: card_metadata(account, card)
      }
    end
  end

  def move_card(arguments)
    with_found_card(arguments) do |account, user, card|
      target = move_target(arguments)

      if arguments["column_id"].blank? && (system_column_name = Board.system_column_name_for(target))
        move_card_to_system_column(card, system_column_name, user)
      else
        column = move_target_column(card, arguments)
        card.triage_into(column)
      end

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
      identifier = required_argument(arguments, "card_id")

      if account_identifier(arguments).present?
        with_account(account_identifier(arguments)) do |account, user|
          yield account, user, find_card_for_user(user, identifier)
        end
      else
        raise Error.new("account_id is required when card_id is a card number", code: -32602) if card_number_identifier?(identifier)

        each_account.each do |account, user|
          result = with_current(account, user) do
            if card = find_card_for_user(user, identifier, raise_on_missing: false)
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

    def card_number_identifier?(identifier)
      identifier.to_s.match?(/\A\d+\z/)
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

    def apply_card_workflow(card, arguments)
      apply_golden(card, arguments["golden"]) if arguments.key?("golden")
      apply_tags(card, arguments["tag_titles"]) if arguments.key?("tag_titles")
      apply_steps(card, arguments["steps"]) if arguments.key?("steps")
    end

    def board_name(arguments)
      arguments["name"].presence || arguments["title"].presence || raise(Error.new("name is required", code: -32602))
    end

    def initial_column_attributes(arguments)
      array_argument(arguments["columns"].presence || arguments["initial_columns"]).filter_map do |value|
        column_attributes_argument(value)
      end.reject { |attributes| Board.system_column_name?(attributes[:name]) }
    end

    def column_attributes_argument(value)
      name, color = case value
      when Hash
        [ value["name"].presence || value["title"].presence, value["color"].presence ]
      else
        [ value, nil ]
      end

      if name.to_s.strip.present?
        { name: name.to_s.strip }.tap do |attributes|
          attributes[:color] = column_color_value(color) if color.present?
        end
      end
    end

    def column_update_attributes(arguments)
      arguments.slice("name", "color").tap do |attributes|
        raise Error.new("name or color is required", code: -32602) if attributes.empty?

        attributes["color"] = column_color_value(attributes["color"]) if attributes.key?("color")
      end
    end

    def column_color_value(value)
      color = Color::COLORS.find do |candidate|
        candidate.value == value.to_s.strip || candidate.name.casecmp?(value.to_s.strip)
      end

      color&.value || raise(Error.new("color must be one of: #{COLUMN_COLOR_OPTIONS}", code: -32602))
    end

    def move_card_to_column_argument(card, column_id)
      if column_id.present?
        card.triage_into(card.board.columns.find(column_id))
      else
        card.send_back_to_triage
      end
    end

    def move_card_to_system_column(card, system_column_name, user)
      case system_column_name
      when "Done"
        card.close(user: user)
      when "Not Now"
        card.postpone(user: user)
      when "Maybe?"
        card.send_back_to_triage
      end
    end

    def move_target_column(card, arguments)
      return card.board.columns.find(arguments["column_id"]) if arguments["column_id"].present?

      case normalized_move_target(move_target(arguments))
      when "backlog"
        card.board.columns.sorted.first || raise(Error.new("Column not found", code: -32004))
      when "next"
        card.column&.right_column || raise(Error.new("Next column not found", code: -32004))
      when ""
        raise Error.new("target or column_id is required", code: -32602)
      else
        card.board.columns.detect { |column| normalized_move_target(column.name) == normalized_move_target(move_target(arguments)) } ||
          raise(Error.new("Column not found", code: -32004))
      end
    end

    def move_target(arguments)
      (arguments["target"].presence || arguments["destination"]).to_s.strip
    end

    def normalized_move_target(target)
      target.to_s.strip.downcase
    end

    def apply_golden(card, value)
      ActiveModel::Type::Boolean.new.cast(value) ? card.gild : card.ungild
    end

    def apply_tags(card, titles)
      array_argument(titles).filter_map { |title| normalized_tag_title(title) }.each do |title|
        tag = card.account.tags.find_or_create_by!(title: title)
        card.taggings.find_or_create_by!(tag: tag)
      end
    end

    def apply_steps(card, contents)
      existing_contents = card.steps.pluck(:content)

      array_argument(contents).map { |content| content.to_s.strip }.reject(&:blank?).each do |content|
        next if existing_contents.include?(content)

        card.steps.create!(content: content)
        existing_contents << content
      end
    end

    def array_argument(value)
      value.is_a?(Array) ? value : Array(value)
    end

    def normalized_tag_title(title)
      title.to_s.strip.gsub(/\A#+/, "").presence
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
        url: @url_context.board_url(board, script_name: board.account.slug),
        created_at: board.created_at.utc.iso8601,
        auto_postpone_period_in_days: board.auto_postpone_period_in_days
      }
    end

    def board_description_hash(board)
      {
        public_description: board.public_description.to_plain_text,
        public_description_html: board.public_description.to_s
      }
    end

    def column_hash(column)
      {
        id: column.id,
        name: column.name,
        color: column.color.to_s,
        created_at: column.created_at.utc.iso8601
      }
    end

    def card_hash(account, card)
      {
        id: card.id,
        number: card.number,
        title: card.title,
        status: card_status(card),
        description: card.description.to_plain_text,
        description_html: card.description.to_s,
        url: card_url(account, card),
        board: board_hash(card.board),
        column: card.active_workflow_column && column_hash(card.active_workflow_column),
        tags: card.tags.alphabetically.map(&:hashtag),
        golden: card.golden?,
        steps: step_hashes(card),
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
        status: card_status(card),
        tags: card.tags.alphabetically.map(&:hashtag),
        golden: card.golden?
      }
    end

    def card_status(card)
      card.board_column_name
    end

    def comment_hash(account, comment)
      {
        id: comment.id,
        body: comment.body.to_plain_text,
        body_html: comment.body.to_s,
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

    def step_hashes(card)
      card.steps.order(:created_at, :id).map do |step|
        {
          id: step.id,
          content: step.content,
          completed: step.completed?
        }
      end
    end
end
