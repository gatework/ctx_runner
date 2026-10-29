# frozen_string_literal: true

require "ctx_driver/failure"
require_relative "session_scope"

module CtxRunner
  # 约束一次连接器交付，不接管连接或操作租约；已取得的事实由领域块保留。
  class Collection
    attr_reader :failure, :stage

    def initialize
      @used = false
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
      scope = SessionScope.new
      connector.open do |session|
        delivered = scope.deliver do
          @stage = :collect
          yield session
          @stage = :close
        end
        contract_failure(scope.failure) unless delivered
      end
      scope.close
      contract_failure(scope.failure) if scope.failure
    rescue StandardError => error
      raise unless CtxDriver::Failure.connection_error?(error, connector)
      contract_failure(scope.failure) if scope&.failure && stage != :connect
      details = CtxDriver::Failure.details(error, fallback: :connection_failed, stage: stage)
      @failure ||= (stage == :close ? details.merge(code: :session_close_failed) : details).freeze
    ensure
      scope&.close
    end

    def contract_failure(code)
      @failure ||= { code: code, stage: stage }.freeze
    end
  end
end
