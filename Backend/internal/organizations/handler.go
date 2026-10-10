package organizations

import (
	"errors"
	"log/slog"
	"net/http"
	
	"github.com/go-chi/chi/v5"
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

	return router
}

// handles GET /api/v1/organizations
func (h *Handler) List(w http.ResponseWriter, r *http.Request) {
	slog.Info("Fetching all organizations...")

	orgs, err := h.queries.ListOrganizations(r.Context())
	if err != nil {
		slog.Error("Failed to list organizations", "error", err)
		httputil.RespondError(w, http.StatusInternalServerError, "failed to list organizations")
		return
	}

	if orgs == nil {
		orgs = []database.ListOrganizationsRow{}
	}

	slog.Info("Fetched all organization info")
	httputil.RespondJSON(w, http.StatusOK, orgs)
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