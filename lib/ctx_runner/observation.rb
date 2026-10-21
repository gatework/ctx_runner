# frozen_string_literal: true

require "ctx_parser/immutable"

module CtxRunner
  # 不可变的事实外壳；领域可继承外壳或复用校验，记录身份和业务字段仍由领域负责。
  class Observation < Data.define(:name, :status, :records, :issues, :evidence, :started_at, :completed_at)
    STATUSES = %i[complete partial failed unsupported not_requested].freeze

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

    def initialize(name:, status:, records: [], issues: [], evidence: [], started_at: nil, completed_at: nil)
      self.class.validate(name: name, status: status, records: records, issues: issues, evidence: evidence)
      unless [ started_at, completed_at ].all? { |time| time.nil? || time.is_a?(Time) }
        raise ArgumentError, "Observation timestamps must be Time values or nil"
      end
      super(name: name, status: status, records: CtxParser::Immutable.copy(records),
        issues: CtxParser::Immutable.copy(issues), evidence: CtxParser::Immutable.copy(evidence),
        started_at: started_at&.dup&.freeze, completed_at: completed_at&.dup&.freeze)
    end

    def complete? = status == :complete
    def partial? = status == :partial
    def available? = complete? || partial?
    def inspect = "#<#{self.class.name} name=#{name} status=#{status} records=#{records.size}>"
    alias to_s inspect
    def pretty_print(printer) = printer.text(inspect)
  end
end
