# frozen_string_literal: true

require "ctx_parser/immutable"

module CtxRunner
  # 设备身份与连接设置分离；边界只接受公开字段，Ruby 内部统一符号键。
  class Target < Data.define(:host, :platform, :name, :model, :software_version, :id)
    FIELDS = %i[host platform name model software_version id].freeze

    def self.coerce(value)
      return value if value.is_a?(self)
      raise ArgumentError, "Target must be a mapping of public identity fields" unless value.is_a?(Hash)
      result = value.each_with_object({}) do |(key, entry), target|
        unless (key.is_a?(String) || key.is_a?(Symbol)) && FIELDS.include?(key.to_sym) && !target.key?(key.to_sym)
          raise ArgumentError, "Target contains unknown or duplicate identity fields"
        end
        target[key.to_sym] = entry
      end
      raise ArgumentError, "Target requires a host" unless result[:host].is_a?(String)
      new(**result)
    end

    def initialize(host:, platform: nil, name: nil, model: nil, software_version: nil, id: nil)
      attributes = { host: host, platform: platform, name: name, model: model, software_version: software_version, id: id }
      unless host.is_a?(String) && attributes.all? do |key, value|
          value.nil? || value.is_a?(String) && !value.strip.empty? && !/[\x00-\x1f\x7f]/.match?(value) || key == :id && value.is_a?(Integer) && value >= 0
        end
        raise ArgumentError, "Invalid target identity value"
      end
      super(**CtxParser::Immutable.copy(attributes))
    end

    def identity_key = [ host, platform, id ].freeze
    def same_identity?(other) = other.is_a?(Target) && identity_key == other.identity_key
    def to_h = super.compact
    def inspect = "#<#{self.class.name}>"
    alias to_s inspect
    def pretty_print(printer) = printer.text(inspect)
  end
end
