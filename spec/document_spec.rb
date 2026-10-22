# frozen_string_literal: true

require_relative "spec_helper"
require "ctx_runner/report"
require "ctx_runner/document"

RSpec.describe "JSON evidence documents" do
  it "does not freeze caller-owned keys in identity hashes" do
    key = +"identity"
    source = {}.compare_by_identity
    source[key] = "value"
    document = CtxRunner::Document.call(source)
    expect { key.replace("changed") }.not_to raise_error
    expect(document).to eq("identity" => "value")
  end

  it "normalizes JSON values without an encode/decode roundtrip or sharing mutable input" do
    record = Data.define(:time, :state).new(Time.utc(2026, 10, 22), :complete)
    source = { dimension: [ { 100 => +"value", flag: false, absent: nil, amount: 1.25, ratio: Rational(1, 2), complex: Complex(1, 2) } ], record: record }
    expected = { "dimension" => [ { "100" => "value", "flag" => false, "absent" => nil, "amount" => 1.25,
      "ratio" => "1/2", "complex" => "1+2i" } ], "record" => { "time" => "2026-10-22T00:00:00.000000Z", "state" => "complete" } }
    document = CtxRunner::Document.call(source)
    expect(document).to eq(expected)
    source[:dimension].first[100].replace("changed")
    expect(document.fetch("dimension").first.fetch("100")).to eq("value")
    expect { document.fetch("dimension") << {} }.to raise_error(FrozenError)
  end

  it "rejects ambiguous keys, cycles and opaque objects before publication" do
    cycle = []; cycle << cycle
    [ { a: 1, "a" => 2 }, cycle, Object.new ].each do |value|
      expect { CtxRunner::Document.call(value) }.to raise_error(ArgumentError)
    end
  end
end
