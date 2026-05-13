class Identity::AccessToken < ApplicationRecord
  belongs_to :identity
  belongs_to :oauth_client, class_name: "Oauth::Client", optional: true

  has_secure_token
  enum :permission, %w[ read write ].index_by(&:itself), default: :read

  scope :personal, -> { where(oauth_client_id: nil) }
  scope :oauth, -> { where.not(oauth_client_id: nil) }

  def allows?(method)
    method.in?(%w[ GET HEAD ]) || write?
  end
end
