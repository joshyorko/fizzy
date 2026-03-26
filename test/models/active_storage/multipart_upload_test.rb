require "test_helper"
require "aws-sdk-s3"

class ActiveStorage::MultipartUploadTest < ActiveSupport::TestCase
  test "initiate includes tenant-aware urls and part metadata" do
    ActiveStorage::Current.url_options = {
      protocol: "https://",
      host: "fizzy.joshyorko.com",
      port: 443,
      script_name: "/#{ActiveRecord::FixtureSet.identify("37signals")}"
    }

    blob = ActiveStorage::Blob.create_before_direct_upload!(
      filename: "video.mp4",
      byte_size: 128.megabytes,
      checksum: "GQ5SqLsM7ylnji0Wgd9wNC==",
      content_type: "video/mp4",
      service_name: ActiveStorage::Blob.service.name
    )

    client = mock
    client.expects(:create_multipart_upload).returns(stub(upload_id: "upload-123"))

    bucket = stub(name: "uploads")
    service = stub(client: stub(client: client), bucket: bucket, upload_options: {}, name: ActiveStorage::Blob.service.name)
    blob.stubs(:service).returns(service)

    presigner = mock
    presigner.expects(:presigned_url).at_least_once.returns("https://uploads.example.test/part-1")
    ::Aws::S3::Presigner.stubs(:new).returns(presigner)

    payload = ActiveStorage::MultipartUpload.new(blob).initiate

    assert_equal "upload-123", payload[:upload_id]
    assert_equal "/#{ActiveRecord::FixtureSet.identify("37signals")}/rails/active_storage/multipart_uploads/#{blob.signed_id}/complete", payload[:complete_url]
    assert_equal "/#{ActiveRecord::FixtureSet.identify("37signals")}/rails/active_storage/multipart_uploads/#{blob.signed_id}", payload[:abort_url]
    assert_operator payload[:part_size], :>=, 5.megabytes
    assert_equal 13, payload[:parts].count
  end
end
