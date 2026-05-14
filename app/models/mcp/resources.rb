class Mcp::Resources
  class Error < Mcp::Toolbox::Error
  end

  def initialize(access_token:, url_context:)
    @identity = access_token.identity
    @url_context = url_context
  end

  def list
    [
      resource("fizzy://accounts", "Accounts", "Accessible Fizzy accounts")
    ] + each_account.flat_map { |account, user| account_resources(account, user) }
  end

  def read(uri)
    payload = payload_for(uri)

    {
      contents: [
        {
          uri: uri,
          mimeType: "application/json",
          text: JSON.pretty_generate(payload)
        }
      ]
    }
  end

  private
    def account_resources(account, user)
      account_overview = [
        resource("fizzy://accounts/#{account.id}/overview", "#{account.name} overview", "Account boards and recent cards")
      ]
      board_resources = user.boards.ordered_by_recently_accessed.limit(25).map do |board|
        resource("fizzy://accounts/#{account.id}/boards/#{board.id}", board.name, "Board summary")
      end
      card_resources = user.accessible_cards.published.latest.limit(25).map do |card|
        resource("fizzy://accounts/#{account.id}/cards/#{card.id}", card.title, "Card summary")
      end

      account_overview + board_resources + card_resources
    end

    def resource(uri, name, description)
      {
        uri: uri,
        name: name,
        description: description,
        mimeType: "application/json"
      }
    end

    def payload_for(uri)
      segments = uri_segments(uri)

      case segments
      in [ "accounts" ]
        { accounts: each_account.map { |account, user| account_hash(account, user) } }
      in [ "accounts", account_id, "overview" ]
        with_account(account_id) { |account, user| overview_hash(account, user) }
      in [ "accounts", account_id, "boards", board_id ]
        with_account(account_id) { |_account, user| board_resource_hash(user.boards.find(board_id)) }
      in [ "accounts", account_id, "cards", card_id ]
        with_account(account_id) { |account, user| card_resource_hash(account, find_card_for_user(user, card_id)) }
      else
        raise Error.new("Resource not found", code: -32004)
      end
    end

    def uri_segments(uri)
      raw_uri = uri.to_s
      raise Error.new("Unsupported resource URI", code: -32602) unless raw_uri.start_with?("fizzy://")

      raw_uri.delete_prefix("fizzy://").split("/").reject(&:blank?)
    end

    def overview_hash(account, user)
      {
        account: account_hash(account, user),
        boards: user.boards.ordered_by_recently_accessed.limit(25).map { |board| board_hash(board) },
        recent_cards: user.accessible_cards.published.latest.limit(25).map { |card| card_summary_hash(account, card) }
      }
    end

    def board_resource_hash(board)
      {
        board: board_hash(board),
        columns: board.columns.sorted.map { |column| column_hash(column) },
        system_columns: Board.system_column_names,
        recent_cards: board.cards.published.latest.limit(25).map { |card| card_summary_hash(board.account, card) }
      }
    end

    def card_resource_hash(account, card)
      {
        card: card_summary_hash(account, card).merge(
          description: card.description.to_plain_text.truncate(1_000),
          tags: card.tags.alphabetically.map(&:hashtag),
          golden: card.golden?,
          steps: card.steps.order(:created_at, :id).map { |step| { id: step.id, content: step.content, completed: step.completed? } }
        )
      }
    end

    def account_hash(account, user)
      {
        id: account.id,
        external_account_id: account.external_account_id.to_s,
        name: account.name,
        slug: account.slug,
        role: user.role
      }
    end

    def board_hash(board)
      {
        id: board.id,
        name: board.name,
        uri: "fizzy://accounts/#{board.account_id}/boards/#{board.id}",
        columns_count: board.columns.size
      }
    end

    def column_hash(column)
      {
        id: column.id,
        name: column.name
      }
    end

    def card_summary_hash(account, card)
      {
        id: card.id,
        number: card.number,
        title: card.title,
        uri: "fizzy://accounts/#{account.id}/cards/#{card.id}",
        url: @url_context.card_url(card, script_name: account.slug),
        board_id: card.board_id,
        column_id: card.active_workflow_column&.id,
        status: card.board_column_name
      }
    end

    def find_card_for_user(user, identifier)
      user.accessible_cards.published.preloaded.find_by(id: identifier) ||
        user.accessible_cards.published.preloaded.find_by(number: identifier) ||
        raise(Error.new("Resource not found", code: -32004))
    end

    def with_account(identifier)
      account = @identity.accounts.active.find_by(id: identifier.to_s.delete_prefix("/")) ||
        @identity.accounts.active.find_by(external_account_id: identifier)
      user = @identity.users.active.find_by(account: account)

      if account && user
        Current.with(account: account, identity: @identity, user: user) { yield account, user }
      else
        raise Error.new("Resource not found", code: -32004)
      end
    end

    def each_account
      @identity.users_with_active_accounts.active.includes(:account).map { |user| [ user.account, user ] }
    end
end
