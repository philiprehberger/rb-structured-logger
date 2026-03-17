# frozen_string_literal: true

require "thread"

module Philiprehberger
  module StructuredLogger
    # Non-blocking log writer that enqueues log lines to a background thread.
    # Falls back to synchronous writes when the buffer is full (backpressure).
    class AsyncWriter
      # @param output [IO] writable output destination
      # @param buffer_size [Integer] maximum number of queued log lines
      def initialize(output, buffer_size: 1000)
        @output = output
        @buffer_size = buffer_size
        @queue = SizedQueue.new(buffer_size)
        @stopped = false
        @closed = false
        @mutex = Mutex.new
        @thread = Thread.new { drain }
      end

      # Enqueue a log line for asynchronous writing.
      # Falls back to synchronous write if the buffer is full.
      #
      # @param line [String] the formatted log line
      def write(line)
        @mutex.synchronize do
          return sync_write(line) if @stopped
        end

        begin
          @queue.push(line, true)
        rescue ThreadError
          sync_write(line)
        end
      end

      # Write a log line using puts.
      #
      # @param line [String] the formatted log line
      def puts(line)
        write(line)
      end

      # Force all buffered log lines to be written immediately.
      def flush
        until @queue.empty?
          Thread.pass
        end
        @output.flush if @output.respond_to?(:flush)
      end

      # Flush remaining log lines and stop the background thread.
      # Safe to call multiple times.
      def close
        @mutex.synchronize do
          return if @closed

          @stopped = true
          @closed = true
        end
        @queue.push(:stop)
        @thread.join
        @output.flush if @output.respond_to?(:flush)
      end

      private

      def drain
        loop do
          line = @queue.pop
          break if line == :stop

          @output.puts(line)
        end

        # Drain remaining items after stop signal
        until @queue.empty?
          line = @queue.pop(true)
          @output.puts(line) unless line == :stop
        rescue ThreadError
          break
        end
      end

      def sync_write(line)
        @output.puts(line)
      end
    end
  end
end
