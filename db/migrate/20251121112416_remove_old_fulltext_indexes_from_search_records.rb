class RemoveOldFulltextIndexesFromSearchRecords < ActiveRecord::Migration[8.2]
  def up
    # Remove the old fulltext indexes (content, title) from all 16 search_records shards
    # We're keeping the new indexes (account_key, content, title) for tenant-aware searching
    (0..15).each do |shard|
      remove_index "search_records_#{shard}", name: "index_search_records_#{shard}_on_content_and_title"
    end
  end

  def down
    # Re-create the old fulltext indexes in case we need to rollback
    (0..15).each do |shard|
      add_index "search_records_#{shard}", [ :content, :title ], type: :fulltext, name: "index_search_records_#{shard}_on_content_and_title"
    end
  end
end
