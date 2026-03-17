# frozen_string_literal: true

require "monitor"
require "securerandom"

module Philiprehberger
  module StructuredLogger
    # Thread-safe structured logger with context, child loggers, multiple
    # outputs, custom formatters, log sampling, correlation IDs, and async mode.
    class Logger
      LEVELS = { debug: 0, info: 1, warn: 2, error: 3, fatal: 4 }.freeze

      CORRELATION_ID_KEY = :philiprehberger_structured_logger_correlation_id

      attr_reader :context, :level

      # @param output [IO, nil] writable output (default: $stdout). Ignored if outputs: is provided.
      # @param outputs [Array<IO, Hash>] multiple outputs. Each element is an IO or
      #   a Hash with :io, optional :level, and optional :formatter.
      # @param level [Symbol] minimum log level
      # @param context [Hash] base context merged into every entry
      # @param formatter [Symbol, Proc, nil] formatter for default output (:json, :text, or callable)
      # @param sampling [Hash{Symbol => Float}] sampling rates per level (0.0..1.0)
      # @param async [Boolean] enable non-blocking background writes
      # @param buffer_size [Integer] async buffer size (only used when async: true)
      def initialize(output: nil, outputs: nil, level: :debug, context: {},
                     formatter: nil, sampling: {}, async: false, buffer_size: 1000)
        @level = level
        @context = context.freeze
        @sampling = sampling
        @async = async
        @buffer_size = buffer_size
        @monitor = Monitor.new

        @outputs = build_outputs(output, outputs, formatter, async, buffer_size)
      end

      # Set the minimum log level.
      #
      # @param new_level [Symbol]
      def level=(new_level)
        validate_level!(new_level)
        @level = new_level
      end

      # Add an additional output destination.
      #
      # @param io [IO] writable output
      # @param level [Symbol, nil] minimum level for this output
      # @param formatter [Symbol, Proc, nil] formatter for this output
      def add_output(io, level: nil, formatter: nil)
        resolved = StructuredLogger.resolve_formatter(formatter)
        wrapped = @async ? AsyncWriter.new(io, buffer_size: @buffer_size) : io
        @monitor.synchronize do
          @outputs << { io: wrapped, level: level, formatter: resolved }
        end
      end

      # Create a child logger with additional context.
      #
      # @param extra [Hash] context to merge
      # @return [Logger]
      def child(**extra)
        clone = self.class.allocate
        clone.send(:initialize_child, @outputs, @level, @context.merge(extra), @sampling, @monitor)
        clone
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

      # Set a correlation ID for all log entries within the block.
      # Uses Thread-local storage so each thread can have its own ID.
      #
      # @param id [String, nil] correlation ID (auto-generates a UUID if nil)
      # @yield block during which the correlation ID is active
      def with_correlation_id(id = nil, &block)
        id ||= SecureRandom.uuid
        previous = Thread.current[CORRELATION_ID_KEY]
        Thread.current[CORRELATION_ID_KEY] = id
        block.call
      ensure
        Thread.current[CORRELATION_ID_KEY] = previous
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

      # Force all async outputs to write their buffered log lines.
      def flush
        @monitor.synchronize do
          @outputs.each do |out|
            out[:io].flush if out[:io].respond_to?(:flush)
          end
        end
      end

      # Flush and stop all async writers.
      def close
        @monitor.synchronize do
          @outputs.each do |out|
            out[:io].close if out[:io].respond_to?(:close) && out[:io].is_a?(AsyncWriter)
          end
        end
      end

      LEVELS.each_key do |lvl|
        define_method(lvl) do |message, **extra|
          log(lvl, message, **extra)
        end
      end

      private

      # Initialize a child logger sharing the parent's outputs and monitor.
      def initialize_child(outputs, level, context, sampling, monitor)
        @outputs = outputs
        @level = level
        @context = context.freeze
        @sampling = sampling
        @monitor = monitor
        @async = false
        @buffer_size = 1000
      end

      def build_outputs(output, outputs, formatter, async, buffer_size)
        if outputs
          outputs.map do |out|
            if out.is_a?(Hash)
              io = async ? AsyncWriter.new(out[:io], buffer_size: buffer_size) : out[:io]
              fmt = StructuredLogger.resolve_formatter(out[:formatter])
              { io: io, level: out[:level], formatter: fmt }
            else
              io = async ? AsyncWriter.new(out, buffer_size: buffer_size) : out
              { io: io, level: nil, formatter: StructuredLogger.resolve_formatter(formatter) }
            end
          end
        else
          io = output || $stdout
          io = async ? AsyncWriter.new(io, buffer_size: buffer_size) : io
          [{ io: io, level: nil, formatter: StructuredLogger.resolve_formatter(formatter) }]
        end
      end

      def log(level, message, **extra)
        return unless should_log?(level)
        return unless sample?(level)

        merged = @context.merge(extra)

        # Inject correlation ID if present
        correlation_id = Thread.current[CORRELATION_ID_KEY]
        merged = merged.merge(correlation_id: correlation_id) if correlation_id

        @monitor.synchronize do
          @outputs.each do |out|
            next if out[:level] && LEVELS.fetch(level) < LEVELS.fetch(out[:level])

            line = out[:formatter].call(level, message, merged)
            out[:io].puts(line)
          end
        end
      end

      def should_log?(level)
        LEVELS.fetch(level) >= LEVELS.fetch(@level)
      end

      def sample?(level)
        rate = @sampling.fetch(level, 1.0)
        return true if rate >= 1.0
        return false if rate <= 0.0

        rand < rate
      end

      def validate_level!(level)
        return if LEVELS.key?(level)

        raise ArgumentError, "Invalid level: #{level}. Valid: #{LEVELS.keys.join(', ')}"
      end
    end
  end
end
