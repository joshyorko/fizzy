class Ai::ListCommentsTool::Filter < Ai::Tool::Filter
   register_filters(
    query: :apply_search,
    ids: :apply_ids_filter,
    card_ids: :apply_card_ids_filter,
    created_before: :apply_created_before_filter,
    created_after: :apply_created_after_filter,
    type: :apply_type_filter
  )

  private
    def apply_search(scope)
      scope.search(filters[:query])
    end

    def apply_ids_filter(scope)
      scope.where(id: filters[:ids].split(",").map(&:strip))
    end

    def apply_card_ids_filter(scope)
      scope.where(card_id: filters[:card_ids].split(",").map(&:strip))
    end

    def apply_created_before_filter(scope)
      scope.where(created_at: ...filters[:created_before].to_datetime)
    end

    def apply_created_after_filter(scope)
      scope.where(created_at: filters[:created_after].to_datetime...)
    end

    def apply_type_filter(scope)
      if filters[:type].casecmp?("system")
        scope.where(creator: { role: "system" })
      else
      scope.where.not(creator: { role: "system" })
      end
    end
end
