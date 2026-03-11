# Philiprehberger::StructuredLogger

A zero-dependency Ruby gem for structured JSON logging with context merging, child loggers, level filtering, and pluggable outputs.

## Installation

Add to your Gemfile:

```ruby
gem "philiprehberger-structured_logger"
```

Or install directly:

```sh
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

Change the level at runtime:

```ruby
logger.level = :error
```

### Custom Output

Pass any IO-like object that responds to `puts`:

```ruby
file = File.open("app.log", "a")
logger = Philiprehberger::StructuredLogger::Logger.new(output: file)
```

## API

### `Philiprehberger::StructuredLogger::Logger`

| Method | Description |
|---|---|
| `new(output: $stdout, level: :debug, context: {})` | Create a logger |
| `debug(message, **extra)` | Log at debug level |
| `info(message, **extra)` | Log at info level |
| `warn(message, **extra)` | Log at warn level |
| `error(message, **extra)` | Log at error level |
| `fatal(message, **extra)` | Log at fatal level |
| `child(**context)` | Create a child logger with merged context |
| `level=(new_level)` | Set the minimum log level |

### `Philiprehberger::StructuredLogger::Formatter`

| Method | Description |
|---|---|
| `call(level, message, context)` | Build a JSON log string |

## License

MIT
