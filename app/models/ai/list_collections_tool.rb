class Ai::ListCollectionsTool < Ai::Tool
  description <<-MD
    Lists all collections accessible by the current user.
    The response is paginated so you may need to iterate through multiple pages to get the full list.
    URLs are valid if they are just a path - don't change them!
    Each collection object has the following fields:
    - id [Integer, not null]
    - name [String, not null]
    - url [String, not null]
  MD

  param :page,
    type: :string,
    desc: "Which page to return. Leave blank to get the first page",
    required: false

  attr_reader :user

  def initialize(user:)
    @user = user
  end

  def execute(**params)
    collections = user.collections

    # TODO: The serialization here is temporary until we add an API,
    # then we can re-use the jbuilder views and caching from that
    paginated_response(collections, page: params[:page], ordered_by: { name: :asc, id: :desc }) do |collection|
      collection_attributes(collection)
    end
  end

  private
    def collection_attributes(collection)
      {
        id: collection.id,
        name: collection.name,
        url: collection_url(collection)
      }
    end
end
