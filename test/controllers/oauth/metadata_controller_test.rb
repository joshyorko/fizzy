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

  test "openid configuration advertises the authorization server metadata" do
    untenanted do
      get "/.well-known/openid-configuration"
    end

    assert_response :success
    metadata = @response.parsed_body
    assert_equal root_url(script_name: nil).delete_suffix("/"), metadata["issuer"]
    assert_equal oauth_authorize_url(script_name: nil), metadata["authorization_endpoint"]
    assert_equal oauth_token_url(script_name: nil), metadata["token_endpoint"]
  end

  test "resource-relative metadata aliases return oauth metadata" do
    {
      "/.well-known/oauth-protected-resource/mcp" => "resource",
      "/mcp/.well-known/oauth-protected-resource" => "resource",
      "/.well-known/oauth-authorization-server/mcp" => "authorization_endpoint",
      "/mcp/.well-known/oauth-authorization-server" => "authorization_endpoint"
    }.each do |path, expected_key|
      untenanted do
        get path
      end

      assert_response :success
      assert @response.parsed_body[expected_key].present?
    end
  end
end
