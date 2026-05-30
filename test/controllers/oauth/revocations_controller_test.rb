require "test_helper"

class Oauth::RevocationsControllerTest < ActionDispatch::IntegrationTest
  test "revocation destroys known access token" do
    client = Oauth::Client.create!(
      client_name: "ChatGPT",
      redirect_uris: [ "https://chat.openai.com/aip/plugin/oauth/callback" ],
      scope: "read"
    )
    token = identities(:david).access_tokens.create!(description: "ChatGPT", permission: "read", oauth_client: client)

    assert_difference -> { Identity::AccessToken.count }, -1 do
      untenanted do
        post oauth_revoke_path, params: { token: token.token }
      end
    end

    assert_response :success
  end

  test "revocation ignores personal access tokens" do
    token = identities(:david).access_tokens.create!(description: "Personal token", permission: "read")

    assert_no_difference -> { Identity::AccessToken.count } do
      untenanted do
        post oauth_revoke_path, params: { token: token.token, token_type_hint: "access_token" }
      end
    end

    assert_response :success
    assert_not_nil token.reload
  end

  test "revocation returns ok for unknown token" do
    assert_no_difference -> { Identity::AccessToken.count } do
      untenanted do
        post oauth_revoke_path, params: { token: "unknown" }
      end
    end

    assert_response :success
  end
end
