-- name: GetPageByID :one
SELECT id, organization_id, project_id, section_id, parent_id, title, slug, path, position,
currend_published_version, has_draft, is_restricted, is_archived, created_by, created_at, updated_at
FROM pages
WHERE id = $1;

-- name: ListPagesByProject: many
SELECT id, organization_id, project_id, section_id, parent_id, title, slug, path, position,
currend_published_version, has_draft, is_restricted, is_archived, created_by, created_at, updated_at
FROM pages
WHERE project_id = $1
ORDER BY position ASC;
