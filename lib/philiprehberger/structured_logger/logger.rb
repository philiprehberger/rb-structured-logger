# frozen_string_literal: true

require "monitor"
require "securerandom"

module Philiprehberger
  module StructuredLogger
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
        @monitor.synchronize { @outputs << { io: wrapped, level: level, formatter: resolved } }
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
        @monitor.synchronize { @outputs.each { |out| out[:io].flush if out[:io].respond_to?(:flush) } }
      end

      def close
        @monitor.synchronize { @outputs.each { |out| out[:io].close if out[:io].is_a?(AsyncWriter) } }
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
      end

      def log(level, message, **extra)
        return unless LEVELS.fetch(level) >= LEVELS.fetch(@level)
        return unless sample?(level)

        merged = @context.merge(extra)
        cid = Thread.current[CORRELATION_ID_KEY]
        merged = merged.merge(correlation_id: cid) if cid
        @monitor.synchronize { write_to_outputs(level, message, merged) }
      end

      def write_to_outputs(level, message, merged)
        @outputs.each do |out|
          next if out[:level] && LEVELS.fetch(level) < LEVELS.fetch(out[:level])

          out[:io].puts(out[:formatter].call(level, message, merged))
        end
      end

      def sample?(level)
        rate = @sampling.fetch(level, 1.0)
        rate >= 1.0 || (rate > 0.0 && rand < rate)
      end

      def validate_level!(level)
        raise ArgumentError, "Invalid level: #{level}" unless LEVELS.key?(level)
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
