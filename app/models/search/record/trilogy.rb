module Search::Record::Trilogy
  extend ActiveSupport::Concern

  SHARD_COUNT = 16

  included do
    self.abstract_class = true

    before_save :set_account_key, :stem_content
  end

  class_methods do
    def shard_classes
      @shard_classes ||= SHARD_COUNT.times.map do |shard_id|
        Class.new(Search::Record) do
          self.table_name = "search_records_#{shard_id}"

          def self.name
            "Search::Record"
          end
        end
      end.freeze
    end

    def for_account(account_id)
      shard_classes[shard_id_for_account(account_id)]
    end

    def shard_id_for_account(account_id)
      Zlib.crc32(account_id.to_s) % SHARD_COUNT
    end

    def matching_scope(query, account_id)
      stemmed_query = Search::Stemmer.stem(query)
      account_key = "account#{account_id}"
      full_query = "+#{account_key} +(#{stemmed_query})"
      where("MATCH(#{table_name}.account_key, #{table_name}.content, #{table_name}.title) AGAINST(? IN BOOLEAN MODE)", full_query)
    end

    def search_scope(relation, query)
      relation.select(:id, :searchable_type, :searchable_id, :card_id, :board_id, :account_id, :created_at, "#{connection.quote(query.terms)} AS query")
    end
  end

  def card_title
    highlight(card.title, show: :full) if card_id
  end

  def card_description
    highlight(card.description.to_plain_text, show: :snippet) if card_id
  end

  def comment_body
    highlight(comment.body.to_plain_text, show: :snippet) if comment
  end

  private
    def stem_content
      self.title = Search::Stemmer.stem(title) if title_changed?
      self.content = Search::Stemmer.stem(content) if content_changed?
    end

    def set_account_key
      self.account_key = "account#{account_id}"
    end

    def highlight(text, show:)
      if text.present? && attribute?(:query)
        highlighter = Search::Highlighter.new(query)
        show == :snippet ? highlighter.snippet(text) : highlighter.highlight(text)
      else
        text
      end
    end
end
