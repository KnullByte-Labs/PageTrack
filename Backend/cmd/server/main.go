package main

import (
	"log/slog"

	"Backend/pkg/config"
	"Backend/pkg/logger"
)

func main() {
	// Load the configuration from .env file
	cfg, err := config.Load(".env")
	if err != nil {
		slog.Error("Failed to load configuration", "error", err)
		os.Exit(1)
	}

	// initialize the logger
	cleanup, err := logger.Init()
	if err != nil {
		slog.Error("Failed to initialize the logger", "error", err)
		os.Exit(1)
	}
	defer cleanup()

	slog.Info(
		"Server booting...",
		"env": cfg.Env,
		"port": cfg.Port,
		"log_level": cfg.LogLevel,
		"log_path": cfg.LogPath
	)
}