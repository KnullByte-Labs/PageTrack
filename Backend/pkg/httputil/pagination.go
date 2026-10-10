package httputil

import (
	"strconv"
	"net/http"
)

type Pagination struct {
	Page 		int32 `json:"page"`
	Limit 		int32 `json:"limit"`
	Total 		int64 `json:"total"`
	TotalPages	int32 `json:"totalPages"`
}

type PaginatedResponse[T any] struct {
	Data 		[]T 		`json:"data"`
	Pagination 	Pagination 	`json:"pagination"`
}

func ParsePagination(r *http.Request) (limit, offset, page int32) {
	return ParsePaginationWithDefault(r, 20, 100)
}

// Allows custom default and max limits per endpoint
func ParsePaginationWithDefault(r *http.Request, defaultLimit, maxLimit int32) (limit, offset, page int32) {
	pageInt, _ := strconv.Atoi(r.URL.Query().Get("page"))
	if pageInt < 1 {
		pageInt = 1
	}

	limitInt, _ := strconv.Atoi(r.URL.Query().Get("limit"))
	if limitInt < 1 {
		limitInt = int(defaultLimit)
	} else if limitInt > 100 {
		limitInt = int(maxLimit)
	}

	page = int32(pageInt)
	limit = int32(limitInt)
	offset = (page - 1) * limit

	return
}

// Build a PaginatedResponse, ensure nil serializes as []
func NewPaginatedResponse[T any](data []T, total int64, page, limit int32) PaginatedResponse[T] {
	if data == nil {
		data = []T{}
	}

	var totalPages int32
	if limit > 0 {
		totalPages = int32((total + int64(limit) - 1) / int64(limit))
	}

	return PaginatedResponse[T]{
		Data: data,
		Pagination: Pagination{
			Page: 		page,
			Limit: 		limit,
			Total: 		total,
			TotalPages: totalPages,
		},
	}
}

// Write a paginated JSON response
func RespondPaginatedJSON[T any](w http.ResponseWriter, status int, data[]T, total int64, page, limit int32) {
	RespondJSON(w, status, NewPaginatedResponse(data, total, page, limit))
}
