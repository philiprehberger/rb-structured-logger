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

      def initialize(**opts)
        @level = opts.fetch(:level, :debug)
        @context = opts.fetch(:context, {}).freeze
        @sampling = opts.fetch(:sampling, {})
        @async = opts.fetch(:async, false)
        @buffer_size = opts.fetch(:buffer_size, 1000)
        @monitor = Monitor.new

        @outputs = OutputBuilder.call(opts, @async, @buffer_size)
      end

      def level=(new_level)
        validate_level!(new_level)
        @level = new_level
      end

      def add_output(io, level: nil, formatter: nil)
        resolved = StructuredLogger.resolve_formatter(formatter)
        wrapped = @async ? AsyncWriter.new(io, buffer_size: @buffer_size) : io
        @monitor.synchronize do
          @outputs << { io: wrapped, level: level, formatter: resolved }
        end
      end

      def child(**extra)
        clone = self.class.allocate
        clone.send(:initialize_child, @outputs, @level, @context.merge(extra), @sampling, @monitor)
        clone
      end

      def with_context(**extra, &block)
        @monitor.synchronize do
          original = @context
          @context = @context.merge(extra).freeze
          block.call
        ensure
          @context = original
        end
      end

      def silence(temp_level = :fatal, &block)
        @monitor.synchronize do
          original = @level
          @level = temp_level
          block.call
        ensure
          @level = original
        end
      end

      def with_correlation_id(id = nil, &block)
        id ||= SecureRandom.uuid
        previous = Thread.current[CORRELATION_ID_KEY]
        Thread.current[CORRELATION_ID_KEY] = id
        block.call
      ensure
        Thread.current[CORRELATION_ID_KEY] = previous
      end

      def log_exception(exception, level: :error, **extra)
        log(level, exception.message,
            error_class: exception.class.name,
            backtrace: exception.backtrace || [],
            **extra)
      end

      def flush
        @monitor.synchronize do
          @outputs.each do |out|
            out[:io].flush if out[:io].respond_to?(:flush)
          end
        end
      end

      def close
        @monitor.synchronize do
          @outputs.each do |out|
            out[:io].close if out[:io].is_a?(AsyncWriter)
          end
        end
      end

      LEVELS.each_key do |lvl|
        define_method(lvl) do |message, **extra|
          log(lvl, message, **extra)
        end
      end

      private

      def initialize_child(outputs, level, context, sampling, monitor)
        @outputs = outputs
        @level = level
        @context = context.freeze
        @sampling = sampling
        @monitor = monitor
        @async = false
        @buffer_size = 1000
      end

      def log(level, message, **extra)
        return unless should_log?(level)
        return unless sample?(level)

        merged = build_merged_context(extra)

        @monitor.synchronize do
          write_to_outputs(level, message, merged)
        end
      end

      def build_merged_context(extra)
        merged = @context.merge(extra)
        correlation_id = Thread.current[CORRELATION_ID_KEY]
        merged = merged.merge(correlation_id: correlation_id) if correlation_id
        merged
      end

      def write_to_outputs(level, message, merged)
        @outputs.each do |out|
          next if out[:level] && LEVELS.fetch(level) < LEVELS.fetch(out[:level])

          line = out[:formatter].call(level, message, merged)
          out[:io].puts(line)
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

    # Builds output configuration from constructor options.
    module OutputBuilder
      module_function

      def call(opts, async, buffer_size)
        outputs = opts[:outputs]
        if outputs
          build_multi(outputs, opts[:formatter], async, buffer_size)
        else
          build_single(opts[:output], opts[:formatter], async, buffer_size)
        end
      end

      def build_multi(outputs, default_formatter, async, buffer_size)
        outputs.map do |out|
          if out.is_a?(Hash)
            build_hash_output(out, async, buffer_size)
          else
            io = async ? AsyncWriter.new(out, buffer_size: buffer_size) : out
            { io: io, level: nil, formatter: StructuredLogger.resolve_formatter(default_formatter) }
          end
        end
      end

      def build_hash_output(out, async, buffer_size)
        io = async ? AsyncWriter.new(out[:io], buffer_size: buffer_size) : out[:io]
        fmt = StructuredLogger.resolve_formatter(out[:formatter])
        { io: io, level: out[:level], formatter: fmt }
      end

      def build_single(output, formatter, async, buffer_size)
        io = output || $stdout
        io = AsyncWriter.new(io, buffer_size: buffer_size) if async
        [{ io: io, level: nil, formatter: StructuredLogger.resolve_formatter(formatter) }]
      end
    end
  end
end
