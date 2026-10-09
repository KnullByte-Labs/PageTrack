-- name: GetOrganizationByID :one
SELECT id, slug, name, created_at, updated_at
FROM organizations
WHERE id = $1;

-- name: ListOrganizations :many
SELECT id, slug, name, created_at, updated_at
FROM organizations
ORDER BY name ASC;
