class CreateOauthAuthorizationCodes < ActiveRecord::Migration[8.1]
  def change
    create_table :oauth_authorization_codes, id: :uuid do |t|
      t.uuid :client_id, null: false
      t.uuid :identity_id, null: false
      t.string :code, null: false
      t.string :redirect_uri, null: false
      t.string :code_challenge, null: false
      t.string :code_challenge_method, null: false
      t.string :scope, null: false
      t.string :resource, null: false
      t.datetime :expires_at, null: false
      t.datetime :used_at

      t.timestamps

      t.index :client_id
      t.index :identity_id
      t.index :code, unique: true
      t.index :expires_at
    end
  end
end
