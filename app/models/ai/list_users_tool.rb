class Ai::ListUsersTool < Ai::Tool
  description <<-MD
    Lists all users accessible by the current user.
    The response is paginated so you may need to iterate through multiple pages to get the full list.
    URLs are valid if they are just a path - don't change them!
    Each user object has the following fields:
    - id [Integer, not null]
    - name [String, not null]
    - role [String, not null]
    - url [String, not null]
  MD

  param :page,
    type: :string,
    desc: "Which page to return. Leave blank to get the first page",
    required: false
  param :collection_id,
    type: :integer,
    desc: "For which collection to list users",
    required: true
  param :ids,
    type: :string,
    desc: "If provided, will return only the users with the given IDs (comma-separated)",
    required: false

  attr_reader :user

  def initialize(user:)
    @user = user
  end

  def execute(**params)
    collection = user.collections.find(params[:collection_id])
    users = Filter.new(scope: collection.users.active, filters: params).filter

    # TODO: The serialization here is temporary until we add an API,
    # then we can re-use the jbuilder views and caching from that
    paginated_response(users, page: params[:page], ordered_by: { name: :asc, id: :desc }) do |user|
      user_attributes(user)
    end
  end

  private
    def user_attributes(user)
      {
        id: user.id,
        name: user.name,
        role: user.role,
        url: user_url(user)
      }
    end
end
