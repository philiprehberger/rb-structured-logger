# Changelog

## 0.3.0

- Add multiple outputs (appenders) with per-output level filtering and formatters
- Add `add_output` for adding output destinations at runtime
- Add custom formatters: `:json` (default), `:text`, and any callable (proc/lambda)
- Add `TextFormatter` for human-readable `[TIMESTAMP] LEVEL: message key=value` output
- Add log sampling with configurable rates per level
- Add `with_correlation_id` for injecting correlation/request IDs via Thread-local storage
- Add buffered async output via background thread with backpressure support
- Add `flush` and `close` methods for async writer lifecycle management

## 0.2.1

- Add License badge to README
- Add bug_tracker_uri to gemspec
- Add Development section to README
- Add Requirements section to README

## [0.2.0] - 2026-03-13
- Add `level` getter to read the current log level
- Add `with_context` for temporarily merging context during a block
- Add `silence` for temporarily raising the log level during a block
- Add `log_exception` for logging exception class, message, and backtrace

## [0.1.0] - 2026-03-10
- Initial release
- Structured JSON log output
- Log levels: debug, info, warn, error, fatal
- Context merging and child loggers
- Pluggable output
