require "test_helper"

class Oauth::MetadataControllerTest < ActionDispatch::IntegrationTest
  test "protected resource metadata advertises mcp resource" do
    untenanted do
      get oauth_protected_resource_path
    end

    assert_response :success
    metadata = @response.parsed_body
    assert_equal mcp_url(script_name: nil), metadata["resource"]
    assert_includes metadata["authorization_servers"], root_url(script_name: nil).delete_suffix("/")
    assert_equal %w[ read write ], metadata["scopes_supported"]
  end

  test "authorization server metadata advertises oauth endpoints and pkce" do
    untenanted do
      get oauth_authorization_server_path
    end

    assert_response :success
    metadata = @response.parsed_body
    assert_equal oauth_authorize_url(script_name: nil), metadata["authorization_endpoint"]
    assert_equal oauth_token_url(script_name: nil), metadata["token_endpoint"]
    assert_equal oauth_revoke_url(script_name: nil), metadata["revocation_endpoint"]
    assert_equal oauth_register_url(script_name: nil), metadata["registration_endpoint"]
    assert_equal [ "S256" ], metadata["code_challenge_methods_supported"]
    assert_equal [ "none" ], metadata["token_endpoint_auth_methods_supported"]
  end
end
