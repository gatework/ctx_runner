# frozen_string_literal: true

require "ipaddr"

module CtxRunner
  # 离线证据的公共外壳；记录字段和领域语义交给消费模块校验。
  module Evidence
    def self.validate(document)
      unless document.is_a?(Hash) && document["device"].is_a?(Hash) &&
          %w[name host].all? { |key| document["device"][key].is_a?(String) && !document["device"][key].empty? }
        raise ArgumentError, "无设备身份"
      end
      host = document["device"]["host"]
      raise ArgumentError, "目标地址须为规范主机地址" unless !host.include?("/") && IPAddr.new(host).to_s == host
      snapshot = document.fetch("snapshot")
      return if snapshot.nil?
      raise ArgumentError, "快照结构错误" unless snapshot.is_a?(Hash) && snapshot["dimensions"].is_a?(Hash)
      if !snapshot["target"].is_a?(Hash) || snapshot["target"]["host"] != host
        raise ArgumentError, "设备身份与采集目标不一致"
      end
      snapshot["dimensions"].each do |dimension, observation|
        unless observation.is_a?(Hash) && %w[complete partial failed unsupported not_requested].include?(observation["status"])
          raise ArgumentError, "观测结构错误"
        end
        records = array(observation.fetch("records"))
        array(observation.fetch("issues", []))
        records.each { |record| yield(record, dimension) }
      end
    end

    def self.array(value)
      raise ArgumentError, "列表结构错误" unless value.is_a?(Array) && value.all? { |entry| entry.is_a?(Hash) }
      value
    end

    def self.map(value)
      raise ArgumentError, "映射结构错误" unless value.is_a?(Hash) && value.values.all? { |entry| entry.is_a?(Hash) }
      value
    end
  end
end
