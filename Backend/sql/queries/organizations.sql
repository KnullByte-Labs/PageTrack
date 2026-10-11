-- name: GetOrganizationByID :one
SELECT id, slug, name, display_name, image_url, live_url, description, created_at, updated_at
FROM organizations
WHERE id = $1;

-- name: GetOrganizationBySlug :one
SELECT id, slug, name, display_name, image_url, live_url, description, created_at, updated_at
FROM organizations
WHERE slug = $1;

-- name: ListOrganizations :many
SELECT id, slug, name, display_name, image_url, live_url, description, created_at, updated_at
FROM organizations
ORDER BY name ASC
LIMIT $1 OFFSET $2;

-- name: CountOrganizations :one
SELECT COUNT(*) FROM organizations;

-- name: CreateOrganization :one
INSERT INTO organizations (
    slug,
    name,
    display_name,
    image_url,
    live_url,
    description
) VALUES (
    $1, $2, $3, $4, $5, $6
)
RETURNING id, slug, name, display_name, image_url, live_url, description, created_at, updated_at;

-- name: UpdateOrganization :one
UPDATE organizations
SET
    name = COALESCE(sqlc.narg('name'), name),
    display_name = COALESCE(sqlc.narg('display_name'), display_name),
    image_url = COALESCE(sqlc.narg('image_url'), image_url),
    live_url = COALESCE(sqlc.narg('live_url'), live_url),
    description = COALESCE(sqlc.narg('description'), description),
    updated_at = CURRENT_TIMESTAMP
WHERE id = $1
RETURNING id, slug, name, display_name, image_url, live_url, description, created_at, updated_at;

-- name: DeleteOrganization :exec
DELETE FROM organizations
WHERE id = $1;
