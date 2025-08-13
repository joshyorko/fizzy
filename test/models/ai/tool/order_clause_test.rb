require "test_helper"

class Ai::Tool::OrderClauseTest < ActiveSupport::TestCase
  test "parsing" do
    order_clause = Ai::Tool::OrderClause.parse("created_at DESC")
    assert_equal({ created_at: :desc }, order_clause.order, "Parses a single column and direction")

    order_clause = Ai::Tool::OrderClause.parse("created_at DESC, id ASC")
    assert_equal({ created_at: :desc, id: :desc }, order_clause.order, "Parses a multiple column and direction")
    assert_equal(%w[created_at id], order_clause.order.keys, "Preserves the order of columns")

    order_clause = Ai::Tool::OrderClause.parse("id DESC, created_at ASC")
    assert_equal({ created_at: :desc, id: :desc }, order_clause.order, "Parses a multiple column and direction")
    assert_equal(%w[id created_at], order_clause.order.keys, "Preserves the order of columns")
  end
end
