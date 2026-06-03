class Oauth::BaseController < ApplicationController
  skip_before_action :require_account

  private
    def issuer_url
      root_url(script_name: nil).delete_suffix("/")
    end

    def mcp_resource_url
      mcp_url(script_name: nil)
    end

    def canonical_mcp_resource_url(resource)
      resource.to_s.delete_suffix("/")
    end

    def mcp_resource_url?(resource)
      canonical_mcp_resource_url(resource) == mcp_resource_url
    end
end
