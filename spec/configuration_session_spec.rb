# frozen_string_literal: true

require_relative "spec_helper"
require "ctx_runner/configuration_session"
require "ctx_parser/result"

RSpec.describe CtxRunner::ConfigurationSession do
  let(:session) { double(connected?: true, send_commands: nil, write_command: nil) }
  let(:parser) { double(parse: CtxParser::Result.new(status: :complete, records: [ { hostname: "leaf" } ])) }
  let(:adapter) do
    described_class.new(session: session, preparation_commands: [ "terminal length 0" ],
      configuration_command: "show running-config", parser: parser)
  end

  def receipt(command, success: true)
    double(success?: success, steps: [ { command: command } ], output: "hostname leaf", value!: "hostname leaf")
  end

  it "prepares and reads through one borrowed session without connecting or closing" do
    expect(session).to receive(:write_command).with("terminal length 0").ordered.and_return(receipt("terminal length 0"))
    expect(session).to receive(:send_commands).with([ "show running-config" ]).ordered.and_return(receipt("show running-config"))
    expect(session).not_to receive(:connect)
    expect(session).not_to receive(:close)
    expect(adapter.read_configuration).to eq("hostname" => "leaf")
  end

  it "rejects a mismatched preparation receipt before reading configuration" do
    expect(session).to receive(:write_command).once.and_return(receipt("unrelated"))
    expect(session).not_to receive(:send_commands)
    expect { adapter.read_configuration }.to raise_error(TypeError)
  end

  it "rejects partial readback and never retries an unconfirmed write" do
    allow(session).to receive(:write_command).and_return(receipt("terminal length 0"))
    allow(session).to receive(:send_commands).and_return(receipt("show running-config"))
    allow(parser).to receive(:parse).and_return(CtxParser::Result.new(status: :partial, records: [ { hostname: "leaf" } ]))
    expect { adapter.read_configuration }.to raise_error(ArgumentError)
    expect(session).to receive(:write_command).with("shutdown").once.and_return(receipt("shutdown", success: false))
    expect { adapter.write(" shutdown") }.to raise_error(IOError)
  end
end
