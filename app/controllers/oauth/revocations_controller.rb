class Oauth::RevocationsController < Oauth::BaseController
  allow_unauthenticated_access
  skip_forgery_protection
  rate_limit to: 30, within: 5.minutes, only: :create, with: -> { render status: :too_many_requests, json: { error: "rate_limited" } }

  def create
    Identity::AccessToken.find_by(token: params[:token].to_s)&.destroy

    head :ok
  end
end
