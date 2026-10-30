# frozen_string_literal: true

require "ctx_driver"
require "ctx_driver/receipt"
require "ctx_parser/commands"
require_relative "document"

module CtxRunner
  # 借用领域已取得租约的会话；查询策略和配置解析器由领域显式注入。
  class ConfigurationSession
    def initialize(session:, preparation_commands:, configuration_command:, parser:, clock: -> { Time.now.utc })
      unless preparation_commands.is_a?(Array) && parser.respond_to?(:parse) && session.respond_to?(:write_command)
        raise ArgumentError, "Configuration session requires a writer and parser"
      end
      @preparation = preparation_commands.map { |command| CtxParser::Commands.command_text(command) }.freeze
      @command = CtxParser::Commands.command_text(configuration_command)
      @session, @parser = session, parser
      @reader = CtxDriver::Reader.new(session: session, clock: clock)
    end

    def read_configuration
      @preparation.each { |command| write(command) }
      capture = @reader.read(@command)
      raise IOError, "Configuration readback failed" unless capture.success?
      observation = @parser.parse(capture.body, complete: true)
      unless observation.complete? && observation.records.one?
        raise ArgumentError, "Configuration evidence is incomplete"
      end
      Document.call(observation.records.first)
    end

    def write(command)
      command = CtxParser::Commands.command_text(command).strip
      receipt = @session.write_command(command)
      raise IOError, "Device command is unconfirmed" unless CtxDriver::Receipt.validate(receipt, command: command)
      true
    end

    def inspect = "#<#{self.class.name}>"
    alias to_s inspect
    def pretty_print(printer) = printer.text(inspect)
  end
end
