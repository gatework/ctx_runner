# frozen_string_literal: true

require "ctx_runner"
require "tmpdir"

# 离线证据发布；临时目录由示例拥有，不接触设备或宿主配置。
Dir.mktmpdir do |root|
  report = CtxRunner::Report.new(File.join(root, "reports"))
  report.publish("evidence.json", JSON.generate(source: "synthetic", records: []))
  device = { "host" => "192.0.2.1", "name" => "example" }
  summary = report.finish([ { device: device, status: :complete, report_saved: true } ], requested: [ device ]) do |value|
    "Evidence: #{value.fetch('status')}; health was not evaluated.\n"
  end
  raise "Report incomplete" unless summary.fetch("status") == "complete"
  raise "Missing evidence" unless File.file?(File.join(report.directory, "evidence.json"))
end
