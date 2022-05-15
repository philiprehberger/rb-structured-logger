# frozen_string_literal: true

require 'spec_helper'
require 'json'

RSpec.describe Philiprehberger::StructuredLogger do
  it 'has a version number' do
    expect(Philiprehberger::StructuredLogger::VERSION).not_to be_nil
  end
end

RSpec.describe Philiprehberger::StructuredLogger::Logger do
  subject(:logger) { described_class.new(output: output, level: level, context: context) }

  let(:output) { StringIO.new }
  let(:level) { :debug }
  let(:context) { {} }

  describe '#debug' do
    it 'writes a JSON log line' do
      logger.debug('hello')
      entry = JSON.parse(output.string)

      expect(entry['level']).to eq('debug')
      expect(entry['message']).to eq('hello')
      expect(entry).to have_key('timestamp')
    end
  end

  describe '#info' do
    it 'logs at info level' do
      logger.info('info message')
      entry = JSON.parse(output.string)

      expect(entry['level']).to eq('info')
      expect(entry['message']).to eq('info message')
    end
  end

  describe '#warn' do
    it 'logs at warn level' do
      logger.warn('warning')
      entry = JSON.parse(output.string)

      expect(entry['level']).to eq('warn')
    end
  end

  describe '#error' do
    it 'logs at error level' do
      logger.error('failure')
      entry = JSON.parse(output.string)

      expect(entry['level']).to eq('error')
    end
  end

  describe '#fatal' do
    it 'logs at fatal level' do
      logger.fatal('crash')
      entry = JSON.parse(output.string)

      expect(entry['level']).to eq('fatal')
    end
  end

  describe 'JSON format' do
    it 'includes timestamp in ISO8601 format' do
      logger.info('test')
      entry = JSON.parse(output.string)

      expect { Time.iso8601(entry['timestamp']) }.not_to raise_error
    end

    it 'includes extra context in the output' do
      logger.info('test', request_id: 'abc-123')
      entry = JSON.parse(output.string)

      expect(entry['request_id']).to eq('abc-123')
    end
  end

  describe 'context merging' do
    let(:context) { { service: 'api' } }

    it 'includes base context in every log entry' do
      logger.info('request')
      entry = JSON.parse(output.string)

      expect(entry['service']).to eq('api')
    end

    it 'merges per-message context with base context' do
      logger.info('request', path: '/health')
      entry = JSON.parse(output.string)

      expect(entry['service']).to eq('api')
      expect(entry['path']).to eq('/health')
    end

    it 'overrides base context with per-message context' do
      logger.info('request', service: 'worker')
      entry = JSON.parse(output.string)

      expect(entry['service']).to eq('worker')
    end
  end

  describe '#child' do
    let(:context) { { service: 'api' } }

    it 'returns a new logger with merged context' do
      child = logger.child(request_id: 'xyz')

      expect(child.context).to eq({ service: 'api', request_id: 'xyz' })
    end

    it 'writes entries with inherited context' do
      child_output = StringIO.new
      child = described_class.new(output: child_output, context: { service: 'api' })
                             .child(request_id: 'xyz')

      child.info('handled')
      entry = JSON.parse(child_output.string)

      expect(entry['service']).to eq('api')
      expect(entry['request_id']).to eq('xyz')
    end

    it 'does not modify the parent logger context' do
      logger.child(extra: 'data')

      expect(logger.context).to eq({ service: 'api' })
    end
  end

  describe 'level filtering' do
    let(:level) { :warn }

    it 'suppresses messages below the configured level' do
      logger.debug('hidden')
      logger.info('hidden')

      expect(output.string).to be_empty
    end

    it 'logs messages at or above the configured level' do
      logger.warn('visible')
      logger.error('also visible')

      lines = output.string.strip.split("\n")
      expect(lines.size).to eq(2)
    end
  end

  describe '#level' do
    it 'returns the current log level' do
      expect(logger.level).to eq(:debug)
    end

    it 'reflects changes made via level=' do
      logger.level = :warn

      expect(logger.level).to eq(:warn)
    end
  end

  describe '#level=' do
    it 'changes the minimum log level' do
      logger.level = :error
      logger.info('hidden')
      logger.error('visible')

      lines = output.string.strip.split("\n")
      expect(lines.size).to eq(1)
      expect(JSON.parse(lines.first)['level']).to eq('error')
    end

    it 'raises on invalid level' do
      expect { logger.level = :bogus }.to raise_error(ArgumentError, /Invalid level/)
    end
  end

  describe '#with_context' do
    let(:context) { { service: 'api' } }

    it 'merges extra context during the block' do
      logger.with_context(request_id: 'abc') do
        logger.info('inside')
      end

      entry = JSON.parse(output.string)
      expect(entry['service']).to eq('api')
      expect(entry['request_id']).to eq('abc')
    end

    it 'restores original context after the block' do
      logger.with_context(request_id: 'abc') do
        logger.info('inside')
      end

      expect(logger.context).to eq({ service: 'api' })
    end

    it 'restores context even when block raises' do
      expect do
        logger.with_context(request_id: 'abc') { raise 'boom' }
      end.to raise_error(RuntimeError, 'boom')

      expect(logger.context).to eq({ service: 'api' })
    end
  end

  describe '#silence' do
    it 'suppresses lower-level logs during the block' do
      logger.silence(:fatal) do
        logger.info('hidden')
        logger.error('hidden')
      end

      expect(output.string).to be_empty
    end

    it 'allows logs at or above the silence level' do
      logger.silence(:error) do
        logger.fatal('visible')
      end

      entry = JSON.parse(output.string)
      expect(entry['level']).to eq('fatal')
    end

    it 'restores the original level after the block' do
      logger.silence(:fatal) do
        logger.info('hidden')
      end

      logger.info('visible')
      expect(output.string).not_to be_empty
    end

    it 'restores level even when block raises' do
      expect do
        logger.silence(:fatal) { raise 'boom' }
      end.to raise_error(RuntimeError, 'boom')

      expect(logger.level).to eq(:debug)
    end
  end

  describe '#log_exception' do
    it 'logs exception class, message, and backtrace' do
      exception = begin
        raise StandardError, 'something broke'
      rescue StandardError => e
        e
      end

      logger.log_exception(exception)
      entry = JSON.parse(output.string)

      expect(entry['level']).to eq('error')
      expect(entry['message']).to eq('something broke')
      expect(entry['error_class']).to eq('StandardError')
      expect(entry['backtrace']).to be_an(Array)
      expect(entry['backtrace']).not_to be_empty
    end

    it 'logs at a custom level' do
      exception = StandardError.new('minor issue')

      logger.log_exception(exception, level: :warn)
      entry = JSON.parse(output.string)

      expect(entry['level']).to eq('warn')
    end

    it 'merges extra context' do
      exception = StandardError.new('oops')

      logger.log_exception(exception, user_id: 42)
      entry = JSON.parse(output.string)

      expect(entry['user_id']).to eq(42)
    end
  end

  describe 'custom output' do
    it 'writes to the provided IO object' do
      buffer = StringIO.new
      custom = described_class.new(output: buffer)
      custom.info('buffered')

      expect(buffer.string).not_to be_empty
    end
  end

  describe 'multiple outputs' do
    it 'writes to all outputs' do
      out1 = StringIO.new
      out2 = StringIO.new
      multi = described_class.new(outputs: [out1, out2])

      multi.info('hello')

      expect(out1.string).not_to be_empty
      expect(out2.string).not_to be_empty
      expect(JSON.parse(out1.string)['message']).to eq('hello')
      expect(JSON.parse(out2.string)['message']).to eq('hello')
    end

    it 'supports per-output level filtering' do
      out1 = StringIO.new
      out2 = StringIO.new
      outputs = [{ io: out1, level: nil }, { io: out2, level: :error }]
      multi = described_class.new(outputs: outputs)

      multi.info('info only')
      multi.error('error too')

      lines1 = out1.string.strip.split("\n")
      lines2 = out2.string.strip.split("\n")

      expect(lines1.size).to eq(2)
      expect(lines2.size).to eq(1)
      expect(JSON.parse(lines2.first)['level']).to eq('error')
    end

    it 'supports per-output formatters' do
      out_json = StringIO.new
      out_text = StringIO.new
      outputs = [{ io: out_json, formatter: :json }, { io: out_text, formatter: :text }]
      multi = described_class.new(outputs: outputs)

      multi.info('hello', user: 'alice')

      expect { JSON.parse(out_json.string) }.not_to raise_error
      expect(out_text.string).to include('INFO:')
      expect(out_text.string).to include('hello')
      expect(out_text.string).to include('user=alice')
    end

    it 'allows singular output: for backwards compatibility' do
      buf = StringIO.new
      compat = described_class.new(output: buf)
      compat.info('works')

      expect(buf.string).not_to be_empty
    end
  end

  describe '#add_output' do
    it 'adds a new output destination at runtime' do
      extra = StringIO.new
      logger.info('before')
      logger.add_output(extra)
      logger.info('after')

      expect(output.string).to include('before')
      expect(output.string).to include('after')
      expect(extra.string).not_to include('before')
      expect(extra.string).to include('after')
    end

    it 'supports level filtering on added output' do
      extra = StringIO.new
      logger.add_output(extra, level: :error)

      logger.info('info only')
      logger.error('error too')

      lines = extra.string.strip.split("\n")
      expect(lines.size).to eq(1)
      expect(JSON.parse(lines.first)['level']).to eq('error')
    end

    it 'supports custom formatter on added output' do
      extra = StringIO.new
      logger.add_output(extra, formatter: :text)

      logger.info('hello')

      expect(extra.string).to include('INFO:')
      expect(extra.string).to include('hello')
    end
  end

  describe 'custom formatters' do
    it 'uses :json formatter by default' do
      logger.info('test')

      expect { JSON.parse(output.string) }.not_to raise_error
    end

    it 'uses :text formatter' do
      text_logger = described_class.new(output: output, formatter: :text)
      text_logger.info('hello', key: 'val')

      expect(output.string).to include('INFO:')
      expect(output.string).to include('hello')
      expect(output.string).to include('key=val')
      expect(output.string).to match(/\[\d{4}-\d{2}-\d{2}/)
    end

    it 'uses a custom proc formatter' do
      custom_fmt = ->(level, message, _context) { "#{level}|#{message}" }
      custom_logger = described_class.new(output: output, formatter: custom_fmt)

      custom_logger.info('hello')

      expect(output.string.strip).to eq('info|hello')
    end

    it 'uses a callable object formatter' do
      formatter_obj = Object.new
      def formatter_obj.call(level, message, _context)
        "CUSTOM: #{level} #{message}"
      end

      custom_logger = described_class.new(output: output, formatter: formatter_obj)
      custom_logger.warn('test')

      expect(output.string.strip).to eq('CUSTOM: warn test')
    end

    it 'raises on invalid formatter' do
      expect do
        described_class.new(output: output, formatter: 42)
      end.to raise_error(ArgumentError, /Invalid formatter/)
    end
  end

  describe 'log sampling' do
    it 'logs all messages when sampling rate is 1.0' do
      sampled = described_class.new(output: output, sampling: { info: 1.0 })

      100.times { sampled.info('always') }
      lines = output.string.strip.split("\n")

      expect(lines.size).to eq(100)
    end

    it 'logs no messages when sampling rate is 0.0' do
      sampled = described_class.new(output: output, sampling: { info: 0.0 })

      100.times { sampled.info('never') }

      expect(output.string).to be_empty
    end

    it 'samples approximately the correct percentage' do
      sampled = described_class.new(output: output, sampling: { info: 0.5 })

      values = (Array.new(50, 0.3) + Array.new(50, 0.7))
      allow(sampled).to receive(:rand).and_return(*values)

      100.times { sampled.info('maybe') }
      lines = output.string.strip.split("\n")

      expect(lines.size).to eq(50)
    end

    it 'defaults unspecified levels to 1.0' do
      sampled = described_class.new(output: output, sampling: { debug: 0.0 })

      sampled.info('should appear')
      sampled.debug('should not appear')

      lines = output.string.strip.split("\n")
      expect(lines.size).to eq(1)
      expect(JSON.parse(lines.first)['level']).to eq('info')
    end
  end

  describe '#with_correlation_id' do
    it 'adds correlation_id to log entries within the block' do
      logger.with_correlation_id('req-abc-123') do
        logger.info('processing')
      end

      entry = JSON.parse(output.string)
      expect(entry['correlation_id']).to eq('req-abc-123')
    end

    it 'auto-generates a UUID when no ID is provided' do
      logger.with_correlation_id do
        logger.info('processing')
      end

      entry = JSON.parse(output.string)
      expect(entry['correlation_id']).to match(
        /\A[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\z/
      )
    end

    it 'removes correlation_id after the block' do
      logger.with_correlation_id('req-abc') do
        logger.info('inside')
      end

      output.truncate(0)
      output.rewind
      logger.info('outside')

      entry = JSON.parse(output.string)
      expect(entry).not_to have_key('correlation_id')
    end

    it 'restores previous correlation_id on nesting' do
      logger.with_correlation_id('outer') do
        logger.with_correlation_id('inner') do
          logger.info('nested')
        end

        output.truncate(0)
        output.rewind
        logger.info('back to outer')
      end

      entry = JSON.parse(output.string)
      expect(entry['correlation_id']).to eq('outer')
    end

    it 'restores correlation_id even when block raises' do
      expect do
        logger.with_correlation_id('req-abc') { raise 'boom' }
      end.to raise_error(RuntimeError, 'boom')

      logger.info('after error')
      entry = JSON.parse(output.string)
      expect(entry).not_to have_key('correlation_id')
    end
  end

  describe 'async output' do
    it 'writes log entries asynchronously' do
      async_logger = described_class.new(output: output, async: true, buffer_size: 10)

      async_logger.info('async message')
      async_logger.flush

      entry = JSON.parse(output.string.strip)
      expect(entry['message']).to eq('async message')

      async_logger.close
    end

    it 'flushes all buffered entries on close' do
      async_logger = described_class.new(output: output, async: true, buffer_size: 100)

      5.times { |i| async_logger.info("msg #{i}") }
      async_logger.close

      lines = output.string.strip.split("\n")
      expect(lines.size).to eq(5)
    end

    it 'handles backpressure by falling back to sync writes' do
      async_logger = described_class.new(output: output, async: true, buffer_size: 1)

      # Flood with messages to trigger backpressure
      20.times { async_logger.info('flood') }
      async_logger.close

      lines = output.string.strip.split("\n")
      expect(lines.size).to eq(20)
    end
  end

  describe '#flush' do
    it 'is available on sync loggers' do
      expect { logger.flush }.not_to raise_error
    end
  end

  describe '#close' do
    it 'is available on sync loggers' do
      expect { logger.close }.not_to raise_error
    end
  end
end

RSpec.describe Philiprehberger::StructuredLogger::Formatter do
  subject(:formatter) { described_class.new }

  it 'returns valid JSON' do
    result = formatter.call(:info, 'hello', {})

    expect { JSON.parse(result) }.not_to raise_error
  end

  it 'includes all base fields' do
    entry = JSON.parse(formatter.call(:warn, 'test', {}))

    expect(entry).to have_key('timestamp')
    expect(entry['level']).to eq('warn')
    expect(entry['message']).to eq('test')
  end

  it 'merges context into the entry' do
    entry = JSON.parse(formatter.call(:info, 'ctx', { user: 'alice' }))

    expect(entry['user']).to eq('alice')
  end
end

RSpec.describe Philiprehberger::StructuredLogger::TextFormatter do
  subject(:formatter) { described_class.new }

  it 'returns a human-readable text line' do
    result = formatter.call(:info, 'hello', {})

    expect(result).to include('INFO:')
    expect(result).to include('hello')
    expect(result).to match(/\[\d{4}-\d{2}-\d{2}/)
  end

  it 'includes context as key=value pairs' do
    result = formatter.call(:warn, 'test', { user: 'bob', count: 5 })

    expect(result).to include('user=bob')
    expect(result).to include('count=5')
  end

  it 'handles empty context' do
    result = formatter.call(:debug, 'plain', {})

    expect(result).to include('DEBUG:')
    expect(result).to include('plain')
  end
end

RSpec.describe Philiprehberger::StructuredLogger::AsyncWriter do
  subject(:writer) { described_class.new(output, buffer_size: 10) }

  let(:output) { StringIO.new }

  after do
    writer.close
  end

  it 'writes lines asynchronously' do
    writer.puts('hello')
    writer.flush

    expect(output.string.strip).to eq('hello')
  end

  it 'drains all entries on close' do
    3.times { |i| writer.puts("line #{i}") }
    writer.close

    lines = output.string.strip.split("\n")
    expect(lines.size).to eq(3)
  end
end

RSpec.describe Philiprehberger::StructuredLogger, '.resolve_formatter' do
  it 'returns a Formatter for nil' do
    result = described_class.resolve_formatter(nil)

    expect(result).to be_a(Philiprehberger::StructuredLogger::Formatter)
  end

  it 'returns a Formatter for :json' do
    result = described_class.resolve_formatter(:json)

    expect(result).to be_a(Philiprehberger::StructuredLogger::Formatter)
  end

  it 'returns a TextFormatter for :text' do
    result = described_class.resolve_formatter(:text)

    expect(result).to be_a(Philiprehberger::StructuredLogger::TextFormatter)
  end

  it 'returns a proc as-is' do
    proc = ->(level, message, _context) { "#{level}:#{message}" }
    result = described_class.resolve_formatter(proc)

    expect(result).to eq(proc)
  end

  it 'returns a callable object as-is' do
    obj = Object.new
    def obj.call(_level, _message, _context); end

    result = described_class.resolve_formatter(obj)

    expect(result).to eq(obj)
  end

  it 'raises for non-callable objects' do
    expect do
      described_class.resolve_formatter(42)
    end.to raise_error(ArgumentError, /Invalid formatter/)
  end
end
