# frozen_string_literal: true

require "ctx_runner"
require "tmpdir"

# 合成领域动作，只演示前提、执行记账与回读验收；没有设备连接。
class ExampleChange
  def commands = [ "set mode enabled" ].freeze
  def eligible?(config) = config["mode"] == "disabled"
  def satisfied?(config, before:) = before["mode"] == "disabled" && config["mode"] == "enabled"
end

class ExampleSession
  def initialize = @mode = "disabled"
  def read_configuration = { "mode" => @mode }
  def write(command)
    raise "Unexpected command" unless command == "set mode enabled"
    @mode = "enabled"
    true
  end
end

Dir.mktmpdir do |root|
  report = CtxRunner::Report.new(File.join(root, "execution"))
  plan = { "target" => { "host" => "192.0.2.1" }, "expected_config_sha256" => CtxRunner::Fingerprint.call("mode" => "disabled") }
  execution = CtxRunner::Execution.new(plan: plan, change: ExampleChange.new, journal: report, plan_sha256: "a" * 64)
  result = execution.run { |operation| operation.call(ExampleSession.new) }
  raise "Unverified configuration" unless result["status"] == "configuration_verified"
  raise "Lost command evidence" unless result["steps"].one?
end
