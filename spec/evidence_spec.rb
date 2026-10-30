# frozen_string_literal: true

require_relative "spec_helper"
require "ctx_runner/evidence"
require "json"

RSpec.describe CtxRunner::Evidence do
  def document
    observation = CtxRunner::Observation.new(name: :configuration, status: :complete, records: [ { hostname: "leaf" } ])
    snapshot = CtxRunner::Snapshot.new(target: { host: "192.0.2.1" }, observations: { configuration: observation },
      names: [ :configuration ], observed_at: Time.utc(2026, 10, 29))
    JSON.parse(JSON.generate(described_class.wrap({ status: :complete, target: { host: "192.0.2.1", name: "leaf" }, snapshot: snapshot }, kind: "collection")))
  end

  it "round trips the shared snapshot while leaving domain records to the consumer" do
    records = []
    described_class.validate(document, names: [ :configuration ]) { |record, name| records << [ name, record ] }
    expect(records).to eq([ [ "configuration", { "hostname" => "leaf" } ] ])
  end

  it "rejects contradictory top-level status and partial identities" do
    [ ->(value) { value["status"] = "failed" },
      ->(value) { value["target"]["platform"] = "h3c" },
      ->(value) { value["snapshot"]["target"]["id"] = 1 },
      ->(value) { value["snapshot"] = nil } ].each do |change|
      value = document
      change.call(value)
      expect { described_class.validate(value, names: [ :configuration ]) { } }.to raise_error(ArgumentError)
    end
  end

  it "validates serialized source status and rejects placeholder proof" do
    value = document
    observation = value.fetch("snapshot").fetch("observations").fetch("configuration")
    observation["status"] = "not_applicable"
    observation["records"] = []
    observation["evidence"] = [ { "command" => "show feature", "sha256" => "a" * 64, "bytes" => 3, "status" => "complete" } ]
    expect { described_class.validate(value, names: [ :configuration ]) { } }.not_to raise_error
    observation["evidence"] = [ {} ]
    expect { described_class.validate(value, names: [ :configuration ]) { } }.to raise_error(ArgumentError)
  end

  it "rejects old versions and mismatched kinds without guessing missing fields" do
    [ nil, 1, 2, 3, 5 ].each do |version|
      expect { described_class.validate(document.merge("schema_version" => version), names: [ :configuration ]) { } }.to raise_error(ArgumentError, /regenerate/)
    end
    expect { described_class.validate(document.merge("kind" => "change_plan"), names: [ :configuration ]) { } }.to raise_error(ArgumentError, /regenerate/)
  end

  it "rejects forged identities, coverage conclusions and timestamps" do
    [ ->(value) { value["target"]["password"] = "private" },
      ->(value) { value["target"]["host"] = "192.0.2.2" },
      ->(value) { value["observed_at"] = "2026-02-30T00:00:00Z" },
      ->(value) { value["collection_status"] = "failed" },
      ->(value) { value["observations"]["collection"] = value["observations"].delete("configuration") },
      ->(value) { value["observations"]["configuration"]["name"] = "interfaces" } ].each do |change|
      value = document
      change.call(value.fetch("snapshot"))
      expect { described_class.validate(value, names: [ :configuration ]) { } }.to raise_error(ArgumentError)
    end
  end

  it "does not freeze caller-owned document kinds" do
    kind = +"collection"
    value = described_class.wrap({}, kind: kind)
    kind.clear
    expect(value).to eq("schema_version" => 4, "kind" => "collection")
    expect(value.fetch("kind")).to be_frozen
  end

  it "binds the selected change platform to its target identity" do
    change = { "schema_version" => 4, "kind" => "change", "platform" => "h3c",
      "target" => { "host" => "192.0.2.1", "platform" => "h3c" }, "expected_config_sha256" => "a" * 64 }
    plan = { "schema_version" => 4, "kind" => "change_plan", "platform" => "h3c", "changes" => { "secure" => change } }
    expect(described_class.plan(plan, item: "secure", platform: "h3c")).to eq(change)
    [ nil, "huawei" ].each do |platform|
      change["target"]["platform"] = platform
      expect { described_class.plan(plan, item: "secure", platform: "h3c") }.to raise_error(ArgumentError)
    end
  end
end
