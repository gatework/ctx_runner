# frozen_string_literal: true

require_relative "spec_helper"
require "ctx_runner/batch"

RSpec.describe CtxRunner::Batch do
  let(:device) { { "host" => "192.0.2.1" } }
  let(:report) { double(write: nil, finish: { "status" => "complete" }) }
  let(:progress) { double(start: nil, result: nil, finish: nil, output_error: nil) }
  let(:batch) { described_class.new(report: report, progress: progress, requested: [ device ]) }

  it "retains collected facts when evidence publication fails" do
    allow(report).to receive(:write).and_raise(IOError)
    observation = Struct.new(:status, :records, :issues).new(:complete, [ { name: "test" } ], [])
    snapshot = Struct.new(:dimensions).new({ collection: observation, interfaces: observation })
    expect { batch.collect(device) { snapshot } }.to raise_error(IOError)
    expect(batch.results).to contain_exactly(include(device: device, status: :complete, report_saved: false,
      dimensions: { collection: { status: :complete, records: 1, issues: [] }, interfaces: { status: :complete, records: 1, issues: [] } }))
  end

  it "isolates a device failure and reports a saved result" do
    delivered = nil
    allow(progress).to receive(:result) { |document| delivered = document }
    result = batch.collect(device) { raise ArgumentError, "private" }
    expect(result).to include(status: :failed, error: :collection_failed, report_saved: true)
    expect(result.to_s).not_to include("private")
    expect(delivered).to include("device" => { "host" => "192.0.2.1" }, "status" => "failed",
      "error" => "collection_failed", "report_saved" => true)
    expect { delivered.fetch("device")["host"] = "changed" }.to raise_error(FrozenError)
  end

  it "updates final output failures without repeating collection" do
    batch.collect(device) { nil }
    allow(progress).to receive(:finish) { allow(progress).to receive(:output_error).and_return(error_type: "IOError") }
    expect(report).to receive(:finish).with(anything, hash_including(output_error: nil)).and_return("status" => "complete")
    expect(report).to receive(:finish).with(anything, hash_including(output_error: { error_type: "IOError" })).and_return("status" => "incomplete")
    expect(batch.finish.fetch("status")).to eq("incomplete")
    expect(batch.results.size).to eq(1)
  end
  it "keeps cancellation authoritative when finalization fails" do
    allow(report).to receive(:finish).and_raise(IOError, "private")
    allow(report).to receive(:recovery_failed?).and_return(true)
    outcome = batch.run { raise Interrupt }
    expect(outcome.status).to eq(:interrupted)
    expect(outcome.finalization_error).to eq("IOError")
    expect(outcome.recovery_failed).to be(true)
    expect(outcome.inspect).not_to include("private")
  end

  it "retains an execution failure without replaying the operation" do
    calls = 0
    expect(report).to receive(:finish).with(anything, hash_including(execution_error: "ArgumentError")).and_return("status" => "incomplete")
    outcome = batch.run do
      calls += 1
      raise ArgumentError, "private"
    end
    expect(outcome.status).to eq(:failed)
    expect(outcome.failure).to eq(kind: :execution, error_type: "ArgumentError", detail: "ArgumentError")
    expect(calls).to eq(1)
    expect { batch.run { calls += 1 } }.to raise_error(ArgumentError)
    expect(calls).to eq(1)
  end

  it "records a presentation failure without collecting or presenting again" do
    calls = 0
    expect(report).to receive(:finish).ordered.and_return("status" => "complete")
    expect(report).to receive(:finish).with(anything, hash_including(report_error: "IOError")).ordered.and_return("status" => "incomplete")
    outcome = batch.run(present: ->(_) { raise IOError, "private" }) { calls += 1 }
    expect(outcome.status).to eq(:failed)
    expect(outcome.summary).to eq("status" => "incomplete")
    expect(calls).to eq(1)
  end

  it "finalizes an abandoned operation while preserving its nonlocal exit" do
    expect(report).to receive(:finish).with(anything, hash_including(interrupted: true)).and_return("status" => "interrupted")
    expect(catch(:cancel) { batch.run { throw :cancel, :stopped } }).to eq(:stopped)
  end

  it "closes registration before final presentation and after completion" do
    batch.run(present: ->(_) { expect { batch.collect(device) { raise "must not execute" } }.to raise_error(ArgumentError) }) { }
    expect { batch.collect(device) { raise "must not execute" } }.to raise_error(ArgumentError)
  end

  it "withdraws completion if presentation abandons the run" do
    expect(report).to receive(:finish).ordered.and_return("status" => "complete")
    expect(report).to receive(:finish).with(anything, hash_including(interrupted: true)).ordered.and_return("status" => "interrupted")
    expect(catch(:cancel) { batch.run(present: ->(_) { throw :cancel, :stopped }) { } }).to eq(:stopped)
  end
  it "presents an owned immutable summary" do
    source = { "status" => "complete", "devices" => [] }
    allow(report).to receive(:finish).and_return(source)
    seen = nil
    outcome = batch.run(present: ->(summary) { seen = summary }) { }
    expect(seen).to be_frozen
    expect(seen.fetch("devices")).to be_frozen
    expect(source).not_to be_frozen
    source["status"] = "failed"
    expect(outcome.status).to eq(:complete)
    expect(outcome.summary.fetch("status")).to eq("complete")
  end
end
