class My::ConnectedAppsController < ApplicationController
  skip_before_action :require_account

  def index
    @connected_apps = Current.identity.access_tokens.oauth.includes(:oauth_client).group_by(&:oauth_client)
  end

  def destroy
    Current.identity.access_tokens.oauth.where(oauth_client_id: params[:id]).destroy_all

    redirect_to my_connected_apps_path
  end
end
