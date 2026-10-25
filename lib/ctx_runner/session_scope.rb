# frozen_string_literal: true

module CtxRunner
  # 连接所有者只在当前线程、当前作用域内交付一次借用会话；不持有或关闭会话。
  class SessionScope
    def initialize
      @owner, @lock = Thread.current, Mutex.new
      @active, @delivered, @completed = true, false, false
    end

    # 先占用交付资格再调用领域代码；失败或重复交付不能因外部 rescue 变为成功。
    def deliver
      raise ArgumentError, "Session delivery requires an operation" unless block_given?
      accepted = @lock.synchronize do
        raise IOError, "Session provider scope has ended" unless @active
        if @violation
          false
        elsif Thread.current != @owner
          @violation ||= :session_out_of_scope
          false
        elsif @delivered
          @violation ||= :session_reentered
          false
        else
          @delivered = true
        end
      end
      return false unless accepted

      yield
      @lock.synchronize { @completed = true }
      true
    end

    def failure
      @lock.synchronize do
        @violation || (!@delivered ? :session_not_opened : !@completed ? :session_incomplete : nil)
      end
    end

    def close
      @lock.synchronize { @active = false }
      nil
    end

    def inspect = "#<#{self.class.name}>"
    alias to_s inspect
    def pretty_print(printer) = printer.text(inspect)
  end
end
