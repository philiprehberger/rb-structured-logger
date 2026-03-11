# frozen_string_literal: true

require "spec_helper"
require "json"

RSpec.describe Philiprehberger::StructuredLogger do
  it "has a version number" do
    expect(Philiprehberger::StructuredLogger::VERSION).not_to be_nil
  end
end

RSpec.describe Philiprehberger::StructuredLogger::Logger do
  subject(:logger) { described_class.new(output: output, level: level, context: context) }

  let(:output) { StringIO.new }
  let(:level) { :debug }
  let(:context) { {} }

  describe "#debug" do
    it "writes a JSON log line" do
      logger.debug("hello")
      entry = JSON.parse(output.string)

      expect(entry["level"]).to eq("debug")
      expect(entry["message"]).to eq("hello")
      expect(entry).to have_key("timestamp")
    end
  end

  describe "#info" do
    it "logs at info level" do
      logger.info("info message")
      entry = JSON.parse(output.string)

      expect(entry["level"]).to eq("info")
      expect(entry["message"]).to eq("info message")
    end
  end

  describe "#warn" do
    it "logs at warn level" do
      logger.warn("warning")
      entry = JSON.parse(output.string)

      expect(entry["level"]).to eq("warn")
    end
  end

  describe "#error" do
    it "logs at error level" do
      logger.error("failure")
      entry = JSON.parse(output.string)

      expect(entry["level"]).to eq("error")
    end
  end

  describe "#fatal" do
    it "logs at fatal level" do
      logger.fatal("crash")
      entry = JSON.parse(output.string)

      expect(entry["level"]).to eq("fatal")
    end
  end

  describe "JSON format" do
    it "includes timestamp in ISO8601 format" do
      logger.info("test")
      entry = JSON.parse(output.string)

      expect { Time.iso8601(entry["timestamp"]) }.not_to raise_error
    end

    it "includes extra context in the output" do
      logger.info("test", request_id: "abc-123")
      entry = JSON.parse(output.string)

      expect(entry["request_id"]).to eq("abc-123")
    end
  end

  describe "context merging" do
    let(:context) { { service: "api" } }

    it "includes base context in every log entry" do
      logger.info("request")
      entry = JSON.parse(output.string)

      expect(entry["service"]).to eq("api")
    end

    it "merges per-message context with base context" do
      logger.info("request", path: "/health")
      entry = JSON.parse(output.string)

      expect(entry["service"]).to eq("api")
      expect(entry["path"]).to eq("/health")
    end

    it "overrides base context with per-message context" do
      logger.info("request", service: "worker")
      entry = JSON.parse(output.string)

      expect(entry["service"]).to eq("worker")
    end
  end

  describe "#child" do
    let(:context) { { service: "api" } }

    it "returns a new logger with merged context" do
      child = logger.child(request_id: "xyz")

      expect(child.context).to eq({ service: "api", request_id: "xyz" })
    end

    it "writes entries with inherited context" do
      child_output = StringIO.new
      child = described_class.new(output: child_output, context: { service: "api" })
                             .child(request_id: "xyz")

      child.info("handled")
      entry = JSON.parse(child_output.string)

      expect(entry["service"]).to eq("api")
      expect(entry["request_id"]).to eq("xyz")
    end

    it "does not modify the parent logger context" do
      logger.child(extra: "data")

      expect(logger.context).to eq({ service: "api" })
    end
  end

  describe "level filtering" do
    let(:level) { :warn }

    it "suppresses messages below the configured level" do
      logger.debug("hidden")
      logger.info("hidden")

      expect(output.string).to be_empty
    end

    it "logs messages at or above the configured level" do
      logger.warn("visible")
      logger.error("also visible")

      lines = output.string.strip.split("\n")
      expect(lines.size).to eq(2)
    end
  end

  describe "#level=" do
    it "changes the minimum log level" do
      logger.level = :error
      logger.info("hidden")
      logger.error("visible")

      lines = output.string.strip.split("\n")
      expect(lines.size).to eq(1)
      expect(JSON.parse(lines.first)["level"]).to eq("error")
    end

    it "raises on invalid level" do
      expect { logger.level = :bogus }.to raise_error(ArgumentError, /Invalid level/)
    end
  end

  describe "custom output" do
    it "writes to the provided IO object" do
      buffer = StringIO.new
      custom = described_class.new(output: buffer)
      custom.info("buffered")

      expect(buffer.string).not_to be_empty
    end
  end
end

RSpec.describe Philiprehberger::StructuredLogger::Formatter do
  subject(:formatter) { described_class.new }

  it "returns valid JSON" do
    result = formatter.call(:info, "hello", {})

    expect { JSON.parse(result) }.not_to raise_error
  end

  it "includes all base fields" do
    entry = JSON.parse(formatter.call(:warn, "test", {}))

    expect(entry).to have_key("timestamp")
    expect(entry["level"]).to eq("warn")
    expect(entry["message"]).to eq("test")
  end

  it "merges context into the entry" do
    entry = JSON.parse(formatter.call(:info, "ctx", { user: "alice" }))

    expect(entry["user"]).to eq("alice")
  end
end
