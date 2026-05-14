module Oauth::Scope
  DEFAULT = "read write"
  SUPPORTED = %w[ read write ].freeze

  class << self
    def normalize(scope)
      requested = scope.to_s.split & SUPPORTED
      requested = [ "read" ] if requested.empty?
      requested.unshift("read") if requested.include?("write") && requested.exclude?("read")
      requested.uniq.join(" ")
    end

    def valid?(scope)
      (scope.to_s.split - SUPPORTED).empty?
    end

    def permission_for(scope)
      normalize(scope).split.include?("write") ? "write" : "read"
    end
  end
end
