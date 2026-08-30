ActiveSupport.on_load(:active_storage_attachment) do
  include Storage::AttachmentTracking
end

ActiveSupport.on_load(:active_storage_blob) do
  ActiveStorage::DiskController.after_action only: :show do
    expires_in 5.minutes, public: true
  end
end

ActiveSupport.on_load(:action_text_content) do
  # Install our extensions after ActionText::Engine's
  ActiveSupport.on_load(:active_storage_blob) do
    # Ensure all <action-text-attachment>s have a "url" attribute that's a relative
    # path (for portability across host name changes, beta environments, etc).
    # Use rails_blob_path so edit mode follows Active Storage's configured
    # proxy/redirect route instead of hard-coding a storage route.
    def to_rich_text_attributes(*)
      super.merge url: Rails.application.routes.url_helpers.rails_blob_path(self, only_path: true, script_name: Current.account&.slug)
    end
  end
end

# ApplicationRecord calls `configure_replica_connections` to set up connection pools for the
# application models. We want ActiveStorage::Record to use the same pools for transactional
# integrity, proper callback invocation, joins, etc., however ActiveStorage::Record inherits from
# ActiveRecord::Base, not ApplicationRecord. This is how we make Active Storage always use the
# ApplicationRecord connection pool.
ActiveSupport.on_load(:active_storage_record) do
  class << self
    delegate :connection_pool, to: "ApplicationRecord"
  end
end

module ActiveStorageControllerExtensions
  extend ActiveSupport::Concern

  included do
    before_action do
      # Add script_name so that Disk Service will generate correct URLs for uploads
      ActiveStorage::Current.url_options = {
        protocol: request.protocol,
        host: request.host,
        port: request.port,
        script_name: request.script_name
      }
    end
  end
end

module ActiveStorageDirectUploadsControllerExtensions
  extend ActiveSupport::Concern

  included do
    include Authentication
    include Authorization
    include RequestForgeryProtection
  end
end

module ActiveStorageVariantWithRecordExtensions
  # Variant records can point at derivative blobs whose objects are missing in
  # storage. Treat those as stale so the next request regenerates the preview.
  def processed?
    super && !stale_record?
  end

  private
    # Variant generation can happen outside a request, so derivative blobs need
    # the source blob's tenant applied explicitly before attachment validation.
    def create_or_find_record(image:)
      Current.with(account: blob.account) { super }
    end

    def process
      purge_stale_record!
      super
    end

    def stale_record?
      current_record = record
      image_blob = current_record&.image_attachment&.blob

      current_record.present? && (image_blob.blank? || !image_blob.service.exist?(image_blob.key))
    end

    def purge_stale_record!
      return unless stale_record?

      Current.with(account: blob.account) do
        record.destroy!
      end

      @record = nil
    end
end

Rails.application.config.to_prepare do
  ActiveStorage::BaseController.include ActiveStorageControllerExtensions
  ActiveStorage::DirectUploadsController.include ActiveStorageDirectUploadsControllerExtensions
  ActiveStorage::VariantWithRecord.prepend ActiveStorageVariantWithRecordExtensions
end
