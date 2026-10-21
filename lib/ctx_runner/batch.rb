# frozen_string_literal: true

require "ctx_parser/immutable"
require "ctx_driver/failure"

module CtxRunner
  # 批量采集的交付账本；调度器负责并发与回收，领域块只返回设备快照。
  class Batch
    Completion = Data.define(:status, :summary, :failure, :finalization_error, :recovery_failed) do
      def initialize(**attributes)
        super(**CtxParser::Immutable.copy(attributes))
      end

      def inspect = "#<#{self.class.name} status=#{status}>"
      alias to_s inspect
      def pretty_print(printer) = printer.text(inspect)
    end

    # 块拥有调度及回收；返回后统一交付，取消优先于收尾失败。
    def run(present: nil)
      raise ArgumentError, "Batch cannot be replayed" if @running
      raise ArgumentError, "Batch requires an operation" unless block_given?
      @running = entered = true
      options = { interrupted: false, report_error: nil, execution_error: nil }
      failure = nil
      begin
        yield
      rescue Interrupt
        options[:interrupted] = true
      rescue StandardError, LoadError => error
        failure = classify(error)
        options[failure[:kind] == :report ? :report_error : :execution_error] = failure[:detail]
      end
      @closed = true
      settling = true
      summary, finalization_error = settle(options)
      if summary && present
        presenting = true
        begin
          present.call(summary)
        rescue Interrupt
          options[:interrupted] = true
          summary, finalization_error = settle(options)
        rescue StandardError, LoadError => error
          failure ||= classify(error)
          options[:report_error] = diagnostic(error)
          summary, finalization_error = settle(options)
        end
      end
      presenting = false
      status = if options[:interrupted]
        :interrupted
      elsif failure || finalization_error
        :failed
      else
        summary[:status] == :complete ? :complete : :incomplete
      end
      completion = Completion.new(status: status, summary: summary, failure: failure, finalization_error: finalization_error,
        recovery_failed: @report.respond_to?(:recovery_failed?) && @report.recovery_failed?)
      completed = true
      completion
    ensure
      @closed = true if entered
      # throw/非局部 return 也要收尾，但绝不覆盖原退出或再次展示。
      if entered && !completed && (!settling || presenting)
        begin
          finish(interrupted: true)
        rescue StandardError, LoadError, Interrupt
          nil
        end
      end
    end

    def initialize(report:, progress:, requested:)
      @requested = CtxParser::Immutable.copy(requested)
      @report, @progress = report, progress
      @results, @lock = [], Mutex.new
    end

    # 先登记设备事实，再保存报告；报告失败仍可在最终摘要中定位未交付结果。
    def collect(device)
      raise ArgumentError, "Batch is closed" if @closed
      device = CtxParser::Immutable.copy(device)
      started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      @progress.start(device)
      snapshot = nil
      begin
        snapshot = yield
        dimensions = snapshot.dimensions.transform_values do |value|
          { status: value.status, records: value.records.size, issues: value.issues.map { |issue| issue[:code] }.uniq }
        end
        result = { device: device, status: snapshot.dimensions.fetch(:collection).status, dimensions: dimensions }
      rescue StandardError => error
        result = { device: device, status: :failed, error: CtxDriver::Failure.code(error, :collection_failed), dimensions: {} }
      end
      result[:duration_ms] = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - started) * 1000).round
      result[:report_saved] = false
      @lock.synchronize { @results << result }
      @report.write(CtxParser::Immutable.copy(result), snapshot: snapshot)
      @lock.synchronize { result[:report_saved] = true }
      saved = CtxParser::Immutable.copy(result)
      @progress.result(saved)
      saved
    end

    def results
      @lock.synchronize { CtxParser::Immutable.copy(@results).sort_by { |result| result[:device].fetch("host") }.freeze }
    end

    # 调度器回收后调用；输出诊断只补写报告，绝不重新执行设备操作。
    def finish(interrupted: false, report_error: nil, execution_error: nil)
      snapshot = results
      options = { interrupted: interrupted, requested: @requested, report_error: report_error, execution_error: execution_error }
      summary = @report.finish(snapshot, **options, output_error: @progress.output_error)
      @progress.finish(summary)
      if @progress.output_error && !summary[:output_error]
        summary = @report.finish(snapshot, **options, output_error: @progress.output_error)
      end
      summary
    end

    def inspect = "#<#{self.class.name}>"

    private

    def settle(options)
      [ CtxParser::Immutable.copy(finish(**options)), nil ]
    rescue Interrupt
      options[:interrupted] = true
      begin
        [ CtxParser::Immutable.copy(finish(**options)), nil ]
      rescue StandardError, LoadError, Interrupt => error
        [ nil, diagnostic(error) ]
      end
    rescue StandardError, LoadError => error
      [ nil, diagnostic(error) ]
    end

    def classify(error)
      kind = error.is_a?(SystemCallError) || error.is_a?(IOError) ? :report : :execution
      { kind: kind, error_type: error.class.name, detail: kind == :report ? diagnostic(error) : error.class.name }.freeze
    end

    def diagnostic(error)
      type = @report.class.const_get(:Error) if @report.class.const_defined?(:Error)
      type && error.instance_of?(type) ? error.message : error.class.name
    end
  end
end
