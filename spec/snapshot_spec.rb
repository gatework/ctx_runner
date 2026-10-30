# frozen_string_literal: true

require_relative "spec_helper"
require "ctx_runner/snapshot"

RSpec.describe CtxRunner::Snapshot do
  def snapshot(observations = {}, **options)
    described_class.new(target: { host: "192.0.2.1" }, observations: observations,
      names: %i[interfaces bgp], observed_at: Time.now, **options)
  end

  def observation(name, status, **options)
    CtxRunner::Observation.new(name: name, status: status, **options)
  end

  it "distinguishes empty requests, unavailable facts and conclusive evidence" do
    expect(snapshot.collection_status).to eq(:not_requested)
    expect(snapshot({ bgp: observation(:bgp, :not_requested) }).collection_status).to eq(:not_requested)
    expect(snapshot({ bgp: observation(:bgp, :unsupported) }).collection_status).to eq(:failed)
    expect(snapshot({ bgp: observation(:bgp, :complete) }).collection_status).to eq(:complete)
    expect(snapshot({ bgp: observation(:bgp, :partial) }).collection_status).to eq(:partial)
    expect(snapshot({ bgp: observation(:bgp, :complete) }, issues: [ { code: :session_close_failed } ]).collection_status).to eq(:partial)
    expect(snapshot({ interfaces: observation(:interfaces, :complete), bgp: observation(:bgp, :failed) }).collection_status).to eq(:partial)
    expect(snapshot({ bgp: observation(:bgp, :not_applicable, evidence: [ { sha256: "a" * 64, bytes: 1 } ]) }).collection_status).to eq(:complete)
    expect { observation(:bgp, :not_applicable) }.to raise_error(ArgumentError)
  end

  it "rejects invalid identities and mismatched dimensions before accepting facts" do
    [ {}, { host: " " }, { host: "a\nb" }, { host: "host", password: "private" },
      { host: "host", "host" => "duplicate" }, { host: "host", id: -1 } ].each do |target|
      expect { snapshot(target: target) }.to raise_error(ArgumentError)
    end
    expect { snapshot(observed_at: "2026-10-29T00:00:00Z") }.to raise_error(ArgumentError)
    expect { snapshot({ unknown: observation(:unknown, :complete) }) }.to raise_error(ArgumentError)
    expect { snapshot({ bgp: observation(:interfaces, :complete) }) }.to raise_error(ArgumentError)
    expect { snapshot.observation(:unknown) }.to raise_error(ArgumentError)
  end

  it "owns its public identity and times without freezing caller data" do
    target = { "host" => +"192.0.2.1", "id" => +"leaf" }
    time = Time.new(2026, 10, 29, 10, 0, 0, "+08:00")
    value = snapshot(target: target, observed_at: time)
    target["host"].clear
    time.localtime("-04:00")
    expect(value.target.to_h).to eq(host: "192.0.2.1", id: "leaf")
    expect(value.observed_at.utc?).to be(true)
    expect(CtxRunner::Document.call(value)).to include("observed_at" => "2026-10-29T02:00:00.000000Z", "collection_status" => "not_requested", "observations" => {})
    expect(value.to_h).not_to have_key(:dimensions)
    expect(value.observations).not_to have_key(:collection)
    expect(value.observation(:bgp).status).to eq(:not_requested)
  end
end
