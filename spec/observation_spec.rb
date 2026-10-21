# frozen_string_literal: true

require_relative "spec_helper"
require "ctx_runner/observation"

RSpec.describe CtxRunner::Observation do
  it "rejects unavailable records and untyped acquisition times" do
    expect { described_class.new(name: :configuration, status: :failed, records: [ {} ]) }.to raise_error(ArgumentError)
    expect { described_class.new(name: :configuration, status: :complete, started_at: "now") }.to raise_error(ArgumentError)
  end

  it "detaches caller records and timestamps without exposing them through diagnostics" do
    records = [ { password: +"private" } ]; time = Time.now
    value = described_class.new(name: :configuration, status: :partial, records: records, started_at: time)
    records.first[:password].replace("changed")
    expect(value.records.first[:password]).to eq("private")
    expect(value.started_at).not_to equal(time)
    expect(value.inspect + value.to_s).not_to include("private")
    expect(value).to be_available
  end
end
