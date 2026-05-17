class My::AccessTokensController < ApplicationController
  wrap_parameters :access_token, include: %i[ description permission ]

  skip_before_action :require_account

  def index
    @access_tokens = my_access_tokens.order(created_at: :desc)
  end

  def show
    @access_token = my_access_tokens.find(verifier.verify(params[:id]))
    reveal = token_reveal

    if reveal_token_matches?(reveal)
      @token = reveal["token"] || reveal[:token]
    else
      redirect_to my_access_tokens_path, alert: "Token is no longer visible"
    end
  rescue ActiveSupport::MessageVerifier::InvalidSignature
    redirect_to my_access_tokens_path, alert: "Token is no longer visible"
  end

  def new
    @access_token = my_access_tokens.new
  end

  def create
    access_token = my_access_tokens.create!(access_token_params)

    respond_to do |format|
      format.html do
        session[:new_access_token] = {
          id: access_token.id,
          token: access_token.token,
          expires_at: 10.seconds.from_now.iso8601
        }
        expiring_id = verifier.generate access_token.id, expires_in: 10.seconds
        redirect_to my_access_token_path(expiring_id)
      end

      format.json do
        render status: :created, json: \
          { id: access_token.id, token: access_token.token, description: access_token.description,
            permission: access_token.permission, created_at: access_token.created_at.utc }
      end
    end
  end

  def destroy
    my_access_tokens.find(params[:id]).destroy!

    respond_to do |format|
      format.html { redirect_to my_access_tokens_path }
      format.json { head :no_content }
    end
  end

  private
    def my_access_tokens
      Current.identity.access_tokens
    end

    def access_token_params
      params.expect(access_token: %i[ description permission ])
    end

    def verifier
      Rails.application.message_verifier(:access_tokens)
    end

    def token_reveal
      session.delete(:new_access_token)
    end

    def reveal_token_matches?(reveal)
      return false if reveal.blank?

      (reveal["id"] || reveal[:id]) == @access_token.id &&
        Time.iso8601(reveal["expires_at"] || reveal[:expires_at]).future?
    end
end
