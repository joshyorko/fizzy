require "test_helper"

class ActiveStorageRichTextAttributesUrlTest < ActiveSupport::TestCase
  test "blob rich text attributes use the configured proxy route" do
    blob = Current.with(account: accounts(:acme)) do
      ActiveStorage::Blob.create_and_upload!(
        io: file_fixture("moon.jpg").open,
        filename: "moon.jpg",
        content_type: "image/jpeg"
      )
    end

    original_route = ActiveStorage.resolve_model_to_route
    ActiveStorage.resolve_model_to_route = :rails_storage_proxy

    assert_includes blob.to_rich_text_attributes[:url], "/rails/active_storage/blobs/proxy/"
  ensure
    ActiveStorage.resolve_model_to_route = original_route
  end
end
