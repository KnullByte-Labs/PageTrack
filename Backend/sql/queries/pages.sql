-- name: GetPageByID :one
SELECT id, organization_id, project_id, section_id, parent_id, title, slug, path, position,
current_published_version, has_draft, is_restricted, is_archived, created_by, created_at, updated_at
FROM pages
WHERE id = $1;

-- name: ListPagesByProject :many
SELECT id, organization_id, project_id, section_id, parent_id, title, slug, path, position,
current_published_version, has_draft, is_restricted, is_archived, created_by, created_at, updated_at
FROM pages
WHERE project_id = $1 AND is_archived = FALSE
ORDER BY position ASC, title ASC
LIMIT $2 OFFSET $3;

-- name: CountPagesByProject :one
SELECT COUNT(*) FROM pages WHERE project_id = $1 AND is_archived = FALSE;

-- name: ListPagesBySection :many
SELECT id, organization_id, project_id, section_id, parent_id, title, slug, path, position,
current_published_version, has_draft, is_restricted, is_archived, created_by, created_at, updated_at
FROM pages
WHERE section_id = $1 AND is_archived = FALSE
ORDER BY position ASC, title ASC
LIMIT $2 OFFSET $3;

-- name: CountPagesBySection :one
SELECT COUNT(*) FROM pages WHERE section_id = $1 AND is_archived = FALSE;

-- name: CreatePage :one
INSERT INTO pages (
    organization_id,
    project_id,
    section_id,
    parent_id,
    title,
    slug,
    path,
    position,
    created_by
) VALUES (
    $1, $2, $3, $4, $5, $6, $7, $8, $9
)
RETURNING id, organization_id, project_id, section_id, parent_id, title, slug, path, position,
current_published_version, has_draft, is_restricted, is_archived, created_by, created_at, updated_at;

-- name: UpdatePage :one
UPDATE pages
SET
    title = COALESCE($2, title),
    position = COALESCE($3, position),
    is_archived = COALESCE($4, is_archived),
    is_restricted = COALESCE($5, is_restricted),
    updated_at = CURRENT_TIMESTAMP
WHERE id = $1
RETURNING id, organization_id, project_id, section_id, parent_id, title, slug, path, position,
current_published_version, has_draft, is_restricted, is_archived, created_by, created_at, updated_at;

-- name: DeletePage :exec
DELETE FROM pages
WHERE id = $1;
