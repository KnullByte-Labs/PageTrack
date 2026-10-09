package config

import (
	"os"
	"fmt"
	"sync"
	"time"
	"bufio"
	"reflect"
	"strings"
	"strconv"
)

// Config holds all platform environment settings
type Config struct {
	// Application & Environment
	Env string `env:"APP_ENV" default:"development"`
	Port int `env:"PORT" default:"8080"`

	// Logging configuration
	LogLevel string `env:"LOG_LEVEL" default:"INFO"`  // DEBUG, INFO, WARN, ERROR
	LogFormat string `env:"LOG_FORMAT" default:"JSON"` // TEXT or JSON
	LogPath string `env:"LOG_PATH" default:""`  // Empty = stdout only

	// PostgreSQL / Multi-Tenancy (RLS)
	DatabaseUser string `env:"DATABASE_USER" default:"postgres"`
	DatabasePass string `env:"DATABASE_PASS" default:"postgres"`
	DatabaseName string `env:"DATABASE_NAME" default:"postgres"`
	DatabaseURL string `env:"DATABASE_URL" default:"localhost:5432"`
	DBMaxConns int `env:"DB_MAX_CONNS" default:"25"`
	DBMinConns int `env:"DB_MIN_CONNS" default:"5"`

	// Graceful shutdown
	ShutdownTimeout time.Duration `env:"SHUTDOWN_TIMEOUT" default:"10s"`
}

var (
	instance *Config
	once	  sync.Once
)

// Returns the loaded configuration singleton
func Get() *Config {
	once.Do(func() {
		cfg := &Config{}
		if err := parseStruct(cfg); err != nil {
			panic(fmt.Sprintf("failed to parse config from environment: %v", err))
		}
		instance = cfg
	})
	return instance
}

// Loads an optional .env file and initializes the config
func Load(envFile string) (*Config, error) {
	if envFile != "" {
		_ = loadDotEnv(envFile) // continues gracefully if file not found
	}
	cfg := Get()
	return cfg, cfg.validate()
}

// Check if env is Dev
func (c *Config) IsDevelopment() bool {
	return strings.EqualFold(c.Env, "development") || strings.EqualFold(c.Env, "dev")
}

// validate config returns error
func (c *Config) validate() error {
	return nil
}

// populates the struct field using env and default tags
func parseStruct(target any) error {
	v := reflect.ValueOf(target)
	if v.Kind() != reflect.Pointer || v.Elem().Kind() != reflect.Struct {
		return fmt.Errorf("target must be a pointer to a struct")
	}

	elem := v.Elem()
	elemType := elem.Type()

	for i := 0; i < elem.NumField(); i++ {
		field := elem.Field(i)
		fieldType := elemType.Field(i)

		// immutable field type
		if !field.CanSet() {
			continue
		}

		// env key not provided in struct definition
		envKey := fieldType.Tag.Get("env")
		if envKey == "" {
			continue
		}

		// fetch from os environment or fallback to default tag
		valStr, exists := os.LookupEnv(envKey)
		if !exists || strings.TrimSpace(valStr) == "" {
			valStr = fieldType.Tag.Get("default")
		}

		valStr = strings.TrimSpace(valStr)

		// Check if value matches the field type
		if err := setFieldValue(field, valStr); err != nil {
			return fmt.Errorf("field %s (%s): %w", fieldType.Name, envKey, err)
		}
	}

	return nil
}

// Set the parse values of default config after type checking
func setFieldValue(field reflect.Value, raw string) error {
	if field.Type() == reflect.TypeOf(time.Duration(0)) {
		d, err := time.ParseDuration(raw)
		if err != nil {
			return fmt.Errorf("invalid duration %q: %w", raw, err)
		}

		field.Set(reflect.ValueOf(d))
		return nil
	}

	switch field.Kind() {
		case reflect.String:
			field.SetString(raw)
		case reflect.Int, reflect.Int8, reflect.Int16, reflect.Int32, reflect.Int64:
			intVal, err := strconv.ParseInt(raw, 10, 64)
			if err != nil {
				return fmt.Errorf("invalid int %q: %w", raw, err)
			}
			field.SetInt(intVal)
		case reflect.Uint, reflect.Uint8, reflect.Uint16, reflect.Uint32, reflect.Uint64:
			uintVal, err := strconv.ParseUint(raw, 10, 64)
			if err != nil {
				return fmt.Errorf("invalid uint %q: %w", raw, err)
			}
			field.SetUint(uintVal)
		case reflect.Bool:
			boolVal, err := strconv.ParseBool(raw)
			if err != nil {
				return fmt.Errorf("invalid bool %q: %w", raw, err)
			}
			field.SetBool(boolVal)
		case reflect.Float32, reflect.Float64:
			floatVal, err := strconv.ParseFloat(raw, 64)
			if err != nil {
				return fmt.Errorf("invalid float %q: %w", raw, err)
			}
			field.SetFloat(floatVal)
		default:
			return fmt.Errorf("unsupported type %s", field.Type().String())
	}

	return nil
}

// Load the environment info from .env file
func loadDotEnv(filepath string) error {
	file, err := os.Open(filepath)
	if err != nil {
		return err
	}
	defer file.Close()

	scanner := bufio.NewScanner(file)
	for scanner.Scan() {
		line := strings.TrimSpace(scanner.Text())
		if line == "" || strings.HasPrefix(line, "#") {
			continue
		}

		parts := strings.SplitN(line, "=", 2)
		if len(parts) == 2 {
			key := strings.TrimSpace(parts[0])
			val := strings.TrimSpace(parts[1])

			val = strings.Trim(val, `"'`) // Remove quotations

			if _, exists := os.LookupEnv(key); !exists {
				_ = os.Setenv(key, val)
			}
		}
	}

	return scanner.Err()
}

// Generate the database connection string
func (c *Config) DSN() string {
	if strings.HasPrefix(c.DatabaseURL, "postgres://") || strings.HasPrefix(c.DatabaseURL, "postgresql://") {
		return c.DatabaseURL
	}

	return fmt.Sprintf("postges://%s:%s@%s/%s?sslmode=disable", c.DatabaseUser, c.DatabasePass, c.DatabaseURL, c.DatabaseName)
}