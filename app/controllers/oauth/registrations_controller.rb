class Oauth::RegistrationsController < Oauth::BaseController
  allow_unauthenticated_access

  def create
    client = Oauth::Client.new(client_params)

    if client.save
      render status: :created, json: {
        client_id: client.client_id,
        client_name: client.client_name,
        redirect_uris: client.redirect_uris,
        grant_types: client.grant_types,
        response_types: client.response_types,
        token_endpoint_auth_method: client.token_endpoint_auth_method,
        scope: client.scope,
        client_id_issued_at: client.created_at.to_i
      }
    else
      render status: :bad_request, json: registration_error(client)
    end
  end

  private
    def registration_error(client)
      error = client.errors.key?(:scope) ? "invalid_scope" : "invalid_client_metadata"
      { error: error, error_description: client.errors.full_messages.to_sentence }
    end

    def client_params
      {
        client_name: params[:client_name],
        redirect_uris: params[:redirect_uris],
        grant_types: params[:grant_types],
        response_types: params[:response_types],
        scope: params[:scope],
        token_endpoint_auth_method: params[:token_endpoint_auth_method]
      }
    end
end
