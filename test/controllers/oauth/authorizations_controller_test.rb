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

  test "consent accepts Codex loopback callback without resource parameter" do
    @client.update!(client_name: "Codex", redirect_uris: [ codex_redirect_uri ])
    sign_in_as :david

    assert_difference -> { Oauth::AuthorizationCode.count }, +1 do
      untenanted do
        post oauth_authorize_path, params: authorization_params(resource: nil)
      end
    end

    authorization_code = Oauth::AuthorizationCode.last
    assert_redirected_to %r{\Ahttp://127\.0\.0\.1:14567/oauth/callback\?}
    assert_equal mcp_url(script_name: nil), authorization_code.resource
  end

  test "consent accepts mcp resource with trailing slash" do
    sign_in_as :david

    assert_difference -> { Oauth::AuthorizationCode.count }, +1 do
      untenanted do
        post oauth_authorize_path, params: authorization_params(resource: "#{mcp_url(script_name: nil)}/")
      end
    end

    assert_equal mcp_url(script_name: nil), Oauth::AuthorizationCode.last.resource
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

  test "consent page presents normalized access and connection details" do
    sign_in_as :david

    untenanted do
      get oauth_authorize_path, params: authorization_params(scope: "write read")
    end

    assert_response :success
    assert_match "Access requested:", @response.body
    assert_match "Read + Write", @response.body
    assert_match "Connection details", @response.body
    assert_match "Client ID:", @response.body
    assert_match "Redirects to:", @response.body
    assert_select "input[name=scope][value='read write']", count: 1
  end

  test "consent page allows registered loopback oauth callback after form post" do
    @client.update!(client_name: "Codex", redirect_uris: [ codex_redirect_uri ])
    sign_in_as :david

    untenanted do
      get oauth_authorize_path, params: authorization_params(resource: nil)
    end

    assert_response :success
    assert_match "http://127.0.0.1:14567", @response.headers["Content-Security-Policy"]
    assert_match "Connect Codex", @response.body
  end

  private
    def authorization_params(scope: "read write", resource: mcp_url(script_name: nil))
      {
        response_type: "code",
        client_id: @client.client_id,
        redirect_uri: @client.redirect_uris.first,
        scope: scope,
        state: "abc123",
        resource: resource,
        code_challenge: Oauth::AuthorizationCode.challenge_for(@verifier),
        code_challenge_method: "S256"
      }
    end

    def codex_redirect_uri
      "http://127.0.0.1:14567/oauth/callback"
    end
end
