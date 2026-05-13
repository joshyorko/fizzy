class Mcp::Resources
  def initialize(access_token:, url_context:)
    @access_token = access_token
    @identity = access_token.identity
    @url_context = url_context
  end

  def list
    resources = [ { uri: "fizzy://accounts", name: "Accounts", description: "Accounts available to the identity" } ]

    each_account.each do |account, user|
      resources << { uri: overview_uri(account), name: "#{account.name} overview", description: "Account overview" }
      user.boards.limit(10).each do |board|
        resources << { uri: board_uri(account, board), name: board.name, description: "Board summary" }
      end
    end

    { resources: resources }
  end

  def read(uri)
    case uri
    when "fizzy://accounts"
      { contents: [ json_content(uri, { accounts: each_account.map { |account, user| account_hash(account, user) } }) ] }
    when %r{\Afizzy://accounts/([^/]+)/overview\z}
      with_account($1) do |account, user|
        data = { account: account_hash(account, user), boards_count: user.boards.count, cards_count: user.accessible_cards.published.count }
        { contents: [ json_content(uri, data) ] }
      end
    when %r{\Afizzy://accounts/([^/]+)/boards/([^/]+)\z}
      with_account($1) do |_account, user|
        board = user.boards.find($2)
        data = { board: { id: board.id, name: board.name }, columns: board.columns.sorted.pluck(:id, :name).map { |id, name| { id: id, name: name } } }
        { contents: [ json_content(uri, data) ] }
      end
    when %r{\Afizzy://accounts/([^/]+)/cards/([^/]+)\z}
      with_account($1) do |account, user|
        card = user.accessible_cards.find($2)
        data = { card: { id: card.id, number: card.number, title: card.title, board_id: card.board_id, column_id: card.column_id, url: @url_context.card_url(card, script_name: "/#{account.external_account_id}") } }
        { contents: [ json_content(uri, data) ] }
      end
    else
      raise Mcp::Toolbox::Error.new("Unknown resource", code: -32602)
    end
  end

  private
    def overview_uri(account) = "fizzy://accounts/#{account.external_account_id}/overview"
    def board_uri(account, board) = "fizzy://accounts/#{account.external_account_id}/boards/#{board.id}"

    def json_content(uri, data)
      { uri: uri, mimeType: "application/json", text: data.to_json }
    end

    def each_account
      @identity.users.includes(:account).map { |user| [ user.account, user ] }
    end

    def with_account(identifier)
      account, user = each_account.find { |a, _u| [ a.external_account_id.to_s, a.slug, a.id ].include?(identifier.to_s) }
      raise Mcp::Toolbox::Error.new("Account not found", code: -32602) unless account

      Current.set(account: account, user: user) { yield account, user }
    end

    def account_hash(account, user)
      { id: account.external_account_id.to_s, slug: account.slug, name: account.name, role: user.role }
    end
end
