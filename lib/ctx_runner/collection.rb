# frozen_string_literal: true

require "ctx_driver/failure"

module CtxRunner
  # 约束一次连接器交付，不接管连接或操作租约；已取得的事实由领域块保留。
  class Collection
    attr_reader :failure, :stage

    def initialize(strict: false)
      raise ArgumentError, "Strict session contract must be boolean" unless [ true, false ].include?(strict)
      @strict, @used = strict, false
      @stage = :connect
    end

    # 准备阶段由领域计划显式声明，关闭阶段仅在采集块正常完成后进入。
    def stage=(value)
      raise ArgumentError, "Invalid collection stage" unless %i[connect prepare collect close].include?(value)
      @stage = value
    end

    def open(connector)
      raise ArgumentError, "Collection cannot be replayed" if @used
      raise ArgumentError, "Collection requires an operation" unless block_given?
      @used = true
      acquire(connector) { |session| yield session }
      self
    end

    def inspect = "#<#{self.class.name} stage=#{stage}>"

    private

    def acquire(connector)
      yielded = false
      active = true
      connector.open do |session|
        raise IOError, "Session provider scope has ended" unless active
        if yielded
          contract_failure(:session_reentered)
          next
        end
        yielded = true
        @stage = :collect
        yield session
        @stage = :close
      end
      contract_failure(:session_not_opened) unless yielded
    rescue StandardError => error
      raise unless CtxDriver::Failure.connection_error?(error, connector)
      details = CtxDriver::Failure.details(error, fallback: :connection_failed, stage: stage)
      @failure = (stage == :close ? details.merge(code: :session_close_failed) : details).freeze
    ensure
      active = false
    end

    def contract_failure(code)
      raise ArgumentError, "Connector must provide one session" if @strict
      @failure ||= { code: code, stage: stage }.freeze
    end
  end
end
