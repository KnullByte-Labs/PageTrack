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
ORDER BY name ASC;

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
    name = COALESCE($2, name),
    display_name = COALESCE($3, display_name),
    image_url = COALESCE($4, image_url),
    live_url = COALESCE($5, live_url),
    description = COALESCE($6, description),
    updated_at = CURRENT_TIMESTAMP
WHERE id = $1
RETURNING id, slug, name, display_name, image_url, live_url, description, created_at, updated_at;