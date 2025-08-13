class Ai::ListCommentsTool < Ai::Tool
  description <<-MD
    Lists all comments accessible by the current user.
    The response is paginated so you may need to iterate through multiple pages to get the full list.
    URLs are valid if they are just a path - don't change them!
    Each comment object has the following fields:
    - id [Integer, not null]
    - card_id [Integer, not null]
    - body [String, not null]
    - created_at [String, not null] ISO8601 formatted timestamp
    - creator [Object, not null] the User that created the comment
    - system [Boolean, not null] indicates if the comment was created by the system
    - reactions [Array]
      - content [String, not null]
      - reacter [Object] represents a User
        - id [Integer, not null]
        - name [String, not null]
  MD

  param :page,
    type: :string,
    desc: "Which page to return. Leave blank to get the first page",
    required: false
  param :query,
    type: :string,
    desc: "If provided, will perform a semantic search by embeddings and return only matching comments",
    required: false
  param :ordered_by,
    type: :string,
    desc: "Can be either id, created_at followed by ASC or DESC - e.g. `created_at DESC`",
    required: false
  param :ids,
    type: :string,
    desc: "If provided, will return only comments with the given IDs (comma-separated)",
    required: false
  param :card_ids,
    type: :string,
    desc: "If provided, will return only comments for the specified cards",
    required: false
  param :type,
    type: :string,
    desc: "If provided, returns either 'user' or 'system' comments, if ommitted it returns both",
    required: false
  param :created_after,
    type: :string,
    desc: "If provided, will return only comments created on or after the given ISO timestamp",
    required: false
  param :created_before,
    type: :string,
    desc: "If provided, will return only comments created on or before the given ISO timestamp",
    required: false

  attr_reader :user

  def initialize(user:)
    @user = user
  end

  def execute(**params)
    cards = Card.where(collection: user.collections)
    comments = Comment.where(card: cards).with_rich_text_body.includes(:card, :creator, reactions: [ :reacter ])
    comments = Filter.new(scope: comments, filters: params).filter

    ordered_by = OrderClause.parse(
      params[:ordered_by],
      defaults: { created_at: :desc, id: :desc },
      permitted: %w[id created_at]
    )

    # TODO: The serialization here is temporary until we add an API,
    # then we can re-use the jbuilder views and caching from that
    paginated_response(comments, page: params[:page], ordered_by: ordered_by.to_h) do |comment|
      comment_attributes(comment)
    end
  end

  private
    def comment_attributes(comment)
      {
        id: comment.id,
        card_id: comment.card_id,
        body: comment.body.to_plain_text,
        created_at: comment.created_at.iso8601,
        creator: comment.creator.as_json(only: [ :id, :name ]),
        system: comment.creator.system?,
        reactions: comment.reactions.map do |reaction|
          {
            content: reaction.content,
            reacter: reaction.reacter.as_json(only: [ :id, :name ])
          }
        end,
        url: collection_card_url(comment.card.collection_id, comment.card, anchor: "comment_#{comment.id}")
      }
    end
end
