package organizations

import (
	"errors"
	"log/slog"
	"net/http"
	
	"github.com/go-chi/chi/v5"
	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgconn"

	"pagetrack-backend/internal/platform/database"
	"pagetrack-backend/pkg/httputil"
)

type Handler struct {
	// Reuse the instance with Shared pgxpool.Pool
	queries database.Querier
}

// Inject the shared queries instance
func NewHandler(queries database.Querier) *Handler {
	return &Handler{
		queries: queries,
	}
}

// Routes registers organization endpoints on a dedicated chi router
func (h *Handler) Routes() chi.Router {
	router := chi.NewRouter()

	router.Get("/", h.List)
	router.Post("/", h.Create)
	router.Get("/{id}", h.GetByID)
	router.Get("/slug/{slug}", h.GetBySlug)
	router.Patch("/{id}", h.Update)

	return router
}

// handles GET /api/v1/organizations
func (h *Handler) List(w http.ResponseWriter, r *http.Request) {
	slog.Info("Fetching all organizations...")

	limit, offset, page := httputil.ParsePagination(r)

	total, err := h.queries.CountOrganizations(r.Context())
	if err != nil {
		slog.Error("Failed to count organizations", "error", err)
		httputil.RespondError(w, http.StatusInternalServerError, "failed to list organizations")
		return
	}

	orgs, err := h.queries.ListOrganizations(r.Context(), database.ListOrganizationsParams{
		Limit: limit,
		Offset: offset,
	})
	if err != nil {
		slog.Error("Failed to list organizations", "error", err)
		httputil.RespondError(w, http.StatusInternalServerError, "failed to list organizations")
		return
	}

	slog.Info("Fetched all organization info")
	httputil.RespondPaginatedJSON(w, http.StatusOK, orgs, total, page, limit)
}

// handles POST /api/v1/organizations
func (h *Handler) Create(w http.ResponseWriter, r *http.Request) {
	slog.Info("Creating New Organization...")

	var req CreateOrganizationRequest

	// Decode request for expected format
	if err := httputil.DecodeJSON(r, &req); err != nil {
		slog.Warn("Failed to decode organization payload", "error", err)
		httputil.RespondError(w, http.StatusBadRequest, err.Error())
		return
	}

	// Validate request has the required data
	if err := req.Validate(); err != nil {
		httputil.RespondError(w, http.StatusBadRequest, err.Error())
		return
	}

	params := database.CreateOrganizationParams{
		Slug:			req.Slug,
		Name: 			req.Name,
		DisplayName:	req.DisplayName,
		ImageUrl: 		req.ImageUrl,
		LiveUrl: 		req.LiveUrl,
		Description: 	req.Description,
	}

	org, err := h.queries.CreateOrganization(r.Context(), params) 

	if err != nil {
		var pgErr *pgconn.PgError

		// Check for slug duplication
		if errors.As(err, &pgErr) && pgErr.Code == "23505" {
			slog.Warn("organization slug collision", "slug", req.Slug)
			httputil.RespondError(w, http.StatusConflict, "an organization with this slug already exists")
			return
		}

		slog.Error("Failed to create organization", "error", err, "slug", req.Slug)
		httputil.RespondError(w, http.StatusInternalServerError, "failed to create organization")
		return
	}

	slog.Info("Organization created", "id", org.ID, "slug", org.Slug)
	httputil.RespondJSON(w, http.StatusCreated, org)
}

// handles GET /api/v1/organizations/{id}
func (h *Handler) GetByID(w http.ResponseWriter, r *http.Request) {
	id, err := uuid.Parse(chi.URLParam(r, "id"))
	if err != nil {
		httputil.RespondError(w, http.StatusBadRequest, "invalid organization id")
		return
	}

	org, err := h.queries.GetOrganizationByID(r.Context(), id)
	if err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			httputil.RespondError(w, http.StatusNotFound, "organization not found")
			return
		}

		slog.Error("Failed to fetch organization", "error", err, "id", id)
		httputil.RespondError(w, http.StatusInternalServerError, "failed to fetch organization")
		return
	}

	slog.Info("Found organzation by ID", "id", id)
	httputil.RespondJSON(w, http.StatusOK, org)
}

// handles GET /api/v1/organizations/slug/{slug}
func (h *Handler) GetBySlug(w http.ResponseWriter, r *http.Request) {
	slug := chi.URLParam(r, "slug")

	org, err := h.queries.GetOrganizationBySlug(r.Context(), slug)
	if err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			httputil.RespondError(w, http.StatusNotFound, "organization not found")
			return
		}

		slog.Error("Failed to fetch organization by slug", "error", err, "slug", slug)
		httputil.RespondError(w, http.StatusInternalServerError, "failed to fetch organization")
		return
	}

	slog.Info("Found organization by slug", "slug", slug)
	httputil.RespondJSON(w, http.StatusOK, org)
}

// handles PATCH /api/v1/organizations/{id}
func (h *Handler) Update(w http.ResponseWriter, r *http.Request) {
	id, err := uuid.Parse(chi.URLParam(r, "id"))
	if err != nil {
		httputil.RespondError(w, http.StatusBadRequest, "invalid organization id")
		return
	}

	var req UpdateOrganizationRequest
	if err := httputil.DecodeJSON(r, &req); err != nil {
		httputil.RespondError(w, http.StatusBadRequest, err.Error())
		return
	}

	if err := req.Validate(); err != nil {
		httputil.RespondError(w, http.StatusBadRequest, err.Error())
		return
	}
	
	params := database.UpdateOrganizationParams{
		ID:          id,
		Name:        req.Name,
		DisplayName: req.DisplayName,
		ImageUrl:    req.ImageUrl,
		LiveUrl:     req.LiveUrl,
		Description: req.Description,
	}

	org, err := h.queries.UpdateOrganization(r.Context(), params)
	if err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			httputil.RespondError(w, http.StatusNotFound, "organization not found")
			return
		}

		slog.Error("Failed to update organization details", "error", err, "id", id)
		httputil.RespondError(w, http.StatusInternalServerError, "failed to update organization")
		return
	}

	httputil.RespondJSON(w, http.StatusOK, org)
}
