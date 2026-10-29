# frozen_string_literal: true

require "time"

module CtxRunner
  # 显式证据边界：生成独立 JSON 值，不通过文本往返转换业务事实。
  module Document
    MAX_DEPTH = 128
    # 组合值对象显式加入文档协议；不对任意外部对象调用 to_h。
    module Value; end

    def self.call(value)
      convert(value, {}.compare_by_identity, 0)
    end

    def self.convert(value, active, depth)
      raise ArgumentError, "Document nesting exceeds the evidence budget" if depth > MAX_DEPTH
      case value
      when Hash, Array, Data, Value
        raise ArgumentError, "Document must not contain cyclic data" if active[value]
        active[value] = true
        begin
          case value
          when Data, Value then convert(value.to_h, active, depth + 1)
          when Array then value.map { |item| convert(item, active, depth + 1) }.freeze
          when Hash
            value.each_with_object({}) do |(key, item), result|
              # 符号名已由 Ruby 持有并冻结；其他键复制后才冻结，不占用调用方对象。
              name = case key
              when Symbol then key.name
              when String, Integer, Float, Rational, Complex, NilClass, TrueClass, FalseClass then String.new(key.to_s)
              else raise ArgumentError, "Document keys must be plain values"
              end
              raise ArgumentError, "Document keys collide after normalization" if result.key?(name)
              result[name.freeze] = convert(item, active, depth + 1)
            end.freeze
          end
        ensure
          active.delete(value)
        end
      when Time then value.getutc.iso8601(6).freeze
      when String then value.dup.freeze
      when Symbol then value.name
      when Rational, Complex then value.to_s.freeze
      when Float
        raise ArgumentError, "Document numbers must be finite" unless value.finite?
        value
      when Integer, NilClass, TrueClass, FalseClass then value
      else raise ArgumentError, "Document must contain plain values"
      end
    end
    private_class_method :convert
  end
end
