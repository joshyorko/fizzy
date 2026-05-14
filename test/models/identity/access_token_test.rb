require "test_helper"

class Identity::AccessTokenTest < ActiveSupport::TestCase
  test "personal and oauth scopes separate tokens by client association" do
    client = Oauth::Client.create!(
      client_name: "ChatGPT",
      redirect_uris: [ "https://chat.openai.com/aip/plugin/oauth/callback" ],
      scope: "read"
    )
    personal_token = identities(:david).access_tokens.create!(description: "PAT", permission: "read")
    oauth_token = identities(:david).access_tokens.create!(description: "OAuth", permission: "read", oauth_client: client)

    assert_includes Identity::AccessToken.personal, personal_token
    assert_not_includes Identity::AccessToken.personal, oauth_token
    assert_includes Identity::AccessToken.oauth, oauth_token
    assert_not_includes Identity::AccessToken.oauth, personal_token
  end
end
