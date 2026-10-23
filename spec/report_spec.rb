# frozen_string_literal: true

require_relative "spec_helper"
require "ctx_runner/report"
require "tmpdir"

RSpec.describe CtxRunner::Report do
  around do |example|
    Dir.mktmpdir do |directory|
      @root = File.join(directory, "reports")
      example.run
    end
  end

  let(:result) { { device: { "host" => "192.0.2.1", "name" => "device" }, status: :complete, report_saved: true } }

  it "publishes private evidence before completing the batch" do
    report = described_class.new(@root)
    report.publish("evidence.json", "{}\n")
    summary = report.finish([ result ], requested: [ result[:device] ]) { "Evidence only\n" }
    expect(summary.fetch("status")).to eq("complete")
    expect(JSON.parse(File.read(File.join(report.directory, "summary.json")))["status"]).to eq("complete")
    expect(File.stat(report.directory).mode & 0o777).to eq(0o700)
    expect(File.stat(File.join(report.directory, "evidence.json")).mode & 0o777).to eq(0o600)
  end

  it "keeps a safe checkpoint if domain rendering fails" do
    report = described_class.new(@root)
    expect { report.finish([ result ]) { raise ArgumentError, "render failed" } }.to raise_error(ArgumentError)
    saved = JSON.parse(File.read(File.join(report.directory, "summary.json")))
    expect(saved).to include("status" => "incomplete", "report_error" => "report_finalization_unconfirmed")
  end

  it "retains pending targets and never completes an empty batch" do
    report = described_class.new(@root)
    summary = report.finish([], requested: [ result[:device] ]) { "pending" }
    expect(summary).to include("status" => "incomplete", "pending" => [ result[:device] ])
  end

  it "gives presentation an immutable owned summary" do
    report = described_class.new(@root)
    original = result.merge(status: :failed)
    expect do
      report.finish([ original ]) { |summary| summary.fetch("devices").first["status"] = "complete" }
    end.to raise_error(FrozenError)
    expect(original[:status]).to eq(:failed)
    saved = JSON.parse(File.read(File.join(report.directory, "summary.json")))
    expect(saved["status"]).to eq("incomplete")
  end

  it "restores a checkpoint on nonlocal cancellation after final replacement" do
    report = described_class.new(@root)
    allow(report).to receive(:sync_directory).and_wrap_original do |original, path|
      file = File.join(report.directory, "summary.json")
      throw :cancel if File.file?(file) && JSON.parse(File.read(file))["status"] == "complete"
      original.call(path)
    end
    catch(:cancel) { report.finish([ result ]) { "text" } }
    expect(JSON.parse(File.read(File.join(report.directory, "summary.json")))["status"]).to eq("incomplete")
  end

  it "invalidates old success on nonlocal cancellation before a replacement checkpoint" do
    report = described_class.new(@root)
    report.finish([ result ]) { "text" }
    allow(report).to receive(:publish) { throw :cancel }
    catch(:cancel) { report.finish([ result ], output_error: { error_type: "IOError" }) { "text" } }
    expect(File).not_to exist(File.join(report.directory, "summary.json"))
  end

  it "rejects publication outside its owned batch" do
    report = described_class.new(@root)
    expect { report.publish("../escaped", "private") }.to raise_error(ArgumentError)
    expect(File).not_to exist(File.join(@root, "escaped"))
  end

  it "does not delete outside files when a checkpoint path is rejected" do
    report = described_class.new(@root)
    outside = File.join(@root, "outside.json")
    File.write(outside, '{"status":"complete"}')
    expect { report.checkpoint("../outside.json", {}) }.to raise_error(ArgumentError)
    expect(File.read(outside)).to eq('{"status":"complete"}')
  end

  it "preserves cancellation after a final rename even if recovery fails" do
    report = described_class.new(@root)
    original = File.method(:rename)
    cancellation = Interrupt.new("cancelled")
    attempts = 0
    allow(File).to receive(:rename) do |source, target|
      attempts += 1 if target.end_with?("/summary.json")
      raise Errno::ENOSPC if attempts >= 3
      original.call(source, target)
      raise cancellation if target.end_with?("/summary.json") && attempts == 2
    end
    expect { report.finish([ result ]) { "summary" } }.to raise_error { |error| expect(error).to equal(cancellation) }
    expect(report).to be_recovery_failed
    expect(File).not_to exist(File.join(report.directory, "summary.json"))
  end

  it "shares one immutable JSON document across presentation, return and persistence" do
    report = described_class.new(@root)
    original = result.merge(observation: Data.define(:time, :state).new(Time.utc(2026, 10, 23), :complete))
    seen = nil
    summary = report.finish([ original ]) do |document|
      seen = document
      original[:device]["host"] = "changed"
      original[:status] = :failed
      "#{document.fetch('devices').first.fetch('device').fetch('host')} #{document.fetch('status')}"
    end
    expect(summary).to equal(seen)
    expect(summary).to eq(JSON.parse(File.read(File.join(report.directory, "summary.json"))))
    expect(summary.fetch("devices").first).to include("status" => "complete",
      "observation" => { "time" => "2026-10-23T00:00:00.000000Z", "state" => "complete" })
    expect(File.read(File.join(report.directory, "summary.txt"))).to eq("192.0.2.1 complete")
    expect { summary.fetch("devices").first.fetch("device")["host"].replace("mutated") }.to raise_error(FrozenError)
    expect(original[:device]["host"]).to eq("changed")
  end

  {
    "cyclic values" => -> { value = []; value << value },
    "colliding keys" => -> { { status: :incomplete, "status" => "complete" } },
    "opaque values" => -> { Object.new },
    "non-finite numbers" => -> { Float::INFINITY },
    "excessive nesting" => -> { 129.times.reduce(nil) { |value, _| [ value ] } }
  }.each do |name, input|
    it "rejects #{name} before checkpoint publication and withdraws old success" do
      report = described_class.new(@root)
      report.finish([ result ]) { "text" }
      expect { report.checkpoint("summary.json", { status: :incomplete, evidence: input.call }) }.to raise_error(ArgumentError)
      expect(File).not_to exist(File.join(report.directory, "summary.json"))
      expect(File).to exist(File.join(report.directory, "summary.txt"))
    end
  end

  it "withdraws old completion when building a new batch document fails" do
    report = described_class.new(@root)
    report.finish([ result ]) { "text" }
    cycle = []; cycle << cycle
    expect { report.finish([ result ], review: cycle) { raise "must not render" } }.to raise_error(ArgumentError)
    expect(File).not_to exist(File.join(report.directory, "summary.json"))
  end

  it "withdraws old completion when encoding a checkpoint fails" do
    report = described_class.new(@root)
    report.finish([ result ]) { "text" }
    expect { report.checkpoint("summary.json", status: :incomplete, evidence: "\xff".b) }.to raise_error(JSON::GeneratorError)
    expect(File).not_to exist(File.join(report.directory, "summary.json"))
  end

  it "withdraws old completion on a nonlocal exit during document conversion" do
    record = Class.new(Data.define(:value)) do
      def to_h = throw(:cancel, :stopped)
    end.new(1)
    report = described_class.new(@root)
    report.finish([ result ]) { "text" }
    expect(catch(:cancel) { report.finish([ result ], review: record) { "text" } }).to eq(:stopped)
    expect(File).not_to exist(File.join(report.directory, "summary.json"))
  end

  it "preserves an existing incomplete checkpoint when new input is invalid" do
    report = described_class.new(@root)
    report.checkpoint("summary.json", status: :incomplete, completed: 1)
    previous = File.binread(File.join(report.directory, "summary.json"))
    expect { report.checkpoint("summary.json", status: :incomplete, evidence: Object.new) }.to raise_error(ArgumentError)
    expect(File.binread(File.join(report.directory, "summary.json"))).to eq(previous)
  end

  it "rejects completion as a checkpoint and withdraws old success" do
    report = described_class.new(@root)
    report.finish([ result ]) { "text" }
    expect { report.checkpoint("summary.json", status: :complete) }.to raise_error(ArgumentError)
    expect(File).not_to exist(File.join(report.directory, "summary.json"))
  end

  it "validates both finalize documents before replacing the existing checkpoint" do
    report = described_class.new(@root)
    report.checkpoint("review.json", status: :incomplete, evidence: [ "retained" ])
    path = File.join(report.directory, "review.json")
    previous = File.binread(path)
    [ [ { status: :complete, evidence: Object.new }, { status: :incomplete } ],
      [ { status: :complete }, { status: :complete } ],
      [ { status: :complete }, { status: :incomplete, "status" => "complete" } ] ].each do |summary, checkpoint|
      expect { report.finalize("review.json", summary, checkpoint: checkpoint) }.to raise_error(ArgumentError)
      expect(File.binread(path)).to eq(previous)
    end
  end

  it "withdraws old completion if finalize validation fails" do
    report = described_class.new(@root)
    report.finish([ result ]) { "text" }
    expect { report.finalize("summary.json", { status: :complete, evidence: Object.new }, checkpoint: { status: :incomplete }) }.to raise_error(ArgumentError)
    expect(File).not_to exist(File.join(report.directory, "summary.json"))
  end

  it "restores a normalized interrupted document after final replacement is cancelled" do
    report = described_class.new(@root)
    report.checkpoint("review.json", status: :incomplete, evidence: [ "retained" ])
    allow(report).to receive(:sync_directory).and_wrap_original do |original, path|
      saved = JSON.parse(File.read(File.join(report.directory, "review.json")))
      raise Interrupt if saved["status"] == "complete"
      original.call(path)
    end
    expect { report.finalize("review.json", { "status" => "complete" }, checkpoint: { "status" => "incomplete", "evidence" => [ "retained" ] }) }.to raise_error(Interrupt)
    expect(JSON.parse(File.read(File.join(report.directory, "review.json"))))
      .to eq("status" => "interrupted", "evidence" => [ "retained" ])
    expect(report).not_to be_recovery_failed
  end

  it "encodes documents within the evidence depth budget" do
    report = described_class.new(@root)
    evidence = 120.times.reduce("retained") { |value, _| [ value ] }
    report.checkpoint("summary.json", status: :incomplete, evidence: evidence)
    saved = JSON.parse(File.read(File.join(report.directory, "summary.json")), max_nesting: false)
    expect(saved.fetch("evidence").flatten).to eq([ "retained" ])
    report.finalize("summary.json", { status: :complete, evidence: evidence }, checkpoint: saved)
    expect { report.checkpoint("summary.json", status: :incomplete, evidence: Object.new) }.to raise_error(ArgumentError)
    expect(File).not_to exist(File.join(report.directory, "summary.json"))
    expect(report).not_to be_recovery_failed
  end

  it "reports unconfirmed removal durability without replacing the input failure" do
    report = described_class.new(@root)
    report.finish([ result ]) { "text" }
    allow(report).to receive(:sync_directory).and_raise(Errno::EIO)
    expect { report.checkpoint("summary.json", status: :incomplete, evidence: Object.new) }.to raise_error(ArgumentError)
    expect(File).not_to exist(File.join(report.directory, "summary.json"))
    expect(report).to be_recovery_failed
  end

  it "validates execution documents without publishing opaque evidence" do
    report = described_class.new(@root)
    expect { report.write_execution(status: :executing, evidence: Object.new) }.to raise_error(ArgumentError)
    expect(File).not_to exist(File.join(report.directory, "execution.json"))
    report.write_execution(status: :executing, time: Time.utc(2026, 10, 23))
    expect(JSON.parse(File.read(File.join(report.directory, "execution.json"))))
      .to eq("status" => "executing", "time" => "2026-10-23T00:00:00.000000Z")
  end
end
