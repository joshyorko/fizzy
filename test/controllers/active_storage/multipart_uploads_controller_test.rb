require "test_helper"

class ActiveStorage::MultipartUploadsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @blob_params = {
      blob: {
        filename: "video.mp4",
        byte_size: 128.megabytes,
        checksum: "GQ5SqLsM7ylnji0Wgd9wNC==",
        content_type: "video/mp4"
      }
    }
  end

  test "create" do
    sign_in_as :david

    multipart_upload = stub(
      initiate: {
        upload_id: "upload-123",
        part_size: 10.megabytes,
        parts: [ { part_number: 1, url: "https://uploads.example.test/part-1" } ],
        complete_url: "/rails/active_storage/multipart_uploads/blob-id/complete",
        abort_url: "/rails/active_storage/multipart_uploads/blob-id"
      }
    )
    ActiveStorage::MultipartUpload.expects(:new).returns(multipart_upload)

    post rails_multipart_uploads_path,
      params: @blob_params,
      headers: bearer_token_header(identity_access_tokens(:davids_api_token).token),
      as: :json

    assert_response :success
    assert_includes response.parsed_body.keys, "multipart_upload"
    assert_equal "upload-123", response.parsed_body.dig("multipart_upload", "upload_id")
  end

  test "create with valid access token in another account is forbidden" do
    post rails_multipart_uploads_path(script_name: "/#{ActiveRecord::FixtureSet.identify("initech")}"),
      params: @blob_params,
      headers: bearer_token_header(identity_access_tokens(:davids_api_token).token),
      as: :json

    assert_response :forbidden
  end

  test "complete" do
    sign_in_as :david
    blob = ActiveStorage::Blob.create_before_direct_upload!(**@blob_params[:blob])

    multipart_upload = stub
    multipart_upload.expects(:complete!).with(
      upload_id: "upload-123",
      parts: [ { "part_number" => 1, "etag" => "\"etag-1\"" } ]
    )
    ActiveStorage::MultipartUpload.expects(:new).with(blob).returns(multipart_upload)

    post complete_rails_multipart_upload_path(blob.signed_id),
      params: {
        multipart_upload: {
          upload_id: "upload-123",
          parts: [ { part_number: 1, etag: "\"etag-1\"" } ]
        }
      },
      as: :json

    assert_response :success
    assert_equal blob.signed_id, response.parsed_body["signed_id"]
  end

  test "destroy" do
    sign_in_as :david
    blob = ActiveStorage::Blob.create_before_direct_upload!(**@blob_params[:blob])

    multipart_upload = stub
    multipart_upload.expects(:abort!).with(upload_id: "upload-123")
    ActiveStorage::MultipartUpload.expects(:new).with(blob).returns(multipart_upload)

    delete rails_multipart_upload_path(blob.signed_id), params: { upload_id: "upload-123" }

    assert_response :no_content
  end

  private
    def bearer_token_header(token)
      { "Authorization" => "Bearer #{token}" }
    end
end
