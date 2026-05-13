class Oauth::RevocationsController < Oauth::BaseController
  allow_unauthenticated_access
  skip_forgery_protection
  rate_limit to: 30, within: 5.minutes, only: :create, with: -> { head :ok }

  def create
    Identity::AccessToken.find_by(token: params[:token].to_s)&.destroy

    head :ok
  end
end
