# frozen_string_literal: true

require "digest"
require "json"
require "ctx_parser/immutable"

module CtxRunner
  # 配置映射顺序不影响身份；列表顺序和全部字段仍参与旧版摘要协议。
  module Fingerprint
    def self.call(value) = Digest::SHA256.hexdigest(JSON.generate(canonical(value), max_nesting: false))

    # 先拒绝非纯数据与循环，再将键归一化；重名键不能静默覆盖来源事实。
    def self.canonical(value)
      normalize(CtxParser::Immutable.copy(value), 0)
    end

    def self.normalize(value, depth)
      raise ArgumentError, "Configuration nesting exceeds the fingerprint budget" if depth > 128

      case value
      when Hash
        normalized = {}
        value.each do |key, entry|
          raise ArgumentError, "Configuration keys must be strings or symbols" unless key.is_a?(String) || key.is_a?(Symbol)
          name = key.to_s
          raise ArgumentError, "Configuration keys collide after normalization" if normalized.key?(name)
          normalized[name] = normalize(entry, depth + 1)
        end
        normalized.sort.to_h
      when Array then value.map { |entry| normalize(entry, depth + 1) }
      else value
      end
    end
    private_class_method :normalize
  end
end
