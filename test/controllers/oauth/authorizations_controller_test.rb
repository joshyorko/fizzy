require "test_helper"

class Oauth::AuthorizationsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @client = Oauth::Client.create!(
      client_name: "ChatGPT",
      redirect_uris: [ "https://chat.openai.com/aip/plugin/oauth/callback" ],
      scope: "read write"
    )
    @verifier = "oauth verifier"
  end

  test "authorize requires an existing session" do
    untenanted do
      get oauth_authorize_path, params: authorization_params
    end

    assert_redirected_to new_session_path(script_name: nil)
  end

  test "consent creates short lived authorization code" do
    sign_in_as :david

    assert_difference -> { Oauth::AuthorizationCode.count }, +1 do
      untenanted do
        post oauth_authorize_path, params: authorization_params
      end
    end

    authorization_code = Oauth::AuthorizationCode.last
    assert_redirected_to %r{\Ahttps://chat\.openai\.com/aip/plugin/oauth/callback\?}
    assert_equal identities(:david), authorization_code.identity
    assert_equal "read write", authorization_code.scope
    assert authorization_code.expires_at.future?
  end

  test "authorize rejects unknown scopes" do
    sign_in_as :david

    assert_no_difference -> { Oauth::AuthorizationCode.count } do
      untenanted do
        get oauth_authorize_path, params: authorization_params(scope: "read delete")
      end
    end

    assert_response :bad_request
    assert_equal "invalid_scope", @response.parsed_body["error"]
  end

  test "consent page allows ChatGPT oauth callback after form post" do
    sign_in_as :david

    untenanted do
      get oauth_authorize_path, params: authorization_params
    end

    assert_response :success
    assert_match "form-action 'self' https://chatgpt.com https://chat.openai.com", @response.headers["Content-Security-Policy"]
  end

  private
    def authorization_params(scope: "read write")
      {
        response_type: "code",
        client_id: @client.client_id,
        redirect_uri: @client.redirect_uris.first,
        scope: scope,
        state: "abc123",
        resource: mcp_url(script_name: nil),
        code_challenge: Oauth::AuthorizationCode.challenge_for(@verifier),
        code_challenge_method: "S256"
      }
    end
end
