# frozen_string_literal: true

require "ctx_parser/immutable"
require "ctx_parser/commands"
require "ctx_driver/failure"
require_relative "fingerprint"
require_relative "session_scope"
require_relative "evidence"

module CtxRunner
  # 只执行已确认的单项领域变更；日志、设备效果与配置验收分别记账。
  class Execution
    # 领域动作负责有限命令及前后置条件；日志接收独立的不可变检查点。
    def initialize(plan:, change:, journal:, plan_sha256:, item: nil)
      @plan = CtxParser::Immutable.copy(plan)
      unless @plan.is_a?(Hash) && @plan["target"].is_a?(Hash) &&
          [ @plan["expected_config_sha256"], plan_sha256 ].all? { |value| value.is_a?(String) && /\A[0-9a-f]{64}\z/.match?(value) }
        raise ArgumentError, "Execution requires a verified plan and fingerprints"
      end
      unless %i[commands eligible? satisfied?].all? { |method| change.respond_to?(method) } && journal.respond_to?(:write_execution)
        raise ArgumentError, "Execution requires a typed change and journal"
      end
      @commands = CtxParser::Immutable.copy(change.commands)
      unless @commands.is_a?(Array) && @commands.any?
        raise ArgumentError, "Change commands must be individual lines"
      end
      @commands.each { |command| CtxParser::Commands.command_text(command) }
      @change, @journal = change, journal
      @state = { "schema_version" => Evidence::VERSION, "kind" => "execution", "status" => "confirmed", "target" => @plan["target"], "plan_sha256" => plan_sha256.dup.freeze,
        "expected_config_sha256" => @plan["expected_config_sha256"], "commands" => @commands, "steps" => [] }
      @state["plan_item"] = CtxParser::Immutable.copy(item) if item
      @started = @used = @journal_failed = false
    end

    # 由连接器提供唯一会话并清理；关闭失败同样不能发布配置已验证状态。
    def run
      raise ArgumentError, "Execution cannot be replayed" if @used
      raise ArgumentError, "Execution requires a session provider" unless block_given?
      @used = true
      perform { |operation| yield operation }
    end

    def started? = @started
    def journal_failed? = @journal_failed
    def state = CtxParser::Immutable.copy(@state)
    def inspect = "#<#{self.class.name} status=#{@state.fetch('status')}>"

    private

    # 保存意图先于连接；回调次数和完成状态不依赖连接器返回值。
    def perform
      finished = recorded = false
      scope = SessionScope.new
      save
      yield lambda { |session|
        delivered = scope.deliver do
          before = CtxParser::Immutable.copy(session.read_configuration)
          unless Fingerprint.call(before) == @plan["expected_config_sha256"] && @change.eligible?(before)
            raise ArgumentError, "Configuration changed or preconditions failed"
          end
          @commands.each_with_index { |command, index| execute(session, command, index) }
          after = CtxParser::Immutable.copy(session.read_configuration)
          raise IOError, "Configuration verification failed" unless @change.satisfied?(after, before: before)
          @state["observed_config_sha256"] = Fingerprint.call(after)
        end
        raise IOError, "Invalid session delivery" unless delivered
      }
      scope.close
      raise IOError, "Session did not verify the configuration" if scope.failure
      @state["status"] = "configuration_verified"
      save
      finished = true
      state
    rescue StandardError, Interrupt => error
      recorded = true
      type = error.is_a?(Interrupt) ? "interrupted" : CtxDriver::Failure.details(error, fallback: :execution_failed, stage: :execute).fetch(:error_type)
      record_failure(type)
      raise
    ensure
      scope&.close
      # 非局部退出与线程取消也不能留下可重放的成功意图。
      record_failure("aborted") unless finished || recorded
    end

    # 发送前记录未决命令；已执行事实在发送后的日志失败时继续保留。
    def execute(session, command, index)
      @state["status"] = "executing"
      @state["pending_command"] = index
      save
      @started = true
      raise IOError, "Command was not acknowledged" unless session.write(command) == true
      @state["steps"] << { "index" => index, "status" => "acknowledged" }
      @state.delete("pending_command")
      save
    end

    def save = @journal.write_execution(state)

    # 次级日志故障不覆盖主异常，也不允许继续发送命令。
    def record_failure(code)
      @state["status"] = started? ? "uncertain" : "failed"
      @state["error"] = code
      save
    rescue StandardError, Interrupt
      @journal_failed = true
    end
  end
end
