require "test_helper"

class Oauth::RevocationsControllerTest < ActionDispatch::IntegrationTest
  test "revocation destroys known access token" do
    token = identities(:david).access_tokens.create!(description: "ChatGPT", permission: "read")

    assert_difference -> { Identity::AccessToken.count }, -1 do
      untenanted do
        post oauth_revoke_path, params: { token: token.token }
      end
    end

    assert_response :success
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
