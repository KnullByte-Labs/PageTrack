-- name: GetProjectByID :one
SELECT id, organization_id, team_id, name, slug, description, visibility, is_archived, created_at, updated_at
FROM projects
WHERE id = $1;

-- name: GetProjectBySlug :one
SELECT id, organization_id, team_id, name, slug, description, visibility, is_archived, created_at, updated_at
FROM projects
WHERE organization_id = $1 AND slug = $2;

-- name: ListProjectsByOrg :many
SELECT id, organization_id, team_id, name, slug, description, visibility, is_archived, created_at, updated_at
FROM projects
WHERE organization_id = $1 AND is_archived = FALSE
ORDER BY name ASC
LIMIT $2 OFFSET $3;

-- name: CountProjectsByOrg :one
SELECT COUNT(*) FROM projects WHERE organization_id = $1 AND is_archived = FALSE;

-- name: CreateProject :one
INSERT INTO projects (
    organization_id,
    team_id,
    name,
    slug,
    description,
    visibility
) VALUES (
    $1, $2, $3, $4, $5, $6
)
RETURNING id, organization_id, team_id, name, slug, description, visibility, is_archived, created_at, updated_at;

-- name: UpdateProject :one
UPDATE projects
SET
    name = COALESCE($2, name),
    description = COALESCE($3, description),
    visibility = COALESCE($4, visibility),
    team_id = COALESCE($5, team_id),
    is_archived = COALESCE($6, is_archived),
    updated_at = CURRENT_TIMESTAMP
WHERE id = $1
RETURNING id, organization_id, team_id, name, slug, description, visibility, is_archived, created_at, updated_at;

-- name: DeleteProject :exec
DELETE FROM projects
WHERE id = $1;
