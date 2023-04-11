# philiprehberger-structured_logger

[![Tests](https://github.com/philiprehberger/rb-structured-logger/actions/workflows/ci.yml/badge.svg)](https://github.com/philiprehberger/rb-structured-logger/actions/workflows/ci.yml)
[![Gem Version](https://badge.fury.io/rb/philiprehberger-structured_logger.svg)](https://rubygems.org/gems/philiprehberger-structured_logger)
[![Last updated](https://img.shields.io/github/last-commit/philiprehberger/rb-structured-logger)](https://github.com/philiprehberger/rb-structured-logger/commits/main)

Structured JSON logger with context and child loggers

## Requirements

- Ruby >= 3.1

## Installation

Add to your Gemfile:

```ruby
gem "philiprehberger-structured_logger"
```

Or install directly:

```bash
gem install philiprehberger-structured_logger
```

## Usage

```ruby
require "philiprehberger/structured_logger"

logger = Philiprehberger::StructuredLogger::Logger.new

logger.info("Server started", port: 3000)
# => {"timestamp":"2026-03-10T12:00:00.000Z","level":"info","message":"Server started","port":3000}
```

### Context

Pass base context that appears in every log entry:

```ruby
logger = Philiprehberger::StructuredLogger::Logger.new(context: { service: "api" })

logger.info("Request received", path: "/health")
# => {"timestamp":"...","level":"info","message":"Request received","service":"api","path":"/health"}
```

### Child Loggers

Create child loggers that inherit and extend the parent context:

```ruby
request_logger = logger.child(request_id: "abc-123")

request_logger.info("Processing")
# => {"timestamp":"...","level":"info","message":"Processing","service":"api","request_id":"abc-123"}
```

### Log Levels

Available levels: `debug`, `info`, `warn`, `error`, `fatal`.

```ruby
logger = Philiprehberger::StructuredLogger::Logger.new(level: :warn)

logger.info("ignored")   # not written
logger.warn("visible")   # written
logger.error("visible")  # written
```

Read the current level:

```ruby
logger.level  # => :debug
```

Change the level at runtime:

```ruby
logger.level = :error
```

### Temporary Context

Use `with_context` to add context for the duration of a block:

```ruby
logger.with_context(request_id: "abc-123") do
  logger.info("Processing request")
  # => {"timestamp":"...","level":"info","message":"Processing request","request_id":"abc-123"}
end
# Context is restored after the block
```

### Silence

Temporarily suppress log output by raising the minimum level:

```ruby
logger.silence(:fatal) do
  logger.info("suppressed")   # not written
  logger.error("suppressed")  # not written
end
# Level is restored after the block
```

### Exception Logging

Log exceptions with class, message, and backtrace:

```ruby
begin
  risky_operation
rescue => e
  logger.log_exception(e)
  # => {"timestamp":"...","level":"error","message":"something broke","error_class":"RuntimeError","backtrace":[...]}
end

# Custom level and extra context:
logger.log_exception(e, level: :fatal, user_id: 42)
```

### Multiple Outputs

Log to multiple destinations simultaneously. Each output can have its own level filter and formatter:

```ruby
logger = Philiprehberger::StructuredLogger::Logger.new(
  outputs: [$stdout, File.open("app.log", "a")]
)

# With per-output configuration:
logger = Philiprehberger::StructuredLogger::Logger.new(outputs: [
  { io: $stdout, formatter: :text },
  { io: File.open("app.log", "a"), formatter: :json },
  { io: $stderr, level: :error }
])
```

Add outputs at runtime:

```ruby
logger.add_output($stderr, level: :error)
logger.add_output(File.open("debug.log", "a"), formatter: :text)
```

The singular `output:` parameter still works for backwards compatibility:

```ruby
logger = Philiprehberger::StructuredLogger::Logger.new(output: $stdout)
```

### Custom Formatters

Choose from built-in formatters or provide your own:

```ruby
# JSON formatter (default)
logger = Philiprehberger::StructuredLogger::Logger.new(formatter: :json)

# Text formatter — human-readable output
logger = Philiprehberger::StructuredLogger::Logger.new(formatter: :text)
logger.info("hello", user: "alice")
# => [2026-03-10T12:00:00.000Z] INFO: hello user=alice

# Custom proc formatter
logger = Philiprehberger::StructuredLogger::Logger.new(
  formatter: ->(level, message, context) { "#{level.upcase} #{message}" }
)

# Any callable object
class MyFormatter
  def call(level, message, context)
    "#{level}|#{message}|#{context.to_json}"
  end
end

logger = Philiprehberger::StructuredLogger::Logger.new(formatter: MyFormatter.new)
```

### Log Sampling

Sample a percentage of logs per level to reduce volume:

```ruby
logger = Philiprehberger::StructuredLogger::Logger.new(
  sampling: { debug: 0.1, info: 0.5 }
)
```

- `1.0` means log everything (default for unspecified levels)
- `0.5` means log approximately 50%
- `0.0` means log nothing

### Correlation ID

Inject a correlation/request ID into all log entries within a block:

```ruby
logger.with_correlation_id("req-abc-123") do
  logger.info("processing")
  # => {"timestamp":"...","level":"info","message":"processing","correlation_id":"req-abc-123"}
end

# Auto-generate a UUID:
logger.with_correlation_id do
  logger.info("processing")
  # => {"timestamp":"...","level":"info","message":"processing","correlation_id":"550e8400-e29b-41d4-a716-446655440000"}
end
```

Correlation IDs nest correctly and are stored in Thread-local storage:

```ruby
logger.with_correlation_id("outer") do
  logger.with_correlation_id("inner") do
    logger.info("nested")  # correlation_id: "inner"
  end
  logger.info("back")      # correlation_id: "outer"
end
```

### Async Output

Enable non-blocking log writes via a background thread:

```ruby
logger = Philiprehberger::StructuredLogger::Logger.new(async: true, buffer_size: 100)

logger.info("non-blocking")

# Force immediate write of buffered entries:
logger.flush

# Flush and stop the background thread:
logger.close
```

When the buffer is full, writes fall back to synchronous mode (backpressure) to avoid dropping log entries.

## API

### `Philiprehberger::StructuredLogger::Logger`

| Method | Description |
|---|---|
| `new(output: $stdout, outputs: nil, level: :debug, context: {}, formatter: nil, sampling: {}, async: false, buffer_size: 1000)` | Create a logger |
| `debug(message, **extra)` | Log at debug level |
| `info(message, **extra)` | Log at info level |
| `warn(message, **extra)` | Log at warn level |
| `error(message, **extra)` | Log at error level |
| `fatal(message, **extra)` | Log at fatal level |
| `child(**context)` | Create a child logger with merged context |
| `level` | Get the current log level |
| `level=(new_level)` | Set the minimum log level |
| `with_context(**extra, &block)` | Temporarily merge context for a block |
| `silence(level = :fatal, &block)` | Temporarily raise log level for a block |
| `log_exception(exception, level: :error, **extra)` | Log exception details |
| `add_output(io, level: nil, formatter: nil)` | Add an output destination at runtime |
| `with_correlation_id(id = nil, &block)` | Set a correlation ID for the block |
| `flush` | Force write of all buffered log entries |
| `close` | Flush and stop async background threads |

### `Philiprehberger::StructuredLogger::Formatter`

| Method | Description |
|---|---|
| `call(level, message, context)` | Build a JSON log string |

### `Philiprehberger::StructuredLogger::TextFormatter`

| Method | Description |
|---|---|
| `call(level, message, context)` | Build a human-readable text log string |

### `Philiprehberger::StructuredLogger::AsyncWriter`

| Method | Description |
|---|---|
| `new(output, buffer_size: 1000)` | Create an async writer wrapping an IO |
| `puts(line)` | Enqueue a line for async writing |
| `flush` | Force write of buffered entries |
| `close` | Flush and stop the background thread |

## Development

```bash
bundle install
bundle exec rspec
bundle exec rubocop
```

## Support

If you find this project useful:

⭐ [Star the repo](https://github.com/philiprehberger/rb-structured-logger)

🐛 [Report issues](https://github.com/philiprehberger/rb-structured-logger/issues?q=is%3Aissue+is%3Aopen+label%3Abug)

💡 [Suggest features](https://github.com/philiprehberger/rb-structured-logger/issues?q=is%3Aissue+is%3Aopen+label%3Aenhancement)

❤️ [Sponsor development](https://github.com/sponsors/philiprehberger)

🌐 [All Open Source Projects](https://philiprehberger.com/open-source-packages)

💻 [GitHub Profile](https://github.com/philiprehberger)

🔗 [LinkedIn Profile](https://www.linkedin.com/in/philiprehberger)

## License

[MIT](LICENSE)
