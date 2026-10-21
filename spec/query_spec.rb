# frozen_string_literal: true

require_relative "spec_helper"
require "ctx_runner/query"
require "ctx_driver"

RSpec.describe CtxRunner::Query do
  it "reads and parses shared views once and binds the same capture to each" do
    capture = CtxDriver::Capture.new(command: "show", body: "body", started_at: Time.now, completed_at: Time.now)
    reader = double(read: capture)
    parser = double
    expect(parser).to receive(:parse_many).once.with([ :a, :b ], "body", complete: true, command: "show").and_return(a: 1, b: 2)
    expect(reader).to receive(:read).once.with("show").and_return(capture)
    result = described_class.new(reader: reader, parser: parser).read("show", names: [ :a, :b ], unavailable: ->(*) { raise "unexpected" }) do |name, value, source|
      [ name, value, source.command ]
    end
    expect(result).to eq(a: [ :a, 1, "show" ], b: [ :b, 2, "show" ])
  end

  it "isolates processing failures without losing the capture or leaking error messages" do
    capture = CtxDriver::Capture.new(command: "show", body: "body", started_at: Time.now, completed_at: Time.now)
    parser = double
    allow(parser).to receive(:parse_many).and_raise(ArgumentError, "private")
    result = described_class.new(reader: double(read: capture), parser: parser).read("show", names: [ :a ], unavailable: ->(_name, source, failure) { [ source.command, failure ] }) { raise "unexpected" }
    expect(result[:a].first).to eq("show")
    expect(result[:a].last).to include(code: :command_processing_failed, stage: :parse)
    expect(result.to_s).not_to include("private")
  end
  it "retains successful sibling views when one projection fails" do
    capture = CtxDriver::Capture.new(command: "show", body: "body", started_at: Time.now, completed_at: Time.now)
    parser = double(parse_many: { a: 1, b: 2, c: 3 })
    result = described_class.new(reader: double(read: capture), parser: parser).read("show", names: [ :a, :b, :c ],
      unavailable: ->(_name, _source, failure) { failure.fetch(:code) }) do |name, value, _source|
      raise ArgumentError, "private" if name == :b
      value
    end
    expect(result).to eq(a: 1, b: :command_processing_failed, c: 3)
  end
end
