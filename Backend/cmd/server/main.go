package main

import (
	"os"
	"log/slog"

	"pagetrack-backend/internal/platform/database"
	"pagetrack-backend/pkg/config"
	"pagetrack-backend/pkg/logger"
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

	slog.Info("Server booting...",
		"env", cfg.Env,
		"port", cfg.Port,
		"log_level", cfg.LogLevel,
		"log_path", cfg.LogPath,
	)

	// Initialize database connection pool
	ctx := context.Background()
	pool, err := database.NewPool(ctx, cfg)
	if err != nil {
		slog.Error("Failed to connect to database", "error", err)
		os.Exit(1)
	}
	defer pool.Close()

	slog.Info("Database connection pool established",
		"max_conns", cfg.DBMaxConns,
		"min_conns", cfg.DBMinConns,
	)
}