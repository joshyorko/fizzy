class Oauth::RevocationsController < Oauth::BaseController
  allow_unauthenticated_access
  skip_forgery_protection
  rate_limit to: 30, within: 5.minutes, only: :create, with: -> { render status: :too_many_requests, json: { error: "rate_limited" } }

  def create
    token_digest = Identity::AccessToken.digest(params[:token].to_s)
    Identity::AccessToken.oauth.find_by(token_digest: token_digest)&.destroy

    head :ok
  end
end
