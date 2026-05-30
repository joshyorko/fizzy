require "digest"

class HardenIdentityAccessTokens < ActiveRecord::Migration[8.2]
  class AccessToken < ActiveRecord::Base
    self.table_name = "identity_access_tokens"
  end

  def up
    change_column_default :oauth_clients, :scope, "read write"

    add_column :identity_access_tokens, :token_digest, :string
    add_column :identity_access_tokens, :expires_at, :datetime
    add_column :identity_access_tokens, :revoked_at, :datetime
    add_column :identity_access_tokens, :last_used_at, :datetime
    add_column :identity_access_tokens, :resource, :string

    AccessToken.reset_column_information

    AccessToken.find_each do |access_token|
      attributes = { expires_at: 1.year.from_now }

      if access_token.token.present?
        attributes[:token_digest] = Digest::SHA256.hexdigest(access_token.token)
        attributes[:token] = nil
      end

      access_token.update_columns(attributes)
    end

    add_index :identity_access_tokens, :token_digest, unique: true
    add_index :identity_access_tokens, :expires_at
    add_index :identity_access_tokens, :revoked_at
    add_index :identity_access_tokens, :resource
  end

  def down
    change_column_default :oauth_clients, :scope, "read write"

    remove_index :identity_access_tokens, :resource
    remove_index :identity_access_tokens, :revoked_at
    remove_index :identity_access_tokens, :expires_at
    remove_index :identity_access_tokens, :token_digest

    remove_column :identity_access_tokens, :resource
    remove_column :identity_access_tokens, :last_used_at
    remove_column :identity_access_tokens, :revoked_at
    remove_column :identity_access_tokens, :expires_at
    remove_column :identity_access_tokens, :token_digest
  end
end
