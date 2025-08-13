class Ai::ListCardsTool::Filter < Ai::Tool::Filter
   register_filters(
    query: :apply_search,
    ids: :apply_ids_filter,
    collection_ids: :apply_collection_ids_filter,
    golden: :apply_golden_filter,
    created_before: :apply_created_before_filter,
    created_after: :apply_created_after_filter,
    last_active_before: :apply_last_active_before_filter,
    last_active_after: :apply_last_active_after_filter
  )

  private
    def apply_search(scope)
      scope.search(filters[:query])
    end

    def apply_ids_filter(scope)
      scope.where(id: filters[:ids].split(",").map(&:strip))
    end

    def apply_collection_ids_filter(scope)
      scope.where(collection_id: filters[:collection_ids].split(",").map(&:strip))
    end

    def apply_golden_filter(scope)
      scope.golden
    end

    def apply_created_before_filter(scope)
      scope.where(created_at: ...filters[:created_before].to_datetime)
    end

    def apply_created_after_filter(scope)
      scope.where(created_at: filters[:created_after].to_datetime...)
    end

    def apply_last_active_before_filter(scope)
      scope.where(last_active_at: ...filters[:last_active_before].to_datetime)
    end

    def apply_last_active_after_filter(scope)
      scope.where(last_active_at: filters[:last_active_after].to_datetime...)
    end
end
