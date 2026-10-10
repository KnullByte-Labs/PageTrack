package httputil

import (
	"io"
	"errors"
	"net/http"
	"encoding/json"
)

type ErrorResponse struct {
	Error string				`json:"error"`
	Details map[string]string 	`json:"details,omitempty"`
}

// Write a JSON response with given status code
func RespondJSON(w http.ResponseWriter, status int, data any) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	if data != nil {
		_ = json.NewEncoder(w).Encode(data)
	}
}

// Write a JSON error response
func RespondError(w http.ResponseWriter, status int, message string) {
	RespondJSON(w, status, ErrorResponse{Error: message})
}

// Decode request body to target struct, rejecting unknown fields
func DecodeJSON(r *http.Request, target any) error {
	if r.Body == nil {
		return errors.New("request body cannot be emtpy")
	}
	defer r.Body.Close()

	decoder := json.NewDecoder(r.Body)
	decoder.DisallowUnknownFields()

	if err := decoder.Decode(target); err != nil {
		if errors.Is(err, io.EOF) {
			return errors.New("request body cannot be empty")
		}
		return err
	}

	return nil
}
