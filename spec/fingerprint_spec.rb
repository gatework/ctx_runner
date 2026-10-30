# frozen_string_literal: true

require_relative "spec_helper"
require "ctx_runner/fingerprint"

RSpec.describe CtxRunner::Fingerprint do
  it "keeps existing JSON fingerprints independent of mapping order" do
    expect(described_class.call({ b: 2, a: [ 1, 3 ] })).to eq(Digest::SHA256.hexdigest('{"a":[1,3],"b":2}'))
    expect(described_class.call({ a: [ 3, 1 ], b: 2 })).not_to eq(described_class.call({ b: 2, a: [ 1, 3 ] }))
  end

  it "rejects key collisions instead of silently losing configuration facts" do
    expect { described_class.call({ x: 1, "x" => 2 }) }.to raise_error(ArgumentError)
  end

  it "rejects cycles and unsupported scalar values" do
    cycle = []; cycle << cycle
    expect { described_class.call(cycle) }.to raise_error(ArgumentError)
    expect { described_class.call(Object.new) }.to raise_error(ArgumentError)
  end

  it "uses the document depth budget beyond the JSON default limit" do
    value = 110.times.reduce("leaf") { |child, _| [ child ] }
    expect(described_class.call(value)).to match(/\A[0-9a-f]{64}\z/)
    value = 130.times.reduce("leaf") { |child, _| [ child ] }
    expect { described_class.call(value) }.to raise_error(ArgumentError)
  end
end
