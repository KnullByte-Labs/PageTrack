package database

import (
	"context"
	"fmt"
	"time"

	"github.com/jackc/pgx/v5/pgxpool"

	"pagetrack-backend/pkg/config"
)

// Initialize and validate a new PostgreSQL connection pool
func NewPool(ctx context.Context, cfg *config.Config) (*pgxpool.Pool, error) {
	connStr := cfg.DSN()
	poolCfg, err := pgxpool.ParseConfig(connStr)

	if err != nil {
		return nil, fmt.Errorf("failed to parse database configuration: %w", err)
	}

	poolCfg.MaxConns = int32(cfg.DBMaxConns)
	poolCfg.MinConns = int32(cfg.DBMinConns)
	poolCfg.MaxConnLifetime = 1 * time.Hour
	poolCfg.MaxConnIdleTime = 30 * time.Minute
	poolCfg.HealthCheckPeriod = 1 * time.Minute

	pool, err := pgxpool.NewWithConfig(ctx, poolCfg)
	if err != nil {
		return nil, fmt.Errorf("failed to create connection pool: %w", err)
	}

	// Verify database connection
	pingCtx, cancel := context.WithTimeout(ctx, 5*time.Second)
	defer cancel()

	if err := pool.Ping(pingCtx); err != nil {
		pool.Close()
		return nil, fmt.Errorf("failed to ping database %w", err)
	}

	return pool, nil
}