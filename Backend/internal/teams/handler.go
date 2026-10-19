package teams

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

	router.Get("/", h.ListByOrg)
	router.Post("/", h.Create)
	router.Get("/{id}", h.GetByID)
	router.Get("/slug/{slug}", h.GetBySlug)
	router.Patch("/{id}", h.Update)

	return router
}

// handles GET /api/v1/teams?org_id={org_id}
func (h *Handler) ListByOrg(w http.ResponseWriter, r *http.Request) {
	slog.Info("Listing all teams by organization")

	orgID, err := uuid.Parse(r.URL.Query().Get("org_id"))
	if err != nil {
		slog.Error("org_id query param is required")
		httputil.RespondError(w, http.StatusBadRequest, "ord_id query param is required and must be valid UUID")
		return
	}

	limit, offset, page := httputil.ParsePagination(r)

	// Get total teams
	total, err := h.queries.CountTeamsByOrg(r.Context(), orgID)
	if err != nil {
		slog.Error("Failed to count teams", "error", err, "org_id", orgID)
		httputil.RespondError(w, http.StatusInternalServerError, "failed to list teams")
		return
	}

	teams, err := h.queries.ListTeamsByOrg(r.Context(), database.ListTeamsByOrgParams{
		OrganizationID: 	orgID,
		Limit: 				limit,
		Offset: 			offset,
	})
	if err != nil {
		slog.Error("Failed to fetch teams data", "error", err, "org_id", orgID)
		httputil.RespondError(w, http.StatusInternalServerError, "failed to fetch teams")
		return
	}

	slog.Info("Successfully fetched teams by organization")
	httputil.RespondPaginatedJSON(w, http.StatusOK, teams, total, page, limit)
}

// handles POST /api/v1/teams
func (h *Handler) Create(w http.ResponseWriter, r *http.Request) {
	slog.Info("Creating new team entry in database...")

	var req CreateTeamRequest
	if err := httputil.DecodeJSON(r, &req); err != nil {
		slog.Error("Failed to decode request object")
		httputil.RespondError(w, http.StatusBadRequest, err.Error())
		return
	}

	if err := req.Validate(); err != nil {
		slog.Error("Failed to validate request object")
		httputil.RespondError(w, http.StatusBadRequest, err.Error())
		return
	}

	params := database.CreateTeamParams{
		OrganizationID: 	req.OrganizationID,
		Name: 				req.Name,
		Slug: 				req.Slug,
		IdpGroupPath: 		req.IDPGroupPath,
	}

	team, err := h.queries.CreateTeam(r.Context(), params)
	if err != nil {
		var pgErr *pgconn.PgError
		if errors.As(err, &pgErr) && pgErr.Code == "23505" {
			slog.Error("Team slug already exists", "slug", req.Slug)
			httputil.RespondError(w, http.StatusConflict, "Team slug already exists within this organization")
			return
		}

		slog.Error("Failed to create team", "error", err)
		httputil.RespondError(w, http.StatusInternalServerError, "Failed to create team")
		return
	}

	slog.Info("Successfully created team")
	httputil.RespondJSON(w, http.StatusCreated, team)
}

// handles GET /api/v1/teams/{id}?org_id={org_id}
func (h *Handler) GetByID(w http.ResponseWriter, r *http.Request) {
	slog.Info("Fetching team info by ID")

	id, err := uuid.Parse(chi.URLParam(r, "id"))
	if err != nil {
		slog.Error("Invalid ID provided")
		httputil.RespondError(w, http.StatusBadRequest, "invalid team id provided")
		return
	}

	orgID, err := uuid.Parse(r.URL.Query().Get("org_id"))
	if err != nil {
		slog.Error("Invalid Organization ID provided")
		httputil.RespondError(w, http.StatusBadRequest, "invalid organization id provided")
		return
	}

	team, err := h.queries.GetTeamByID(r.Context(), database.GetTeamByIDParams{
		OrganizationID: 	orgID,
		ID: 				id,
	})
	if err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			httputil.RespondError(w, http.StatusNotFound, "team not found")
			return
		}

		slog.Error("Failed to fetch team details by id", "error", err, "team_id", id)
		httputil.RespondError(w, http.StatusInternalServerError, "Failed to fetch team data")
		return
	}

	slog.Info("Successfully fetched team info by ID")
	httputil.RespondJSON(w, http.StatusOK, team)
}

// handles GET /api/v1/teams/slug/{slug}?org_id={org_id}
func (h *Handler) GetBySlug(w http.ResponseWriter, r *http.Request) {
	slog.Info("Fetching team info by Slug")

	orgID, err := uuid.Parse(r.URL.Query().Get("org_id"))
	if err != nil {
		slog.Error("Invalid Organization ID provided")
		httputil.RespondError(w, http.StatusBadRequest, "invalid organization id provided")
		return
	}

	slug := chi.URLParam(r, "slug")

	team, err := h.queries.GetTeamBySlug(r.Context(), database.GetTeamBySlugParams{
		OrganizationID: 	orgID,
		Slug: 				slug,
	})
	if err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			httputil.RespondError(w, http.StatusNotFound, "team not found")
			return
		}

		slog.Error("Failed to fetch team details by slug", "error", err, "org_id", orgID, "slug", slug)
		httputil.RespondError(w, http.StatusInternalServerError, "Failed to fetch team info by slug")
		return
	}

	slog.Info("Successfully fetched the team details by slug")
	httputil.RespondJSON(w, http.StatusOK, team)
}

// handles PATCH /api/v1/teams/{id}?org_id={org_id}
func (h *Handler) Update(w http.ResponseWriter, r *http.Request) {
	slog.Info("Updating team info by ID")

	id, err := uuid.Parse(chi.URLParam(r, "id"))
	if err != nil {
		slog.Error("Invalid team id provided")
		httputil.RespondError(w, http.StatusBadRequest, "Invalid team id provided")
		return
	}

	orgID, err := uuid.Parse(r.URL.Query().Get("org_id"))
	if err != nil {
		slog.Error("Invalid organization ID provided")
		httputil.RespondError(w, http.StatusBadRequest, "Invalid organization id provided")
		return
	}

	var req UpdateTeamRequest
	if err := httputil.DecodeJSON(r, &req); err != nil {
		slog.Error("Failed to decode update request", "error", err)
		httputil.RespondError(w, http.StatusBadRequest, err.Error())
		return
	}

	if err := req.Validate(); err != nil {
		slog.Error("Failed to validate request object", "error", err)
		httputil.RespondError(w, http.StatusBadRequest, err.Error())
		return
	}

	params := database.UpdateTeamParams{
		ID: 			id,
		Name: 			req.Name,
		OrganizationID: orgID,
		IdpGroupPath: 	req.IDPGroupPath,
	}

	team, err := h.queries.UpdateTeam(r.Context(), params)
	if err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			httputil.RespondError(w, http.StatusNotFound, "team not found in this organization")
			return
		}

		slog.Error("Failed to update team details", "error", err)
		httputil.RespondError(w, http.StatusInternalServerError, "Failed to update team details")
		return
	}

	slog.Info("Successfully updated the team details")
	httputil.RespondJSON(w, http.StatusOK, team)
}
