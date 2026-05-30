require "test_helper"

class Oauth::AuthorizationCodeTest < ActiveSupport::TestCase
  setup do
    @verifier = "correct horse battery staple"
    @client = Oauth::Client.create!(
      client_name: "ChatGPT",
      redirect_uris: [ "https://chat.openai.com/aip/plugin/oauth/callback" ],
      scope: "read write"
    )
  end

  test "verifies S256 PKCE challenge" do
    authorization_code = @client.authorization_codes.create!(
      identity: identities(:david),
      redirect_uri: @client.redirect_uris.first,
      code_challenge: Oauth::AuthorizationCode.challenge_for(@verifier),
      code_challenge_method: "S256",
      scope: "read write",
      resource: "https://example.com/mcp"
    )

    assert authorization_code.verifies_pkce?(@verifier)
    assert_not authorization_code.verifies_pkce?("wrong")
  end

  test "active scope excludes used and expired codes" do
    active_code = authorization_code
    used_code = authorization_code.tap(&:use)
    expired_code = authorization_code(expires_at: 1.minute.ago)

    assert_includes Oauth::AuthorizationCode.active, active_code
    assert_not_includes Oauth::AuthorizationCode.active, used_code
    assert_not_includes Oauth::AuthorizationCode.active, expired_code
  end

  private
    def authorization_code(expires_at: 10.minutes.from_now)
      @client.authorization_codes.create!(
        identity: identities(:david),
        redirect_uri: @client.redirect_uris.first,
        code_challenge: Oauth::AuthorizationCode.challenge_for(@verifier),
        code_challenge_method: "S256",
        scope: "read",
        resource: "https://example.com/mcp",
        expires_at: expires_at
      )
    end
end
