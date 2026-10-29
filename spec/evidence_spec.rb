# frozen_string_literal: true

require_relative "spec_helper"
require "ctx_runner/evidence"
require "json"

RSpec.describe CtxRunner::Evidence do
  def document
    observation = CtxRunner::Observation.new(name: :configuration, status: :complete, records: [ { hostname: "leaf" } ])
    snapshot = CtxRunner::Snapshot.new(target: { host: "192.0.2.1" }, observations: { configuration: observation },
      names: [ :configuration ], observed_at: Time.utc(2026, 10, 29))
    JSON.parse(JSON.generate(described_class.wrap({ device: { host: "192.0.2.1", name: "leaf" }, snapshot: snapshot }, kind: "collection")))
  end

  it "round trips the shared snapshot while leaving domain records to the consumer" do
    records = []
    described_class.validate(document, names: [ :configuration ]) { |record, name| records << [ name, record ] }
    expect(records).to eq([ [ "configuration", { "hostname" => "leaf" } ] ])
  end

  it "rejects old versions and mismatched kinds without guessing missing fields" do
    [ nil, 1, 2, 4 ].each do |version|
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
    expect(value).to eq("schema_version" => 3, "kind" => "collection")
    expect(value.fetch("kind")).to be_frozen
  end
end
