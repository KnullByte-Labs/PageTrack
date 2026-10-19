package projects

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

// handles GET /api/v1/projects?org_id={org_id}
func (h *Handler) ListByOrg(w http.ResponseWriter, r *http.Request) {
	slog.Info("Listing all projects by organization")

	orgID, err := uuid.Parse(r.URL.Query().Get("org_id"))
	if err != nil {
		slog.Error("org_id query param is required")
		httputil.RespondError(w, http.StatusBadRequest, "ord_id query param is required and must be valid UUID")
		return
	}

	limit, offset, page := httputil.ParsePagination(r)

	// Get total projects
	total, err := h.queries.CountProjectsByOrg(r.Context(), orgID)
	if err != nil {
		slog.Error("Failed to count projects", "error", err, "org_id", orgID)
		httputil.RespondError(w, http.StatusInternalServerError, "Failed to count projects")
		return
	}

	projects, err := h.queries.ListProjectsByOrg(r.Context(), database.ListProjectsByOrgParams{
		OrganizationID: 	orgID,
		Limit: 				limit,
		Offset: 			offset,
	})
	if err != nil {
		slog.Error("Failed to fetch projects data", "error", err, "org_id", orgID)
		httputil.RespondError(w, http.StatusInternalServerError, "Failed to fetch projects")
		return
	}
	
	slog.Info("Successfully fetched projects by organization", "count", len(projects), "total", total)
	httputil.RespondPaginatedJSON(w, http.StatusOK, projects, total, page, limit)
}

// handles POST /api/v1/projects
func (h *Handler) Create(w http.ResponseWriter, r *http.Request) {
	slog.Info("Creating new project entry in database...")

	var req CreateProjectRequest
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

	params := database.CreateProjectParams{
		OrganizationID: 		req.OrganizationID,
		TeamID: 				req.TeamID,
		Name: 					req.Name,
		Slug: 					req.Slug,
		Description: 			req.Description,
		Visibility: 			req.Visibility,
	}

	project, err := h.queries.CreateProject(r.Context(), params)
	if err != nil {
		var pgErr *pgconn.PgError
		if errors.As(err, &pgErr) && pgErr.Code == "23505" {
			slog.Error("Project already exists in this organization", "slug", req.Slug, "name", req.Name)
			httputil.RespondError(w, http.StatusConflict, "Project already exists in this organization")
			return
		}

		slog.Error("Failed to create project", "error", err)
		httputil.RespondError(w, http.StatusInternalServerError, "Failed to create project")
		return
	}

	slog.Info("Successfully created an entry for project in database")
	httputil.RespondJSON(w, http.StatusCreated, project)
}

// handles GET /api/v1/projects/{id}?org_id={org_id}
func (h *Handler) GetByID(w http.ResponseWriter, r *http.Request) {
	slog.Info("Fetching project by ID")

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

	project, err := h.queries.GetProjectByID(r.Context(), database.GetProjectByIDParams{
		ID: 					id,
		OrganizationID: 		orgID,
	})
	if err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			httputil.RespondError(w, http.StatusNotFound, "Project not found")
			return
		}

		slog.Error("Failed to fetch project details by id", "error", err, "org_id", orgID, "project_id", id)
		httputil.RespondError(w, http.StatusInternalServerError, "Failed to fetch project")
		return
	}

	slog.Info("Successfully fetched project by ID")
	httputil.RespondJSON(w, http.StatusOK, project)
}

// handles GET /api/v1/projects/slug/{slug}?org_id={org_id}
func (h *Handler) GetBySlug(w http.ResponseWriter, r *http.Request) {
	slog.Info("Fetching project by slug")

	orgID, err := uuid.Parse(r.URL.Query().Get("org_id"))
	if err != nil {
		slog.Error("Invalid Organization ID provided")
		httputil.RespondError(w, http.StatusBadRequest, "invalid organization id provided")
		return
	}

	slug := chi.URLParam(r, "slug")

	project, err := h.queries.GetProjectBySlug(r.Context(), database.GetProjectBySlugParams{
		OrganizationID: 	orgID,
		Slug: 				slug,
	})
	if err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			httputil.RespondError(w, http.StatusNotFound, "team not found")
			return
		}

		slog.Error("Failed to fetch project details by slug", "error", err, "org_id", orgID, "slug", slug)
		httputil.RespondError(w, http.StatusInternalServerError, "Failed to fetch project info by slug")
		return
	}

	slog.Info("Successfully fetched project details by slug")
	httputil.RespondJSON(w, http.StatusOK, project)
}

// handles PATCH /api/v1/projects/{id}?org_id={org_id}
func (h *Handler) Update(w http.ResponseWriter, r *http.Request) {
	slog.Info("Updating project info by ID")

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

	var req UpdateProjectRequest
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

	params := database.UpdateProjectParams{
		ID: 				id,
		OrganizationID: 	orgID,
		Name: 				req.Name,
		Description: 		req.Description,
		Visibility: 		req.Visibility,
		TeamID: 			req.TeamID,
		IsArchived: 		req.IsArchived,
	}

	project, err := h.queries.UpdateProject(r.Context(), params)
	if err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			httputil.RespondError(w, http.StatusNotFound, "team not found")
			return
		}

		slog.Error("Failed to update project details", "error", err)
		httputil.RespondError(w, http.StatusInternalServerError, "Failed to update project details")
		return
	}

	slog.Info("Successfully updated the project details")
	httputil.RespondJSON(w, http.StatusOK, project)
}
