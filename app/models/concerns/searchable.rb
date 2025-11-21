module Searchable
  extend ActiveSupport::Concern

  included do
    after_create_commit :create_in_search_index
    after_update_commit :update_in_search_index
    after_destroy_commit :remove_from_search_index
  end

  def reindex
    update_in_search_index
  end

  private
    def create_in_search_index
      search_record_class.create!(search_record_attributes)
    end

    def update_in_search_index
      search_record_class.find_or_initialize_by(searchable_type: self.class.name, searchable_id: id).tap do |record|
        record.update!(search_record_attributes)
      end
    end

    def remove_from_search_index
      search_record_class.find_by(searchable_type: self.class.name, searchable_id: id)&.destroy
    end

    def search_record_class
      Search::Record.for_account(account_id)
    end

    def search_record_attributes
      {
        account_id: account_id,
        searchable_type: self.class.name,
        searchable_id: id,
        card_id: search_card_id,
        board_id: search_board_id,
        title: search_title,
        content: search_content,
        created_at: created_at
      }
    end

  # Models must implement these methods:
  # - account_id: returns the account id
  # - search_title: returns title string or nil
  # - search_content: returns content string
  # - search_card_id: returns the card id (self.id for cards, card_id for comments)
  # - search_board_id: returns the board id
end
