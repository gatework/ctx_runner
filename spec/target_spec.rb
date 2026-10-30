# frozen_string_literal: true

require_relative "spec_helper"
require "ctx_runner/target"

RSpec.describe CtxRunner::Target do
  it "compares identity independently from display attributes" do
    target = described_class.coerce("host" => "192.0.2.1", "platform" => "h3c", "id" => 1)
    expect(target.same_identity?(target.with(name: "controller"))).to be(true)
    expect(target.same_identity?(target.with(platform: "huawei"))).to be(false)
    expect(target.same_identity?(target.with(id: 2))).to be(false)
    expect({ target => :found }.fetch(target.with)).to eq(:found)
    expect(target.deconstruct_keys([ :host ])).to eq(host: "192.0.2.1")
  end

  it "rejects hidden credentials and ambiguous or mutable identity values" do
    [ { host: "192.0.2.1", password: "private" }, { host: "192.0.2.1", "host" => "192.0.2.2" },
      { host: "\n" }, { host: "192.0.2.1", id: [] } ].each do |value|
      expect { described_class.coerce(value) }.to raise_error(ArgumentError)
    end
    host = +"192.0.2.1"
    target = described_class.new(host: host)
    host.clear
    expect(target.host).to eq("192.0.2.1")
    expect { target.with(host: nil) }.to raise_error(ArgumentError)
  end
end
