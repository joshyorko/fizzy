class CreateOauthClients < ActiveRecord::Migration[8.1]
  def change
    create_table :oauth_clients, id: :uuid do |t|
      t.string :client_id, null: false
      t.string :client_name
      t.json :redirect_uris, null: false
      t.string :token_endpoint_auth_method, null: false, default: "none"
      t.string :scope, null: false, default: "read write"
      t.json :grant_types
      t.json :response_types

      t.timestamps

      t.index :client_id, unique: true
    end
  end
end
