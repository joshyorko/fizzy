require "test_helper"

class My::ConnectedAppsControllerTest < ActionDispatch::IntegrationTest
  setup do
    sign_in_as :david
    @client = Oauth::Client.create!(
      client_name: "ChatGPT",
      redirect_uris: [ "https://chat.openai.com/aip/plugin/oauth/callback" ],
      scope: "read write"
    )
  end

  test "index lists connected oauth apps" do
    identities(:david).access_tokens.create!(description: "ChatGPT", permission: "read", oauth_client: @client)

    get my_connected_apps_path

    assert_response :success
    assert_in_body "Connected apps"
    assert_in_body "ChatGPT"
  end

  test "destroy revokes identity tokens for the app" do
    identities(:david).access_tokens.create!(description: "One", permission: "read", oauth_client: @client)
    identities(:david).access_tokens.create!(description: "Two", permission: "write", oauth_client: @client)

    assert_difference -> { identities(:david).access_tokens.oauth.where(oauth_client: @client).count }, -2 do
      delete my_connected_app_path(@client)
    end

    assert_redirected_to my_connected_apps_path
  end
end
