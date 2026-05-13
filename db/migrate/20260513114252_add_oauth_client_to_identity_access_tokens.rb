class AddOauthClientToIdentityAccessTokens < ActiveRecord::Migration[8.2]
  def change
    add_reference :identity_access_tokens, :oauth_client, type: :uuid, foreign_key: { to_table: :oauth_clients }, index: true
  end
end
