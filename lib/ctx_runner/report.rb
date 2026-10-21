# frozen_string_literal: true

require "json"
require "time"
require "tempfile"
require "fileutils"
require "ctx_parser/immutable"

module CtxRunner
  # 持有私有证据批次，统一检查点、发布和失败恢复；领域只提供展示内容。
  class Report
    attr_reader :directory

    # 仅交付发布阶段，不保留底层异常正文或敏感报告内容。
    class Error < IOError
      attr_reader :relative, :phase

      # 保留安全的发布阶段与提交状态，不携带底层异常正文。
      def initialize(relative:, phase:, committed:)
        @relative, @phase, @committed = relative.dup.freeze, phase, committed
        super("报告写入失败：#{relative}；阶段 #{phase}；#{committed ? '已替换，收尾未确认' : '尚未替换'}")
      end

      # 区分原子替换已完成与目录同步尚未确认。
      def committed? = @committed
    end

    # 批次目录排他创建，重复时间戳不会覆盖上一批次。
    def initialize(root, error_class: Error)
      raise ArgumentError, "Report error must inherit from Report::Error" unless error_class.is_a?(Class) && error_class <= Error
      @error_class = error_class
      root = File.expand_path(root)
      prepare_directory(root)
      stat = File.lstat(root)
      unless stat.directory? && (stat.mode & 0o077).zero?
        raise ArgumentError, "报告根目录须为真实私有目录，权限0700；请设置独立目录并检查 chmod 0700"
      end
      stem = Time.now.utc.strftime("%Y-%m-%d_%H-%M-%S")
      sequence = 0
      begin
        @directory = File.join(root, sequence.zero? ? stem : "#{stem}_#{sequence}").freeze
        Dir.mkdir(directory, 0o700)
      rescue Errno::EEXIST
        sequence += 1
        retry
      end
      sync_directory(root)
    end

    # 摘要不嵌入配置事实，只汇总状态与诊断，供终端和自动化共用。
    def finish(results, interrupted: false, requested: [], report_error: nil, execution_error: nil, output_error: nil, review: nil)
      raise ArgumentError, "Report requires a presentation block" unless block_given?
      @recovery_failed = false
      # 按地址索引一次，避免大批次逐个扫描所有已完成结果。
      completed_hosts = results.to_h { |result| [ result.fetch(:device).fetch("host"), true ] }
      pending = requested.reject { |device| completed_hosts.key?(device.fetch("host")) }
      complete = !report_error && !execution_error && !output_error && pending.empty? && results.any? && results.all? { |r| r[:status] == :complete && r[:report_saved] != false }
      summary = { status: interrupted ? :interrupted : (complete ? :complete : :incomplete),
        total: [ requested.size, results.size ].max, completed: results.size, pending: pending, counts: results.map { |r| r[:status] }.tally, devices: results,
        directory: directory, evidence_only: true }
      summary[:review] = review if review
      summary[:report_error] = report_error if report_error
      summary[:execution_error] = execution_error if execution_error
      summary[:output_error] = output_error if output_error
      summary = CtxParser::Immutable.copy(serializable(summary))
      # 先保存未完成检查点；文本发布或最终提交失败都不能留下成功摘要。
      checkpoint = summary.merge(status: interrupted ? :interrupted : :incomplete,
        report_error: report_error || :report_finalization_unconfirmed)
      checkpoint("summary.json", checkpoint)
      publish("summary.txt", yield(summary))
      finalize("summary.json", summary, checkpoint: checkpoint)
    end

    # 新一轮发布必须先撤销旧完成结论；非局部退出也不能绕过这条边界。
    def checkpoint(relative, value)
      relative = checked_relative(relative)
      validated = true
      published = false
      publish(relative, JSON.pretty_generate(serializable(value)) + "\n")
      published = true
    ensure
      invalidate_completed_summary(relative: relative) if validated && !published
    end

    # 领域报告正文完成后提交最终状态；取消和提交后失败共用恢复协议。
    def finalize(relative, summary, checkpoint:)
      relative = checked_relative(relative)
      summary = CtxParser::Immutable.copy(serializable(summary))
      checkpoint = CtxParser::Immutable.copy(serializable(checkpoint))
      checkpoint_body = JSON.pretty_generate(checkpoint) + "\n"
      finalized = false
      begin
        publish(relative, JSON.pretty_generate(serializable(summary)) + "\n")
        finalized = true
      rescue Error => error
        # 未替换时原检查点仍安全，不做可能破坏它的多余恢复写入。
        restore_checkpoint(checkpoint_body, relative: relative) if error.committed?
        finalized = true
        raise
      rescue Interrupt
        restore_checkpoint(JSON.pretty_generate(serializable(checkpoint.merge(status: :interrupted))) + "\n", relative: relative)
        finalized = true
        raise
      ensure
        # throw、线程终止等不经过 rescue；仍撤销尚未确认持久性的最终状态。
        restore_checkpoint(checkpoint_body, relative: relative) unless finalized
      end
      summary
    end

    # 每次发送配置前后发布检查点；失败由执行器停止后续写入。
    def write_execution(state)
      publish("execution.json", JSON.pretty_generate(state) + "\n")
    end

    # 恢复写入或删除受阻时，调用方须把退出码及此状态作为未确认诊断。
    def recovery_failed? = @recovery_failed == true

    # 新建目录的名字属于父目录；文件 fsync 不能替代这条持久化链。
    def prepare_directory(path)
      missing, parent = [], path
      until File.directory?(parent)
        missing << parent
        parent = File.dirname(parent)
      end
      FileUtils.mkdir_p(path, mode: 0o700)
      missing.reverse_each do |created|
        parent = File.dirname(created)
        sync_directory(File.symlink?(parent) ? File.realpath(parent) : parent)
      end
    end

    # 批次创建与文件发布共享目录同步边界，失败直接交还宿主停止执行。
    def sync_directory(path)
      File.open(path, File::RDONLY | File::NOFOLLOW) { |parent| parent.fsync }
    end

    # 新一次收尾失败时，旧成功摘要不再代表当前状态；安全检查点继续保留。
    def invalidate_completed_summary(relative: "summary.json")
      relative = checked_relative(relative)
      Thread.handle_interrupt(Exception => :never) do
        saved = JSON.parse(File.read(File.join(directory, relative)))
        discard_summary(relative: relative) if saved["status"] == "complete"
      end
    rescue Errno::ENOENT
      nil
    rescue SystemCallError, JSON::ParserError, Interrupt
      @recovery_failed = true
    end

    # 屏蔽恢复中的次级取消，始终把最先观察到的发布失败或取消交还调用方。
    def restore_checkpoint(body, relative: "summary.json")
      relative = checked_relative(relative)
      Thread.handle_interrupt(Exception => :never) do
        begin
          publish(relative, body)
        rescue Error, Interrupt => error
          @recovery_failed = true
          discard_summary(relative: relative) unless error.is_a?(Error) && error.committed?
        end
      end
    rescue Interrupt
      @recovery_failed = true
    end

    # 存储拒绝恢复时尽力移除不可信摘要，不删除已获得的设备事实。
    def discard_summary(relative: "summary.json")
      relative = checked_relative(relative)
      File.unlink(File.join(directory, relative))
    rescue Errno::ENOENT
      nil
    rescue SystemCallError
      @recovery_failed = true
    end

    # Time 使用 ISO-8601，递归转换 Data 只发生在显式持久化边界。
    def serializable(value)
      case value
      when Time then value.iso8601(6)
      when Data then serializable(value.to_h)
      when Hash then value.transform_values { |item| serializable(item) }
      when Array then value.map { |item| serializable(item) }
      else value
      end
    end

    # 临时文件与目标在同一目录，写入失败不发布半份报告。
    def publish(relative, body)
      relative = checked_relative(relative)
      target = File.join(directory, relative)
      phase, committed = :temporary_file, false
      Tempfile.create([ ".ctx-runner-", ".tmp" ], File.dirname(target)) do |file|
        file.chmod(0o600)
        phase = :write
        file.write(body)
        phase = :file_sync
        file.flush
        file.fsync
        phase = :rename
        File.rename(file.path, target)
        committed = true
        phase = :directory_sync
        sync_directory(File.dirname(target))
        phase = :cleanup
      end
    rescue SystemCallError, IOError, NotImplementedError
      raise @error_class.new(relative: relative, phase: phase, committed: committed), cause: nil
    end
    private

    # 发布、恢复与删除使用同一条路径契约；拒绝路径时不能执行收尾副作用。
    def checked_relative(relative)
      unless relative.is_a?(String) && !relative.empty? && !relative.start_with?("/") &&
          relative.split("/", -1).none? { |part| [ "", ".", ".." ].include?(part) } && !relative.include?("\0")
        raise ArgumentError, "Report path must remain inside the batch"
      end
      relative.dup.freeze
    end
  end
end
