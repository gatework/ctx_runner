# frozen_string_literal: true

require_relative "spec_helper"
require "ctx_runner/collection"

RSpec.describe CtxRunner::Collection do
  def connector(count: 1, close_error: false)
    Object.new.tap do |value|
      value.define_singleton_method(:open) do |&operation|
        count.times { operation.call(:session) }
        raise IOError, "private" if close_error
      end
    end
  end

  it "never repeats collection when a provider yields twice" do
    calls = []
    run = described_class.new
    run.open(connector(count: 2)) { |session| calls << session }
    expect(calls).to eq([ :session ])
    expect(run.failure).to include(code: :session_reentered)
  end

  it "distinguishes missing sessions and close failures" do
    run = described_class.new
    run.open(connector(count: 0)) { raise "not called" }
    expect(run.failure).to include(code: :session_not_opened, stage: :connect)
    run = described_class.new
    run.open(connector(close_error: true)) { }
    expect(run.failure).to include(code: :session_close_failed, stage: :close)
    expect(run.failure.to_s).not_to include("private")
  end

  it "preserves strict provider contracts without swallowing programming errors" do
    expect { described_class.new(strict: true).open(connector(count: 0)) { } }.to raise_error(ArgumentError)
    expect { described_class.new.open(connector) { raise TypeError } }.to raise_error(TypeError)
    expect { described_class.new.open(connector) { raise Interrupt } }.to raise_error(Interrupt)
  end

  it "revokes callbacks after the connection owner returns" do
    callback = nil
    owner = Object.new
    owner.define_singleton_method(:open) { |&operation| callback = operation }
    calls = []
    described_class.new.open(owner) { |session| calls << session }
    expect { callback.call(:late) }.to raise_error(IOError)
    expect(calls).to be_empty
  end

  it "retains strict contract violations even when the provider rescues them" do
    owner = Object.new
    owner.define_singleton_method(:open) do |&operation|
      operation.call(:session)
      begin
        operation.call(:session)
      rescue ArgumentError
        nil
      end
    end
    calls = []
    expect { described_class.new(strict: true).open(owner) { |session| calls << session } }.to raise_error(ArgumentError)
    expect(calls).to eq([ :session ])
  end

  it "does not report completion when a provider swallows an unfinished operation" do
    owner = Object.new
    owner.define_singleton_method(:open) do |&operation|
      operation.call(:session)
    rescue IOError
      nil
    end
    run = described_class.new
    run.open(owner) { raise IOError, "private operation failure" }
    expect(run.failure).to include(code: :session_incomplete, stage: :collect)
    expect(run.failure.to_s).not_to include("private")
  end

  it "preserves the first provider violation when connection cleanup also fails" do
    run = described_class.new
    run.open(connector(count: 2, close_error: true)) { }
    expect(run.failure).to include(code: :session_reentered)
  end

  it "does not run device operations on a provider's foreign thread" do
    owner = Object.new
    owner.define_singleton_method(:open) { |&operation| Thread.new { operation.call(:session) }.value }
    calls = []
    run = described_class.new
    run.open(owner) { |session| calls << session }
    expect(run.failure).to include(code: :session_out_of_scope)
    expect(calls).to be_empty
  end
end
