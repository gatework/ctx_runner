# frozen_string_literal: true

require_relative "spec_helper"
require "ctx_runner/session_scope"

RSpec.describe CtxRunner::SessionScope do
  it "allows one completed operation and rejects replay" do
    scope = described_class.new
    calls = []
    expect(scope.deliver { calls << :first }).to be(true)
    expect(scope.deliver { calls << :second }).to be(false)
    expect(scope.failure).to eq(:session_reentered)
    expect(calls).to eq([ :first ])
  end

  it "distinguishes no delivery from an unfinished operation" do
    scope = described_class.new
    expect(scope.failure).to eq(:session_not_opened)
    expect { scope.deliver { raise IOError, "private" } }.to raise_error(IOError)
    expect(scope.failure).to eq(:session_incomplete)
    expect(scope.deliver { raise "replayed" }).to be(false)
  end

  it "prevents another thread from borrowing the owner's session" do
    scope = described_class.new
    calls = []
    accepted = Thread.new { scope.deliver { calls << :foreign } }.value
    expect(accepted).to be(false)
    expect(scope.failure).to eq(:session_out_of_scope)
    expect(scope.deliver { calls << :retry }).to be(false)
    expect(calls).to be_empty
  end

  it "revokes retained callbacks without changing the completed outcome" do
    scope = described_class.new
    scope.deliver { }
    scope.close
    expect { scope.deliver { raise "late" } }.to raise_error(IOError)
    expect(scope.failure).to be_nil
    expect(scope.close).to be_nil
  end

  it "retains unfinished state on nonlocal exits" do
    scope = described_class.new
    expect(catch(:cancel) { scope.deliver { throw :cancel, :cancelled } }).to eq(:cancelled)
    expect(scope.failure).to eq(:session_incomplete)
  end
end
