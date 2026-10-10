-- ============================================================================
-- Complete PostgreSQL 16+ Database Schema: PageTrack (pagetrack_db)
-- Designed for High-Performance Go Backend, TypeScript TipTap Frontend,
-- Realtime Collaboration, Multi-Tenancy (RLS), and Polyrepo Reusability.
-- ============================================================================

-- Enable Required Extensions
CREATE EXTENSION IF NOT EXISTS "ltree";
CREATE EXTENSION IF NOT EXISTS "pg_trgm";

-- ============================================================================
-- SECTION 1: IDENTITY & TENANT BOUNDARY
-- ============================================================================

-- 1. Organizations (Tenant Boundary)
CREATE TABLE organizations (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    slug VARCHAR(64) UNIQUE NOT NULL,
    name VARCHAR(255) NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);

-- 2. Users (IDM-Agnostic Profile Cache)
CREATE TABLE users (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    idp_id VARCHAR(255) NOT NULL,                 -- External user ID from provider (OIDC sub)
    idp_type VARCHAR(64) NOT NULL DEFAULT 'oidc', -- 'keycloak', 'auth0', 'google', 'okta'
    email VARCHAR(255) NOT NULL,
    display_name VARCHAR(255) NOT NULL,
    avatar_url TEXT,
    is_active BOOLEAN NOT NULL DEFAULT TRUE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT unique_idp_identity UNIQUE (idp_type, idp_id)
);

CREATE INDEX idx_users_idp ON users(idp_type, idp_id);
CREATE INDEX idx_users_email ON users(email);

-- 3. Organization Members (Tenant RBAC: Tiered)
CREATE TABLE organization_members (
    organization_id UUID NOT NULL REFERENCES organizations(id) ON DELETE CASCADE,
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    role VARCHAR(32) NOT NULL DEFAULT 'member',
    joined_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (organization_id, user_id),
    CONSTRAINT chk_org_role CHECK (role IN ('owner', 'admin', 'member', 'guest'))
);

CREATE INDEX idx_org_members_user ON organization_members(user_id);

-- ============================================================================
-- SECTION 2: TEAMS & PROJECT SPACES
-- ============================================================================

-- 4. Teams (Functional Groups mapped to IDM group path)
CREATE TABLE teams (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    organization_id UUID NOT NULL REFERENCES organizations(id) ON DELETE CASCADE,
    name VARCHAR(255) NOT NULL,
    slug VARCHAR(64) NOT NULL,
    idp_group_path VARCHAR(255),                 -- Optional group mapping (e.g. "/engineering/backend")
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT unique_org_team_slug UNIQUE (organization_id, slug)
);

CREATE INDEX idx_teams_org ON teams(organization_id);

-- 5. Team Members (Flat Team Membership)
CREATE TABLE team_members (
    team_id UUID NOT NULL REFERENCES teams(id) ON DELETE CASCADE,
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (team_id, user_id)
);

CREATE INDEX idx_team_members_user ON team_members(user_id);

-- 6. Projects (Collaborative Spaces)
CREATE TABLE projects (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    organization_id UUID NOT NULL REFERENCES organizations(id) ON DELETE CASCADE,
    team_id UUID REFERENCES teams(id) ON DELETE SET NULL,
    name VARCHAR(255) NOT NULL,
    slug VARCHAR(64) NOT NULL,
    description TEXT,
    visibility VARCHAR(32) NOT NULL DEFAULT 'team', -- 'public', 'team', 'private'
    is_archived BOOLEAN NOT NULL DEFAULT FALSE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT unique_org_project_slug UNIQUE (organization_id, slug)
);

CREATE INDEX idx_projects_org_team ON projects(organization_id, team_id);

-- 7. Project Members (Project RBAC: admin, member, guest)
CREATE TABLE project_members (
    project_id UUID NOT NULL REFERENCES projects(id) ON DELETE CASCADE,
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    role VARCHAR(32) NOT NULL DEFAULT 'member',
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (project_id, user_id),
    CONSTRAINT chk_project_role CHECK (role IN ('admin', 'member', 'guest'))
);

CREATE INDEX idx_project_members_user ON project_members(user_id);

-- ============================================================================
-- SECTION 3: KNOWLEDGE BASE DOCUMENT DOMAIN
-- ============================================================================

-- 8. Sections (Sub-project Functional Groupings)
CREATE TABLE sections (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    organization_id UUID NOT NULL REFERENCES organizations(id) ON DELETE CASCADE,
    project_id UUID NOT NULL REFERENCES projects(id) ON DELETE CASCADE,
    name VARCHAR(255) NOT NULL,
    slug VARCHAR(64) NOT NULL,
    position INT NOT NULL DEFAULT 0,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT unique_project_section_slug UNIQUE (project_id, slug)
);

CREATE INDEX idx_sections_project ON sections(project_id, position);

-- 9. Pages (Recursive Document Hierarchy using ltree)
CREATE TABLE pages (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    organization_id UUID NOT NULL REFERENCES organizations(id) ON DELETE CASCADE,
    project_id UUID NOT NULL REFERENCES projects(id) ON DELETE CASCADE,
    section_id UUID NOT NULL REFERENCES sections(id) ON DELETE CASCADE,
    parent_id UUID REFERENCES pages(id) ON DELETE CASCADE,
    title VARCHAR(255) NOT NULL,
    slug VARCHAR(255) NOT NULL,
    path LTREE NOT NULL,                         -- Materialized path (e.g. "root.parent_id.child_id")
    position INT NOT NULL DEFAULT 0,
    current_published_version INT NOT NULL DEFAULT 0,
    has_draft BOOLEAN NOT NULL DEFAULT FALSE,
    is_restricted BOOLEAN NOT NULL DEFAULT FALSE, -- Governed by page_permissions when TRUE
    is_archived BOOLEAN NOT NULL DEFAULT FALSE,
    created_by UUID NOT NULL REFERENCES users(id) ON DELETE RESTRICT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT unique_section_page_slug UNIQUE (section_id, slug)
);

CREATE INDEX idx_pages_path_gist ON pages USING GIST(path);
CREATE INDEX idx_pages_lookup ON pages(organization_id, project_id, section_id);
CREATE INDEX idx_pages_parent ON pages(parent_id, position);
CREATE INDEX idx_pages_title_trgm ON pages USING GIN (title gin_trgm_ops);

-- 10. Page Permissions (Exceptions for pages.is_restricted = TRUE)
CREATE TABLE page_permissions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    page_id UUID NOT NULL REFERENCES pages(id) ON DELETE CASCADE,
    user_id UUID REFERENCES users(id) ON DELETE CASCADE,
    team_id UUID REFERENCES teams(id) ON DELETE CASCADE,
    permission VARCHAR(32) NOT NULL,             -- 'view', 'edit'
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT chk_perm_target CHECK (user_id IS NOT NULL OR team_id IS NOT NULL),
    CONSTRAINT unique_page_user_perm UNIQUE (page_id, user_id),
    CONSTRAINT unique_page_team_perm UNIQUE (page_id, team_id),
    CONSTRAINT chk_perm_level CHECK (permission IN ('view', 'edit'))
);

CREATE INDEX idx_page_perms_page ON page_permissions(page_id);
CREATE INDEX idx_page_perms_user ON page_permissions(user_id);

-- 11. Page Revisions (Immutable Version History)
CREATE TABLE page_revisions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    organization_id UUID NOT NULL REFERENCES organizations(id) ON DELETE CASCADE,
    page_id UUID NOT NULL REFERENCES pages(id) ON DELETE CASCADE,
    version INT NOT NULL,
    title VARCHAR(255) NOT NULL,
    content_ast JSONB NOT NULL,                 -- Full TipTap/ProseMirror JSON Block AST
    content_text TEXT NOT NULL,                -- Plain text fallback for search/notifications
    change_summary VARCHAR(512),
    created_by UUID NOT NULL REFERENCES users(id) ON DELETE RESTRICT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT unique_page_revision UNIQUE (page_id, version)
);

CREATE INDEX idx_revisions_page ON page_revisions(page_id, version DESC);

-- 12. Page Drafts (Working State & CRDT Collaboration State)
CREATE TABLE page_drafts (
    page_id UUID PRIMARY KEY REFERENCES pages(id) ON DELETE CASCADE,
    organization_id UUID NOT NULL REFERENCES organizations(id) ON DELETE CASCADE,
    title VARCHAR(255) NOT NULL,
    content_ast JSONB NOT NULL,
    binary_crdt_state BYTEA,                     -- State vector for undo/redo preservation
    created_by UUID NOT NULL REFERENCES users(id) ON DELETE RESTRICT,
    updated_by UUID NOT NULL REFERENCES users(id) ON DELETE RESTRICT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);

-- 13. Page Comments (In-App Discussions & Text Anchors)
CREATE TABLE page_comments (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    organization_id UUID NOT NULL REFERENCES organizations(id) ON DELETE CASCADE,
    page_id UUID NOT NULL REFERENCES pages(id) ON DELETE CASCADE,
    parent_comment_id UUID REFERENCES page_comments(id) ON DELETE SET NULL, -- Soft tree preservation
    author_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    content_ast JSONB NOT NULL,
    content_text TEXT NOT NULL,
    anchor_from INT,
    anchor_to INT,
    anchor_text_preview VARCHAR(255),
    is_resolved BOOLEAN NOT NULL DEFAULT FALSE,
    resolved_by UUID REFERENCES users(id) ON DELETE SET NULL,
    resolved_at TIMESTAMPTZ,
    deleted_at TIMESTAMPTZ,                     -- Soft deletion
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX idx_comments_page ON page_comments(page_id, created_at ASC);
CREATE INDEX idx_comments_parent ON page_comments(parent_comment_id);

-- ============================================================================
-- SECTION 4: COMMON UTILITIES & WORKER INFRASTRUCTURE
-- ============================================================================

-- 14. Labels & Tags
CREATE TABLE labels (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    organization_id UUID NOT NULL REFERENCES organizations(id) ON DELETE CASCADE,
    name VARCHAR(64) NOT NULL,
    color_hex VARCHAR(7) DEFAULT '#6B7280',
    CONSTRAINT unique_org_label UNIQUE (organization_id, name)
);

CREATE TABLE page_labels (
    page_id UUID NOT NULL REFERENCES pages(id) ON DELETE CASCADE,
    label_id UUID NOT NULL REFERENCES labels(id) ON DELETE CASCADE,
    PRIMARY KEY (page_id, label_id)
);

-- 15. Attachments (File & Video Object Storage Metadata)
CREATE TABLE attachments (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    organization_id UUID NOT NULL REFERENCES organizations(id) ON DELETE CASCADE,
    project_id UUID NOT NULL REFERENCES projects(id) ON DELETE CASCADE,
    page_id UUID REFERENCES pages(id) ON DELETE SET NULL,
    file_name VARCHAR(255) NOT NULL,
    file_size_bytes BIGINT NOT NULL,
    mime_type VARCHAR(128) NOT NULL,
    object_store_key VARCHAR(512) NOT NULL,
    uploaded_by UUID NOT NULL REFERENCES users(id) ON DELETE RESTRICT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX idx_attachments_page ON attachments(page_id);

-- 16. Project Webhooks (Outgoing Slack/Discord Alerts)
CREATE TABLE project_webhooks (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    organization_id UUID NOT NULL REFERENCES organizations(id) ON DELETE CASCADE,
    project_id UUID NOT NULL REFERENCES projects(id) ON DELETE CASCADE,
    platform VARCHAR(32) NOT NULL,              -- 'slack', 'discord'
    webhook_url TEXT NOT NULL,
    events TEXT[] NOT NULL DEFAULT '{"PAGE_PUBLISHED", "COMMENT_ADDED"}',
    is_active BOOLEAN NOT NULL DEFAULT TRUE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX idx_webhooks_project ON project_webhooks(project_id) WHERE is_active = TRUE;

-- 17. Transactional Outbox (Search Sync & Asynchronous Worker Events)
CREATE TABLE outbox_events (
    id BIGSERIAL PRIMARY KEY,
    organization_id UUID NOT NULL,
    aggregate_type VARCHAR(64) NOT NULL,         -- 'PAGE', 'COMMENT'
    aggregate_id UUID NOT NULL,
    event_type VARCHAR(64) NOT NULL,             -- 'PAGE_PUBLISHED', 'COMMENT_ADDED'
    payload JSONB NOT NULL,
    processed BOOLEAN NOT NULL DEFAULT FALSE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX idx_outbox_unprocessed ON outbox_events(id) WHERE processed = FALSE;

-- ============================================================================
-- SECTION 5: ROW-LEVEL SECURITY (RLS) POLICIES
-- ============================================================================

ALTER TABLE organizations ENABLE ROW LEVEL SECURITY;
ALTER TABLE organization_members ENABLE ROW LEVEL SECURITY;
ALTER TABLE teams ENABLE ROW LEVEL SECURITY;
ALTER TABLE team_members ENABLE ROW LEVEL SECURITY;
ALTER TABLE projects ENABLE ROW LEVEL SECURITY;
ALTER TABLE project_members ENABLE ROW LEVEL SECURITY;
ALTER TABLE sections ENABLE ROW LEVEL SECURITY;
ALTER TABLE pages ENABLE ROW LEVEL SECURITY;
ALTER TABLE page_permissions ENABLE ROW LEVEL SECURITY;
ALTER TABLE page_revisions ENABLE ROW LEVEL SECURITY;
ALTER TABLE page_drafts ENABLE ROW LEVEL SECURITY;
ALTER TABLE page_comments ENABLE ROW LEVEL SECURITY;
ALTER TABLE attachments ENABLE ROW LEVEL SECURITY;
ALTER TABLE labels ENABLE ROW LEVEL SECURITY;
ALTER TABLE project_webhooks ENABLE ROW LEVEL SECURITY;

-- 1. Organizations Tenant Policy
CREATE POLICY tenant_isolation_organizations ON organizations
    AS RESTRICTIVE
    USING (id = NULLIF(current_setting('app.current_org_id', true), '')::UUID);

-- 2. Organization Members Policy
CREATE POLICY tenant_isolation_organization_members ON organization_members
    AS RESTRICTIVE
    USING (organization_id = NULLIF(current_setting('app.current_org_id', true), '')::UUID);

-- 3. Teams Policy
CREATE POLICY tenant_isolation_teams ON teams
    AS RESTRICTIVE
    USING (organization_id = NULLIF(current_setting('app.current_org_id', true), '')::UUID);

-- 4. Team Members Policy
CREATE POLICY tenant_isolation_team_members ON team_members
    AS RESTRICTIVE
    USING (
        team_id IN (
            SELECT id FROM teams WHERE organization_id = NULLIF(current_setting('app.current_org_id', true), '')::UUID
        )
    );

-- 5. Projects Policy
CREATE POLICY tenant_isolation_projects ON projects
    AS RESTRICTIVE
    USING (organization_id = NULLIF(current_setting('app.current_org_id', true), '')::UUID);

-- 6. Project Members Policy
CREATE POLICY tenant_isolation_project_members ON project_members
    AS RESTRICTIVE
    USING (
        project_id IN (
            SELECT id FROM projects WHERE organization_id = NULLIF(current_setting('app.current_org_id', true), '')::UUID
        )
    );

-- 7. Sections Policy
CREATE POLICY tenant_isolation_sections ON sections
    AS RESTRICTIVE
    USING (organization_id = NULLIF(current_setting('app.current_org_id', true), '')::UUID);

-- 8. Pages Policy
CREATE POLICY tenant_isolation_pages ON pages
    AS RESTRICTIVE
    USING (organization_id = NULLIF(current_setting('app.current_org_id', true), '')::UUID);

-- 9. Page Permissions Policy
CREATE POLICY tenant_isolation_page_permissions ON page_permissions
    AS RESTRICTIVE
    USING (
        page_id IN (
            SELECT id FROM pages WHERE organization_id = NULLIF(current_setting('app.current_org_id', true), '')::UUID
        )
    );

-- 10. Page Revisions Policy
CREATE POLICY tenant_isolation_revisions ON page_revisions
    AS RESTRICTIVE
    USING (organization_id = NULLIF(current_setting('app.current_org_id', true), '')::UUID);

-- 11. Page Drafts Policy
CREATE POLICY tenant_isolation_drafts ON page_drafts
    AS RESTRICTIVE
    USING (organization_id = NULLIF(current_setting('app.current_org_id', true), '')::UUID);

-- 12. Page Comments Policy
CREATE POLICY tenant_isolation_comments ON page_comments
    AS RESTRICTIVE
    USING (organization_id = NULLIF(current_setting('app.current_org_id', true), '')::UUID);

-- 13. Attachments Policy
CREATE POLICY tenant_isolation_attachments ON attachments
    AS RESTRICTIVE
    USING (organization_id = NULLIF(current_setting('app.current_org_id', true), '')::UUID);

-- 14. Labels Policy
CREATE POLICY tenant_isolation_labels ON labels
    AS RESTRICTIVE
    USING (organization_id = NULLIF(current_setting('app.current_org_id', true), '')::UUID);

-- 15. Project Webhooks Policy
CREATE POLICY tenant_isolation_project_webhooks ON project_webhooks
    AS RESTRICTIVE
    USING (organization_id = NULLIF(current_setting('app.current_org_id', true), '')::UUID);
