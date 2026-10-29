# frozen_string_literal: true

require_relative "target"
require_relative "observation"
require_relative "document"

module CtxRunner
  # 领域组合公共快照；采集结论与领域健康、报告持久性分别表达。
  class Snapshot
    include Document::Value
    attr_reader :target, :observations, :observed_at, :issues, :collection_status

    def initialize(target:, observations:, observed_at:, names:, issues: [])
      unless names.is_a?(Array) && names.all? { |name| name.is_a?(Symbol) } && names.uniq == names
        raise ArgumentError, "Snapshot dimensions must be unique symbols"
      end
      unless observations.is_a?(Hash) && observations.all? do |name, value|
          names.include?(name) && %i[name status records issues evidence covered_scopes started_at completed_at complete? to_h].all? { |method| value.respond_to?(method) } && value.name == name && Observation::STATUSES.include?(value.status) && value.frozen?
        end
        raise ArgumentError, "Snapshot observations must match declared dimensions"
      end
      raise ArgumentError, "Snapshot time must be a Time" unless observed_at.is_a?(Time)
      unless issues.is_a?(Array) && issues.all? { |issue| issue.is_a?(Hash) }
        raise ArgumentError, "Snapshot issues must be hashes"
      end
      @target = Target.snapshot(target)
      @names = names.dup.freeze
      @observations = observations.to_h { |name, value| [ name, value ] }.freeze
      @observed_at = observed_at.getutc.freeze
      @issues = CtxParser::Immutable.copy(issues)
      @collection_status = aggregate
      freeze
    end

    def observation(name)
      raise ArgumentError, "Unknown observation dimension" unless @names.include?(name)
      observations.fetch(name) { Observation.new(name: name, status: :not_requested) }
    end

    def complete? = collection_status == :complete
    def same_target?(other) = other.respond_to?(:target) && %i[host platform id].all? { |key| target[key] == other.target[key] }

    def to_h
      { target: target, observations: observations.transform_values(&:to_h), observed_at: observed_at,
        issues: issues, collection_status: collection_status }
    end

    def inspect = "#<#{self.class.name} collection_status=#{collection_status}>"
    alias to_s inspect
    def pretty_print(printer) = printer.text(inspect)

    private

    # 不适用必须已有来源证据；空请求不通过 all? 被提升为完整。
    def aggregate
      selected = observations.values.reject { |observation| observation.status == :not_requested }
      return issues.empty? ? :not_requested : :failed if selected.empty?
      conclusive = selected.select do |observation|
        %i[complete partial].include?(observation.status) || observation.status == :not_applicable && observation.evidence.any?
      end
      return :failed if conclusive.empty?
      return :complete if issues.empty? && conclusive.size == selected.size && selected.none? { |observation| observation.status == :partial }
      :partial
    end
  end
end
