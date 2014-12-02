# frozen_string_literal: true

require "monitor"

module Philiprehberger
  module StructuredLogger
    # Thread-safe structured JSON logger with context and child loggers.
    class Logger
      LEVELS = { debug: 0, info: 1, warn: 2, error: 3, fatal: 4 }.freeze

      attr_reader :context, :level

      # @param output [IO] writable output (default: $stdout)
      # @param level [Symbol] minimum log level
      # @param context [Hash] base context merged into every entry
      def initialize(output: $stdout, level: :debug, context: {})
        @output = output
        @level = level
        @context = context.freeze
        @formatter = Formatter.new
        @monitor = Monitor.new
      end

      # Set the minimum log level.
      #
      # @param new_level [Symbol]
      def level=(new_level)
        validate_level!(new_level)
        @level = new_level
      end

      # Create a child logger with additional context.
      #
      # @param extra [Hash] context to merge
      # @return [Logger]
      def child(**extra)
        self.class.new(output: @output, level: @level, context: @context.merge(extra))
      end

      # Temporarily merge extra context for the duration of a block.
      #
      # @param extra [Hash] additional context
      # @yield block during which the extra context is active
      def with_context(**extra, &block)
        @monitor.synchronize do
          original = @context
          @context = @context.merge(extra).freeze
          block.call
        ensure
          @context = original
        end
      end

      # Temporarily raise the log level for the duration of a block.
      #
      # @param temp_level [Symbol] level to use during the block
      # @yield block during which the level is raised
      def silence(temp_level = :fatal, &block)
        @monitor.synchronize do
          original = @level
          @level = temp_level
          block.call
        ensure
          @level = original
        end
      end

      # Log an exception with its class, message, and backtrace.
      #
      # @param exception [Exception] the exception to log
      # @param level [Symbol] log level to use
      # @param extra [Hash] additional context
      def log_exception(exception, level: :error, **extra)
        log(level, exception.message, **extra.merge(
          error_class: exception.class.name,
          backtrace: exception.backtrace || []
        ))
      end

      LEVELS.each_key do |lvl|
        define_method(lvl) do |message, **extra|
          log(lvl, message, **extra)
        end
      end

      private

      def log(level, message, **extra)
        return unless should_log?(level)

        merged = @context.merge(extra)
        line = @formatter.call(level, message, merged)
        @monitor.synchronize { @output.puts(line) }
      end

      def should_log?(level)
        LEVELS.fetch(level) >= LEVELS.fetch(@level)
      end

      def validate_level!(level)
        return if LEVELS.key?(level)

        raise ArgumentError, "Invalid level: #{level}. Valid: #{LEVELS.keys.join(', ')}"
      end
    end
  end
end
