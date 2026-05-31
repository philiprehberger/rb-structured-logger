# frozen_string_literal: true

require 'monitor'
require 'securerandom'

module Philiprehberger
  module StructuredLogger
    class Logger
      LEVELS = { debug: 0, info: 1, warn: 2, error: 3, fatal: 4 }.freeze

      CORRELATION_ID_KEY = :philiprehberger_structured_logger_correlation_id

      # Regex matching a single Ruby backtrace line. Captures the file
      # path, the line number, and (optionally) the method name. Handles
      # both Ruby 3.4+ single-quote (`'method'`) and Ruby 3.3-and-earlier
      # backtick-apostrophe (`` `method' ``) quoting.
      BACKTRACE_LINE = /\A(?<file>.+?):(?<line>\d+)(?::in ['`](?<method>[^']+)')?\z/

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

      # Adds the given tags to the logger's context under the `:tags`
      # key, merging with any existing tags (de-duplicated, preserving
      # insertion order). When a block is given, the previous context is
      # restored when the block exits (even on exception). Without a
      # block, the change persists like {#with_context}.
      #
      # @param tags [Array<String, Symbol>] one or more tags to add.
      # @yield (optional) executes within the tagged context; the
      #   original context is restored on exit.
      # @return [Object, Hash] the block's return value when a block is
      #   given, otherwise the new merged context hash.
      #
      # @example Block form
      #   logger.with_tags('auth', 'request') do
      #     logger.info('Login attempt')
      #     # entry includes tags: ['auth', 'request']
      #   end
      def with_tags(*tags)
        existing = @context[:tags] || []
        merged_tags = (existing + tags).uniq
        if block_given?
          @monitor.synchronize do
            original = @context
            @context = @context.merge(tags: merged_tags).freeze
            yield
          ensure
            @context = original
          end
        else
          @monitor.synchronize do
            @context = @context.merge(tags: merged_tags).freeze
          end
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

      # Logs an exception's message, class, and backtrace as a single
      # structured entry.
      #
      # @param exception [Exception] the exception to log.
      # @param level [Symbol] the log level for the entry (default
      #   `:error`).
      # @param structured_backtrace [Boolean] when `false` (default),
      #   the backtrace is emitted as an array of raw strings (the same
      #   shape as `exception.backtrace`). When `true`, each backtrace
      #   line is parsed into a hash with `:file`, `:line` (Integer),
      #   and (when present) `:method` keys. Lines that don't match the
      #   standard Ruby backtrace format are passed through as
      #   `{ raw: "<original line>" }`. The parsed form is generally
      #   easier to index in log-aggregation systems like Elasticsearch,
      #   Datadog, or Loki.
      # @param extra [Hash] additional context merged into the log
      #   entry.
      # @return [void]
      #
      # @example Default (raw string backtrace)
      #   logger.log_exception(e)
      #   # backtrace: ["app/foo.rb:42:in 'bar'", ...]
      #
      # @example Structured backtrace
      #   logger.log_exception(e, structured_backtrace: true)
      #   # backtrace: [
      #   #   { file: "app/foo.rb", line: 42, method: "bar" },
      #   #   ...
      #   # ]
      def log_exception(exception, level: :error, structured_backtrace: false, **extra)
        bt = exception.backtrace || []
        bt = parse_backtrace(bt) if structured_backtrace
        log(level, exception.message,
            error_class: exception.class.name,
            backtrace: bt,
            **extra)
      end

      # Yields to the given block, measures its monotonic wall-clock
      # duration, and emits a single info-level log entry describing the
      # outcome. On success, the block's return value is returned. On
      # exception, the failure is logged and the original exception is
      # re-raised.
      #
      # @param event_name [String, Symbol] the event name to record as
      #   the `event` field in the log entry.
      # @param context [Hash] extra context merged into the log entry.
      # @yield executes the measured block.
      # @return [Object] the block's return value on success.
      # @raise re-raises any exception raised by the block.
      #
      # @example Measuring a database query
      #   logger.measure('db.query', table: 'users') { User.find(1) }
      #   # logs event: 'db.query', table: 'users', duration_ms: 12.345
      def measure(event_name, **context)
        start = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        begin
          result = yield
          duration_ms = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - start) * 1000.0).round(3)
          log(:info, event_name.to_s, event: event_name, duration_ms: duration_ms, **context)
          result
        rescue StandardError => e
          duration_ms = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - start) * 1000.0).round(3)
          log(:info, event_name.to_s,
              event: event_name,
              duration_ms: duration_ms,
              error: e.message,
              error_class: e.class.name,
              **context)
          raise
        end
      end

      # Variant of {#measure} that emits the same timing log entry but
      # also returns the block's return value. Captures and re-raises
      # exceptions like {#measure}.
      #
      # @param event_name [String, Symbol] the event name to record as
      #   the `event` field in the log entry.
      # @param context [Hash] extra context merged into the log entry.
      # @yield executes the measured block.
      # @return [Object] the block's return value on success.
      # @raise re-raises any exception raised by the block.
      #
      # @example Capturing a query result
      #   result = logger.measure_value('db.query') { query_database }
      def measure_value(event_name, **context, &)
        measure(event_name, **context, &)
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

      def parse_backtrace(backtrace)
        backtrace.map do |line|
          if (m = line.match(BACKTRACE_LINE))
            { file: m[:file], line: m[:line].to_i, method: m[:method] }.compact
          else
            { raw: line }
          end
        end
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
