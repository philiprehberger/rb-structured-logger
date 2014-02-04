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
  end
end
