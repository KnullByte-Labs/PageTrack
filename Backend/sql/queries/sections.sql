-- name: GetSectionByID :one
SELECT id, organization_id, project_id, name, slug, position, created_at, updated_at
FROM sections
WHERE id = $1;

-- name: ListSectionsByProject :many
SELECT id, organization_id, project_id, name, slug, position, created_at, updated_at
FROM sections
WHERE project_id = $1
ORDER BY position ASC, name ASC;

-- name: CreateSection :one
INSERT INTO sections (
    organization_id,
    project_id,
    name,
    slug,
    position
) VALUES (
    $1, $2, $3, $4, $5
)
RETURNING id, organization_id, project_id, name, slug, position, created_at, updated_at;

-- name: UpdateSection :one
UPDATE sections
SET
    name = COALESCE($2, name),
    position = COALESCE($3, position),
    updated_at = CURRENT_TIMESTAMP
WHERE id = $1
RETURNING id, organization_id, project_id, name, slug, position, created_at, updated_at;

-- name: DeleteSection :exec
DELETE FROM sections
WHERE id = $1;
