# frozen_string_literal: true

require "ctx_parser/immutable"

module CtxRunner
  # 设备身份与连接设置分离；边界只接受公开字段，Ruby 内部统一符号键。
  module Target
    FIELDS = %i[host platform name model software_version id].freeze

    def self.snapshot(value)
      raise ArgumentError, "Target must be a mapping of public identity fields" unless value.is_a?(Hash)
      result = value.each_with_object({}) do |(key, entry), target|
        unless (key.is_a?(String) || key.is_a?(Symbol)) && FIELDS.include?(key.to_sym) && !target.key?(key.to_sym)
          raise ArgumentError, "Target contains unknown or duplicate identity fields"
        end
        unless entry.nil? || entry.is_a?(String) && !entry.strip.empty? && !/[\x00-\x1f\x7f]/.match?(entry) || key.to_sym == :id && entry.is_a?(Integer) && entry >= 0
          raise ArgumentError, "Invalid target identity value"
        end
        target[key.to_sym] = entry
      end
      raise ArgumentError, "Target requires a host" unless result[:host].is_a?(String)
      CtxParser::Immutable.copy(result)
    end
  end
end
