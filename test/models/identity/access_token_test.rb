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

  test "new tokens keep only a digest after creation" do
    token = identities(:david).access_tokens.create!(description: "PAT", permission: "write")
    raw_token = token.token

    assert raw_token.start_with?("fzy_")
    assert_nil token.read_attribute(:token)
    assert_equal Identity::AccessToken.digest(raw_token), token.token_digest
    assert_nil Identity::AccessToken.find(token.id).token
  end

  test "authenticate records use and rejects bad expired or revoked tokens" do
    token = identities(:david).access_tokens.create!(description: "PAT", permission: "read")
    raw_token = token.token

    assert_equal token, Identity::AccessToken.authenticate(raw_token)
    assert token.reload.last_used_at.present?
    assert_nil Identity::AccessToken.authenticate("nope")

    token.update!(expires_at: 1.minute.ago)
    assert_nil Identity::AccessToken.authenticate(raw_token)

    token.update!(expires_at: 1.minute.from_now, revoked_at: Time.current)
    assert_nil Identity::AccessToken.authenticate(raw_token)
  end

  test "oauth tokens require the matching resource audience" do
    client = Oauth::Client.create!(
      client_name: "ChatGPT",
      redirect_uris: [ "https://chat.openai.com/aip/plugin/oauth/callback" ],
      scope: "read write"
    )
    token = identities(:david).access_tokens.create!(
      description: "OAuth",
      permission: "write",
      oauth_client: client,
      resource: "https://example.test/mcp"
    )
    raw_token = token.token

    assert_nil Identity::AccessToken.authenticate(raw_token)
    assert_nil Identity::AccessToken.authenticate(raw_token, resource: "https://elsewhere.test/mcp")
    assert_equal token, Identity::AccessToken.authenticate(raw_token, resource: "https://example.test/mcp")
  end
end
