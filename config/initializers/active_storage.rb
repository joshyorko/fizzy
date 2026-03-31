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
      super.merge url: Rails.application.routes.url_helpers.rails_blob_path(self, only_path: true)
    end
  end
end

# Don't configure replica connections for ActiveStorage::Record.
# When ActiveStorage uses `connects_to`, it creates a separate connection pool
# from ApplicationRecord. This causes after_commit callbacks to fire in
# non-deterministic order - the Attachment's create_variants callback can fire
# before the User model's upload callback, causing FileNotFoundError when
# using `process: :immediately` for variants.
# See: https://github.com/rails/rails/issues/53694
ActiveSupport.on_load(:active_storage_record) do
  configure_replica_connections
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
    skip_forgery_protection if: :authenticate_by_bearer_token
  end
end

module ActiveStorageVariantWithRecordExtensions
  private
    # Variant generation can happen outside a request, so derivative blobs need
    # the source blob's tenant applied explicitly before attachment validation.
    def create_or_find_record(image:)
      Current.with(account: blob.account) { super }
    end

    # Variant records can point at derivative blobs whose objects are missing in
    # storage. Treat those as stale so the next request regenerates the preview.
    def processed?
      super && !stale_record?
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
