class ActiveStorage::MultipartUploadsController < ActiveStorage::DirectUploadsController
  before_action :set_blob, only: [ :complete, :destroy ]

  def create
    blob = ActiveStorage::Blob.create_before_direct_upload!(**blob_args)

    render json: blob_json(blob).merge(
      multipart_upload: ActiveStorage::MultipartUpload.new(blob).initiate
    )
  rescue NotImplementedError => error
    render json: { error: error.message }, status: :unprocessable_entity
  end

  def complete
    ActiveStorage::MultipartUpload.new(@blob).complete!(**multipart_upload_params)
    render json: blob_json(@blob)
  end

  def destroy
    ActiveStorage::MultipartUpload.new(@blob).abort!(upload_id: params.expect(:upload_id))
    head :no_content
  end

  private
    def set_blob
      @blob = ActiveStorage::Blob.find_signed!(params.expect(:id))
    end

    def blob_json(blob)
      blob.as_json(root: false, methods: :signed_id)
    end

    def multipart_upload_params
      upload = params.require(:multipart_upload).permit(:upload_id, parts: [ :part_number, :etag ])
      {
        upload_id: upload.fetch(:upload_id),
        parts: Array(upload[:parts]).map(&:to_h)
      }
    end
end
