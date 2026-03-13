# Changelog

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
