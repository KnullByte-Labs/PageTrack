package logger

import (
	"io"
	"os"
	"strings"
	"log/slog"
	"path/filepath"

	"pagetrack-backend/pkg/config"
)

// Configure Go's global default structured logger.
// Call this once at application startup in main.go
func Init() (func(), error) {
	cfg := config.Get()

	// Get log level
	var level slog.Level

	switch strings.ToUpper(cfg.LogLevel) {
		case "DEBUG":
			level = slog.LevelDebug
		case "WARN":
			level = slog.LevelWarn
		case "ERROR":
			level = slog.LevelError
		default:
			level = slog.LevelInfo
	}

	// Resolve output target
	var output io.Writer = os.Stdout
	var cleanup = func() {}

	if cfg.LogPath != "" {
		if err := os.MkdirAll(filepath.Dir(cfg.LogPath), 0755); err != nil {
			return nil, err
		}

		file, err := os.OpenFile(cfg.LogPath, os.O_CREATE|os.O_WRONLY|os.O_APPEND, 0644)
		if err != nil {
			return nil, err
		}

		// Write to stdout and file
		output = io.MultiWriter(os.Stdout, file)
		cleanup = func() {
			_ = file.Sync()
			_ = file.Close()
		}
	}

	// Handler Options
	opts := &slog.HandlerOptions{
		Level: level,
		AddSource: true,
		ReplaceAttr: func(_ []string, a slog.Attr) slog.Attr {
			if a.Key == slog.SourceKey {
				if src, ok := a.Value.Any().(*slog.Source); ok && src != nil {
					dir := filepath.Base(filepath.Dir(src.File))
					src.File = filepath.Join(dir, filepath.Base(src.File))
				}
			}
			return a
		},
	}

	// Resolve handler format (JSON vs TEXT)
	var handler slog.Handler
	if strings.EqualFold(cfg.LogFormat, "TEXT") {
		handler = slog.NewTextHandler(output, opts)
	} else {
		handler = slog.NewJSONHandler(output, opts)
	}

	slog.SetDefault(slog.New(handler))
	return cleanup, nil
}