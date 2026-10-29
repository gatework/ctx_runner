# frozen_string_literal: true

require "ctx_parser/immutable"
require "ctx_parser/values"
require "time"

module CtxRunner
  # 不可变的事实外壳；领域可继承外壳或复用校验，记录身份和业务字段仍由领域负责。
  class Observation < Data.define(:name, :status, :records, :issues, :evidence, :started_at, :completed_at, :covered_scopes)
    STATUSES = %i[complete partial failed unsupported not_requested not_applicable].freeze

    def self.validate(name:, status:, records:, issues:, evidence:, statuses: STATUSES)
      raise ArgumentError, "Observation name must be a symbol" unless name.is_a?(Symbol)
      raise ArgumentError, "Invalid observation status" unless statuses.include?(status)
      unless [ records, issues, evidence ].all? { |entries| entries.is_a?(Array) && entries.all? { |entry| entry.is_a?(Hash) } }
        raise ArgumentError, "Observation entries must be arrays of hashes"
      end
      if %i[failed unsupported not_requested not_applicable].include?(status) && records.any?
        raise ArgumentError, "Unavailable observations cannot contain records"
      end
    end

    def initialize(name:, status:, records: [], issues: [], evidence: [], started_at: nil, completed_at: nil, covered_scopes: [])
      self.class.validate(name: name, status: status, records: records, issues: issues, evidence: evidence)
      unless [ started_at, completed_at ].all? { |time| time.nil? || time.is_a?(Time) }
        raise ArgumentError, "Observation timestamps must be Time values or nil"
      end
      unless covered_scopes.is_a?(Array) && covered_scopes.all? { |scope| scope.is_a?(Hash) } && covered_scopes.uniq == covered_scopes &&
          (covered_scopes.empty? || %i[complete partial].include?(status))
        raise ArgumentError, "Covered scopes require available observations and unique hashes"
      end
      if status == :not_applicable && evidence.empty?
        raise ArgumentError, "Not applicable observations require evidence"
      end
      @observed_at = evidence.filter_map { |entry| CtxParser::Values.timestamp(entry[:observed_at]) if entry.key?(:observed_at) }.max
      super(name: name, status: status, records: CtxParser::Immutable.copy(records),
        issues: CtxParser::Immutable.copy(issues), evidence: CtxParser::Immutable.copy(evidence),
        started_at: started_at&.getutc&.freeze, completed_at: completed_at&.getutc&.freeze,
        covered_scopes: CtxParser::Immutable.copy(covered_scopes))
    end

    def complete? = status == :complete
    def partial? = status == :partial
    def available? = complete? || partial?
    # 来源采样时间不由较晚的快照或报告时间替代。
    attr_reader :observed_at
    def inspect = "#<#{self.class.name} name=#{name} status=#{status} records=#{records.size}>"
    alias to_s inspect
    def pretty_print(printer) = printer.text(inspect)
  end
end
