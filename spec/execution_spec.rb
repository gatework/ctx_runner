# frozen_string_literal: true

require_relative "spec_helper"
require "ctx_runner/execution"

RSpec.describe CtxRunner::Execution do
  let(:before) { { "value" => 1 } }
  let(:after) { { "value" => 2 } }
  let(:plan) { { "target" => { "host" => "192.0.2.1" }, "expected_config_sha256" => CtxRunner::Fingerprint.call(before) } }
  let(:change) do
    Object.new.tap do |value|
      value.define_singleton_method(:commands) { [ "set value 2", "end" ] }
      value.define_singleton_method(:eligible?) { |config| config["value"] == 1 }
      value.define_singleton_method(:satisfied?) { |config, before:| config["value"] == 2 && before["value"] == 1 }
    end
  end
  let(:journal) { [] }
  let(:store) do
    entries = journal
    Object.new.tap { |value| value.define_singleton_method(:write_execution) { |state| entries << state } }
  end
  let(:writes) { [] }
  let(:session) do
    sent, initial, final = writes, before, after
    Object.new.tap do |value|
      value.define_singleton_method(:read_configuration) { sent.empty? ? initial : final }
      value.define_singleton_method(:write) { |command| sent << command; true }
    end
  end
  let(:execution) { described_class.new(plan: plan, change: change, journal: store, plan_sha256: "a" * 64) }

  it "records pending commands before sending and verifies after readback" do
    result = execution.run { |operation| operation.call(session) }
    expect(result["status"]).to eq("configuration_verified")
    expect(writes).to eq(change.commands)
    expect(journal.map { |state| state["pending_command"] }).to eq([ nil, 0, nil, 1, nil, nil ])
    expect(journal.first["steps"]).to eq([])
    expect(journal.last["steps"].size).to eq(2)
  end

  it "never replays a reused execution" do
    execution.run { |operation| operation.call(session) }
    expect { execution.run { |operation| operation.call(session) } }.to raise_error(ArgumentError)
    expect(writes.size).to eq(2)
    expect(journal.last["status"]).to eq("configuration_verified")
  end

  it "revokes a retained session callback when the provider exits" do
    callback = nil
    expect { execution.run { |operation| callback = operation } }.to raise_error(IOError)
    expect { callback.call(session) }.to raise_error(IOError)
    expect(writes).to be_empty
    expect(journal.last["status"]).to eq("failed")
  end

  it "rejects duplicate sessions without repeating commands" do
    expect { execution.run { |operation| 2.times { operation.call(session) } } }.to raise_error(IOError)
    expect(writes.size).to eq(2)
    expect(journal.last["status"]).to eq("uncertain")
  end

  it "rejects a duplicate delivery even when the provider swallows its exception" do
    expect do
      execution.run do |operation|
        operation.call(session)
        begin
          operation.call(session)
        rescue IOError
          nil
        end
      end
    end.to raise_error(IOError)
    expect(writes).to eq(change.commands)
    expect(journal.last["status"]).to eq("uncertain")
    expect(journal.none? { |entry| entry["status"] == "configuration_verified" }).to be(true)
  end

  it "retains the acknowledged command if journaling fails afterwards" do
    allow(store).to receive(:write_execution).and_wrap_original do |original, state|
      raise IOError if journal.size == 2 && state["status"] == "executing"
      original.call(state)
    end
    expect { execution.run { |operation| operation.call(session) } }.to raise_error(IOError)
    expect(writes).to eq([ "set value 2" ])
    expect(journal.last).to include("status" => "uncertain", "steps" => [ { "index" => 0, "status" => "acknowledged" } ])
  end

  it "does not send commands on a provider's foreign thread" do
    expect do
      execution.run do |operation|
        worker = Thread.new do
          operation.call(session)
        rescue IOError
          nil
        end
        worker.value
      end
    end.to raise_error(IOError)
    expect(writes).to be_empty
    expect(journal.last["status"]).to eq("failed")
  end

  it "takes ownership of plan inputs before external callbacks" do
    run = execution
    plan["expected_config_sha256"] = "changed"
    run.run { |operation| operation.call(session) }
    expect(journal.last["status"]).to eq("configuration_verified")
  end

  it "preserves interruption and stops before later commands" do
    allow(session).to receive(:write).and_raise(Interrupt)
    expect { execution.run { |operation| operation.call(session) } }.to raise_error(Interrupt)
    expect(journal.last).to include("status" => "uncertain", "error" => "interrupted", "pending_command" => 0)
  end
end
