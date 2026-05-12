require "test_helper"

class Oauth::RegistrationsControllerTest < ActionDispatch::IntegrationTest
  test "dynamic registration creates public client" do
    assert_difference -> { Oauth::Client.count }, +1 do
      untenanted do
        post oauth_register_path,
          params: {
            client_name: "ChatGPT",
            redirect_uris: [ "https://chat.openai.com/aip/plugin/oauth/callback" ],
            scope: "read write"
          },
          as: :json
      end
    end

    assert_response :created
    body = @response.parsed_body
    assert body["client_id"].present?
    assert_equal "ChatGPT", body["client_name"]
    assert_equal [ "https://chat.openai.com/aip/plugin/oauth/callback" ], body["redirect_uris"]
    assert_equal "none", body["token_endpoint_auth_method"]
    assert_equal "read write", body["scope"]
  end

  test "dynamic registration defaults to read write for ChatGPT tools" do
    assert_difference -> { Oauth::Client.count }, +1 do
      untenanted do
        post oauth_register_path,
          params: {
            client_name: "ChatGPT",
            redirect_uris: [ "https://chatgpt.com/connector/oauth/callback" ]
          },
          as: :json
      end
    end

    assert_response :created
    assert_equal "read write", @response.parsed_body["scope"]
  end

  test "dynamic registration accepts Codex loopback callback" do
    assert_difference -> { Oauth::Client.count }, +1 do
      untenanted do
        post oauth_register_path,
          params: {
            client_name: "Codex",
            redirect_uris: [ "http://127.0.0.1:14567/oauth/callback" ],
            scope: "read"
          },
          as: :json
      end
    end

    assert_response :created
    assert_equal [ "http://127.0.0.1:14567/oauth/callback" ], @response.parsed_body["redirect_uris"]
  end

  test "dynamic registration rejects invalid redirect schemes" do
    assert_no_difference -> { Oauth::Client.count } do
      untenanted do
        post oauth_register_path,
          params: {
            client_name: "ChatGPT",
            redirect_uris: [ "javascript:alert(1)" ],
            scope: "read"
          },
          as: :json
      end
    end

    assert_response :bad_request
    assert_equal "invalid_client_metadata", @response.parsed_body["error"]
  end

  test "dynamic registration rejects unknown scopes" do
    assert_no_difference -> { Oauth::Client.count } do
      untenanted do
        post oauth_register_path,
          params: {
            client_name: "ChatGPT",
            redirect_uris: [ "https://chat.openai.com/aip/plugin/oauth/callback" ],
            scope: "read delete"
          },
          as: :json
      end
    end

    assert_response :bad_request
    assert_equal "invalid_scope", @response.parsed_body["error"]
  end
end
