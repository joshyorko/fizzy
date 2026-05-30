module Oauth::Scope
  DEFAULT = "read write"
  SUPPORTED = %w[ read write ].freeze

  class << self
    def normalize(scope)
      requested = scope.to_s.split & SUPPORTED
      requested = [ "read" ] if requested.empty?
      requested.unshift("read") if requested.include?("write") && requested.exclude?("read")
      ordered(requested).join(" ")
    end

    def valid?(scope)
      (scope.to_s.split - SUPPORTED).empty?
    end

    def permission_for(scope)
      normalize(scope).split.include?("write") ? "write" : "read"
    end

    private
      def ordered(scopes)
        scopes.uniq.sort_by { |scope| SUPPORTED.index(scope) || SUPPORTED.length }
      end
  end
end
