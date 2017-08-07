# frozen_string_literal: true

require "json"
require "time"

module Philiprehberger
  module StructuredLogger
    # Builds structured JSON log entries.
    class Formatter
      # Format a log entry as a JSON string.
      #
      # @param level [Symbol] the log level
      # @param message [String] the log message
      # @param context [Hash] merged context data
      # @return [String] JSON-encoded log line
      def call(level, message, context)
        entry = base_entry(level, message)
        entry.merge!(context) unless context.empty?
        JSON.generate(entry)
      end

      private

      def base_entry(level, message)
        {
          timestamp: Time.now.utc.iso8601(3),
          level: level.to_s,
          message: message
        }
      end
    end

    # Builds plain-text structured log entries.
    class TextFormatter
      # Format a log entry as a human-readable text string.
      #
      # @param level [Symbol] the log level
      # @param message [String] the log message
      # @param context [Hash] merged context data
      # @return [String] formatted text log line
      def call(level, message, context)
        timestamp = Time.now.utc.iso8601(3)
        parts = ["[#{timestamp}] #{level.to_s.upcase}: #{message}"]
        context.each do |key, value|
          parts << "#{key}=#{value}"
        end
        parts.join(" ")
      end
    end

    def self.resolve_formatter(formatter)
      case formatter
      when nil, :json then Formatter.new
      when :text then TextFormatter.new
      when Proc then formatter
      else
        unless formatter.respond_to?(:call)
          raise ArgumentError,
                "Formatter must be :json, :text, a Proc, or respond to #call"
        end

        formatter
      end
    end
  end
end
