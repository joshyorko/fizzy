class ActiveStorage::MultipartUpload
  MAXIMUM_UPLOAD_PARTS_COUNT = 10_000
  MINIMUM_UPLOAD_PART_SIZE = 5.megabytes
  DEFAULT_PART_SIZE = 10.megabytes
  CLIENT_THRESHOLD = 64.megabytes

  attr_reader :blob

  def initialize(blob)
    @blob = blob
  end

  def initiate
    ensure_supported_service!

    upload_id = client.create_multipart_upload(
      bucket: bucket.name,
      key: blob.key,
      content_type: blob.content_type,
      metadata: blob.custom_metadata,
      **service.upload_options
    ).upload_id

    {
      upload_id: upload_id,
      part_size: part_size,
      parts: part_urls_for(upload_id),
      complete_url: Rails.application.routes.url_helpers.complete_rails_multipart_upload_path(blob.signed_id, url_options),
      abort_url: Rails.application.routes.url_helpers.rails_multipart_upload_path(blob.signed_id, url_options)
    }
  end

  def complete!(upload_id:, parts:)
    ensure_supported_service!

    client.complete_multipart_upload(
      bucket: bucket.name,
      key: blob.key,
      upload_id: upload_id,
      multipart_upload: {
        parts: normalize_parts(parts)
      }
    )
  end

  def abort!(upload_id:)
    ensure_supported_service!

    client.abort_multipart_upload(
      bucket: bucket.name,
      key: blob.key,
      upload_id: upload_id
    )
  end

  private
    def normalize_parts(parts)
      Array(parts).map do |part|
        {
          part_number: Integer(part.fetch(:part_number) || part.fetch("part_number")),
          etag: part.fetch(:etag) || part.fetch("etag")
        }
      end.sort_by { |part| part[:part_number] }
    end

    def part_urls_for(upload_id)
      part_count.times.map do |index|
        part_number = index + 1

        {
          part_number: part_number,
          url: presigner.presigned_url(
            :upload_part,
            bucket: bucket.name,
            key: blob.key,
            upload_id: upload_id,
            part_number: part_number,
            expires_in: ActiveStorage.service_urls_for_direct_uploads_expire_in.to_i
          )
        }
      end
    end

    def part_count
      (blob.byte_size.to_f / part_size).ceil
    end

    def part_size
      @part_size ||= [ DEFAULT_PART_SIZE, MINIMUM_UPLOAD_PART_SIZE, (blob.byte_size.to_f / MAXIMUM_UPLOAD_PARTS_COUNT).ceil ].max
    end

    def presigner
      @presigner ||= Aws::S3::Presigner.new(client: client)
    end

    def client
      service.client.client
    end

    def bucket
      service.bucket
    end

    def service
      blob.service
    end

    def ensure_supported_service!
      return if service.respond_to?(:client) && service.respond_to?(:bucket) && service.respond_to?(:upload_options)

      raise NotImplementedError, "Multipart uploads require Active Storage S3 service"
    end

    def url_options
      ActiveStorage::Current.url_options.to_h.symbolize_keys.merge(only_path: true)
    end
end
