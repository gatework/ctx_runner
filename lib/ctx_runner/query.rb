# frozen_string_literal: true

require "ctx_parser/immutable"
require "ctx_driver/failure"

module CtxRunner
  # 一条查询只读取解析一次；共享视图交付相同来源，失败不影响其他查询。
  class Query
    def initialize(reader:, parser:)
      @reader, @parser = reader, parser
    end

    # 不可用投影负责领域诊断结构；成功投影负责将事实与来源绑定。
    def read(command, names:, unavailable:)
      unless names.is_a?(Array) && names.any? && names.uniq == names && names.all? { |name| name.is_a?(Symbol) }
        raise ArgumentError, "Query views must be unique symbols"
      end
      names = CtxParser::Immutable.copy(names)
      command = CtxParser::Immutable.copy(command)
      capture = @reader.read(command)
      failure = capture.failure
      if capture.success?
        begin
          parsed = @parser.parse_many(names, capture.body, complete: true, command: command)
        rescue StandardError => error
          failure = CtxDriver::Failure.details(error, fallback: :command_processing_failed, stage: :parse)
        else
          return names.to_h do |name|
            value = begin
              yield(name, parsed.fetch(name), capture)
            rescue StandardError => error
              details = CtxDriver::Failure.details(error, fallback: :command_processing_failed, stage: :parse)
              unavailable.call(name, capture, details)
            end
            [ name, value ]
          end
        end
      end
      names.to_h { |name| [ name, unavailable.call(name, capture, failure) ] }
    end

    def inspect = "#<#{self.class.name}>"
  end
end
