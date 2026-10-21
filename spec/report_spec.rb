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
    expect(summary[:status]).to eq(:complete)
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
    expect(summary).to include(status: :incomplete, pending: [ result[:device] ])
  end

  it "gives presentation an immutable owned summary" do
    report = described_class.new(@root)
    original = result.merge(status: :failed)
    expect do
      report.finish([ original ]) { |summary| summary[:devices].first[:status] = :complete }
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
end
