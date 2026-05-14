require "test_helper"

class ActiveStorageVariantWithRecordTest < ActiveSupport::TestCase
  setup do
    @account = accounts("37s")

    @blob = Current.with(account: @account) do
      ActiveStorage::Blob.create_and_upload!(
        io: file_fixture("moon.jpg").open,
        filename: "moon.jpg",
        content_type: "image/jpeg"
      )
    end
  end

  test "processed variant inherits the source blob account without ambient current account" do
    variant = nil

    Current.without_account do
      variant = @blob.variant(resize_to_limit: [ 100, 100 ]).processed
    end

    assert_equal @account, variant.image.record.account
    assert_equal @account, variant.image.blob.account
  end

  test "processed variant regenerates when the stored derivative object is missing" do
    stale_variant = Current.with(account: @account) do
      @blob.variant(resize_to_limit: [ 100, 100 ]).processed
    end

    stale_record_id = stale_variant.image.record.id
    stale_blob = stale_variant.image.blob
    stale_blob.service.delete(stale_blob.key)

    regenerated_variant = Current.without_account do
      @blob.variant(resize_to_limit: [ 100, 100 ]).processed
    end

    assert_not_equal stale_record_id, regenerated_variant.image.record.id
    assert regenerated_variant.image.blob.service.exist?(regenerated_variant.image.blob.key)
  end
end
