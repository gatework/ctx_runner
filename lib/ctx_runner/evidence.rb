# frozen_string_literal: true

require "ipaddr"
require_relative "document"
require_relative "target"
require_relative "observation"
require_relative "snapshot"

module CtxRunner
  # 离线证据的公共外壳；记录字段和领域语义交给消费模块校验。
  module Evidence
    VERSION = 3
    KINDS = %w[collection batch change_plan change execution review recommendations fabric_review].freeze

    def self.wrap(value, kind:)
      raise ArgumentError, "Unknown evidence kind" unless KINDS.include?(kind)
      Document.call(value).merge("schema_version" => VERSION, "kind" => kind.dup.freeze).freeze
    end

    # 旧报告和计划必须重新生成；拒绝以默认值猜测版本。
    def self.validate_version!(document, kind:)
      unless document.is_a?(Hash) && document["schema_version"] == VERSION && document["kind"] == kind
        raise ArgumentError, "Unsupported evidence format; regenerate reports and plans with schema version #{VERSION}"
      end
    end

    def self.plan(document, item:, platform:)
      validate_version!(document, kind: "change_plan")
      unless document["platform"] == platform && document["changes"].is_a?(Hash) && item.is_a?(String) &&
          item.match?(/\A[A-Za-z0-9_.-]+\z/) && document["changes"].key?(item)
        raise ArgumentError, "A supported plan and explicit --item are required"
      end
      selected = document["changes"].fetch(item)
      validate_version!(selected, kind: "change")
      raise ArgumentError, "Change platform differs from its plan" unless selected["platform"] == platform
      identity = Target.snapshot(selected.fetch("device"))
      host = identity.fetch(:host)
      unless !host.include?("/") && IPAddr.new(host).to_s == host &&
          selected["expected_config_sha256"].is_a?(String) && selected["expected_config_sha256"].match?(/\A[0-9a-f]{64}\z/)
        raise ArgumentError, "Invalid change target or configuration fingerprint"
      end
      Document.call(selected)
    end

    def self.validate(document, names:)
      validate_version!(document, kind: "collection")
      unless document.is_a?(Hash) && document["device"].is_a?(Hash) &&
          %w[name host].all? { |key| document["device"][key].is_a?(String) && !document["device"][key].empty? }
        raise ArgumentError, "Device identity is missing"
      end
      host = document["device"]["host"]
      Target.snapshot(document["device"])
      raise ArgumentError, "Target address must be a canonical host address" unless !host.include?("/") && IPAddr.new(host).to_s == host
      snapshot = document.fetch("snapshot")
      return if snapshot.nil?
      unless snapshot.is_a?(Hash) && snapshot["observations"].is_a?(Hash) &&
          %w[complete partial failed not_requested].include?(snapshot["collection_status"])
        raise ArgumentError, "Invalid snapshot structure"
      end
      if !snapshot["target"].is_a?(Hash) || snapshot["target"]["host"] != host
        raise ArgumentError, "Device identity does not match the collection target"
      end
      identity = Target.snapshot(snapshot["target"])
      %w[platform id].each do |field|
        if document["device"].key?(field) && snapshot["target"].key?(field) && document["device"][field] != snapshot["target"][field]
          raise ArgumentError, "Device identity does not match the collection target"
        end
      end
      observations = snapshot["observations"].to_h do |dimension, observation|
        unless names.map(&:to_s).include?(dimension) && observation.is_a?(Hash) &&
            Observation::STATUSES.map(&:to_s).include?(observation["status"]) && observation["name"] == dimension
          raise ArgumentError, "Invalid observation structure"
        end
        records = array(observation.fetch("records"))
        value = Observation.new(name: dimension.to_sym, status: observation["status"].to_sym, records: records,
          issues: array(observation.fetch("issues", [])), evidence: array(observation.fetch("evidence", [])).map { |entry| entry.transform_keys(&:to_sym) },
          covered_scopes: array(observation.fetch("covered_scopes", [])),
          started_at: observation["started_at"] && CtxParser::Values.timestamp(observation["started_at"]),
          completed_at: observation["completed_at"] && CtxParser::Values.timestamp(observation["completed_at"]))
        records.each { |record| yield(record, dimension) }
        [ dimension.to_sym, value ]
      end
      value = Snapshot.new(target: identity, observations: observations, names: names,
        observed_at: CtxParser::Values.timestamp(snapshot.fetch("observed_at")), issues: array(snapshot.fetch("issues", [])))
      unless value.collection_status.to_s == snapshot["collection_status"]
        raise ArgumentError, "Collection status differs from its evidence"
      end
    end

    def self.array(value)
      raise ArgumentError, "Expected a list of records" unless value.is_a?(Array) && value.all? { |entry| entry.is_a?(Hash) }
      value
    end

    def self.map(value)
      raise ArgumentError, "Expected a mapping of records" unless value.is_a?(Hash) && value.values.all? { |entry| entry.is_a?(Hash) }
      value
    end
  end
end
