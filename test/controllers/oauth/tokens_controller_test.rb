require "test_helper"

class Oauth::TokensControllerTest < ActionDispatch::IntegrationTest
  setup do
    @client = Oauth::Client.create!(
      client_name: "ChatGPT",
      redirect_uris: [ "https://chat.openai.com/aip/plugin/oauth/callback" ],
      scope: "read write"
    )
    @verifier = "oauth verifier"
    @authorization_code = @client.authorization_codes.create!(
      identity: identities(:david),
      redirect_uri: @client.redirect_uris.first,
      code_challenge: Oauth::AuthorizationCode.challenge_for(@verifier),
      code_challenge_method: "S256",
      scope: "read write",
      resource: mcp_url(script_name: nil)
    )
  end

  test "token exchange rejects wrong pkce verifier" do
    assert_no_difference -> { identities(:david).access_tokens.count } do
      untenanted do
        post oauth_token_path, params: token_params(code_verifier: "wrong")
      end
    end

    assert_response :bad_request
    assert_equal "invalid_grant", @response.parsed_body["error"]
  end

  test "token exchange creates identity access token" do
    assert_difference -> { identities(:david).access_tokens.count }, +1 do
      untenanted do
        post oauth_token_path, params: token_params
      end
    end

    assert_response :success
    body = @response.parsed_body
    assert body["access_token"].present?
    assert_equal "Bearer", body["token_type"]
    assert_equal "read write", body["scope"]
    assert identities(:david).access_tokens.last.write?
    assert @authorization_code.reload.used_at.present?
  end

  private
    def token_params(code_verifier: @verifier)
      {
        grant_type: "authorization_code",
        client_id: @client.client_id,
        code: @authorization_code.code,
        redirect_uri: @authorization_code.redirect_uri,
        resource: @authorization_code.resource,
        code_verifier: code_verifier
      }
    end
end
