-- name: GetTeamByID :one
SELECT id, organization_id, name, slug, idp_group_path, created_at, updated_at
FROM teams
WHERE id = $1;

-- name: GetTeamBySlug :one
SELECT id, organization_id, name, slug, idp_group_path, created_at, updated_at
FROM teams
WHERE organization_id = $1 AND slug = $2;

-- name: ListTeamsByOrg :many
SELECT id, organization_id, name, slug, idp_group_path, created_at, updated_at
FROM teams
WHERE organization_id = $1
ORDER BY name ASC
LIMIT $2 OFFSET $3;

-- name: CountTeamsByOrg :one
SELECT COUNT(*) FROM teams WHERE organization_id = $1;

-- name: CreateTeam :one
INSERT INTO teams (
    organization_id,
    name,
    slug,
    idp_group_path
) VALUES (
    $1, $2, $3, $4
)
RETURNING id, organization_id, name, slug, idp_group_path, created_at, updated_at;

-- name: UpdateTeam :one
UPDATE teams
SET
    name = COALESCE($2, name),
    idp_group_path = COALESCE($3, idp_group_path),
    updated_at = CURRENT_TIMESTAMP
WHERE id = $1
RETURNING id, organization_id, name, slug, idp_group_path, created_at, updated_at;

-- name: DeleteTeam :exec
DELETE FROM teams
WHERE id = $1;
