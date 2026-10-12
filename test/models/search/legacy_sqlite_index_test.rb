require "test_helper"

class Search::LegacySqliteIndexTest < ActiveSupport::TestCase
  test "pre-upgrade SQLite index rows remain searchable without a rebuild" do
    skip "SQLite storage format" unless ActiveRecord::Base.connection.adapter_name == "SQLite"

    card = cards(:logo)
    record = Search::Record.create!(account_id: card.account_id, board_id: card.board_id,
      card_id: card.id, searchable_type: "Card", searchable_id: card.id,
      title: card.title, content: "legacyquartzfalcon", created_at: card.created_at)
    Search::Record.connection.exec_query(
      "INSERT OR REPLACE INTO search_records_fts(rowid, title, content) VALUES (?, ?, ?)",
      "Legacy search index", [ record.id, card.title, "legacyquartzfalcon" ]
    )

    assert_equal [ card.id ], users(:david).search("legacyquartzfalcon").results.map(&:id)
  end
end
