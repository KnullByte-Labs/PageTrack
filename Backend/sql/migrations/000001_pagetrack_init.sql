-- ============================================================================
-- Complete PostgreSQL 16+ Database Schema: PageTrack (pagetrack_db)
-- Designed for High-Performance Go Backend, TypeScript TipTap Frontend,
-- Realtime Collaboration, Multi-Tenancy (RLS), and Polyrepo Reusability.
-- ============================================================================

-- Enable Required Extensions
CREATE EXTENSION IF NOT EXISTS "ltree";
CREATE EXTENSION IF NOT EXISTS "pg_trgm";

-- ============================================================================
-- SECTION 1: MULTI-TENANT HIERARCHY (Reusable with Task tracking counterpart)
-- ============================================================================

-- 1. Organization (Tier 1: Tenant Boundary)
CREATE TABLE organizations (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    slug VARCHAR(64) UNIQUE NOT NULL,
    name VARCHAR(255) NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);

-- 2. Teams (Tier 2: Functional Groups mapped to IDM services)
CREATE TABLE teams (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    organization_id UUID NOT NULL REFERENCES organizations(id) ON DELETE CASCADE,
    name VARCHAR(255) NOT NULL,
    slug VARCHAR(64) NOT NULL,
    idm_group_path VARCHAR(255) NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT unique_org_team_slug UNIQUE (organization_id, slug)
);

CREATE INDEX idx_teams_org ON teams(organization_id);

-- 3. Projects (Tier 3: Collaborative spaces)
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

-- ============================================================================
-- SECTION 2: PAGETRACK DOCUMENT DOMAIN
-- ============================================================================

-- 4. Sections (Tier 4: Sub-project Functional Groupings)
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

-- 5. Pages (Tier 5: Recursive Document Hierarchy using ltree)
CREATE TABLE pages (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    organization_id UUID NOT NULL REFERENCES organizations(id) ON DELETE CASCADE,
    project_id UUID NOT NULL REFERENCES projects(id) ON DELETE CASCADE,
    section_id UUID NOT NULL REFERENCES sections(id) ON DELETE CASCADE,
    parent_id UUID REFERENCES pages(id) ON DELETE CASCADE,
    title VARCHAR(255) NOT NULL,
    slug VARCHAR(255) NOT NULL,
    path LTREE NOT NULL, -- Path eg. root.parent_id.child_id
    position INT NOT NULL DEFAULT 0, -- peer ordering for sidebar
    current_published_version INT NOT NULL DEFAULT 0,
    has_draft BOOLEAN NOT NULL DEFAULT FALSE,
    is_restricted BOOLEAN NOT NULL DEFAULT FALSE,
    is_archived BOOLEAN NOT NULL DEFAULT FALSE,
    created_by VARCHAR(128) NOT NULL, -- IDM service user ID
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT unique_section_page_slug UNIQUE (section_id, slug)
);

-- Performance indexes for hierarchy and search
CREATE INDEX idx_pages_path_gist ON pages USING GIST(path);
CREATE INDEX idx_pages_lookup ON pages(organization_id, project_id, section_id);
CREATE INDEX idx_pages_parent ON pages(parent_id, position);
CREATE INDEX idx_pages_title_trgm ON pages USING GIN (title gin_trgm_ops);

-- 6. Page Revisions (Version history)
CREATE TABLE page_revisions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    organization_id UUID NOT NULL REFERENCES organizations(id) ON DELETE CASCADE,
    page_id UUID NOT NULL REFERENCES pages(id) ON DELETE CASCADE,
    version INT NOT NULL,
    title VARCHAR(255) NOT NULL,
    content_ast JSONB NOT NULL, -- Full Abstract syntax tree
    content_text TEXT NOT NULL, -- Plain markdown for fallback
    change_summary VARCHAR(512),
    created_by VARCHAR(128) NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT unique_page_revision UNIQUE (page_id, version)
);

CREATE INDEX idx_revisions_page ON page_revisions(page_id, version DESC);

-- 7. Page drafts (Autosaved working state and realtime collabe snapshots)
CREATE TABLE page_drafts (
    page_id UUID PRIMARY KEY NOT NULL REFERENCES pages(id) ON DELETE CASCADE,
    organization_id UUID NOT NULL REFERENCES organizations(id) ON DELETE CASCADE,
    title VARCHAR(255) NOT NULL,
    content_ast JSONB NOT NULL,
    binary_crdt_state BYTEA, -- For carrying forward the undo/redo space
    created_by VARCHAR(128) NOT NULL,
    updated_by VARCHAR(128) NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);

-- 8. Page Comments (In-App discussions and Inline comments)
CREATE TABLE page_comments (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    organization_id UUID NOT NULL REFERENCES organizations(id) ON DELETE CASCADE,
    page_id UUID NOT NULL REFERENCES pages(id) ON DELETE CASCADE,
    parent_comment_id UUID REFERENCES page_comments(id) ON DELETE SET NULL,
    author_id VARCHAR(128) NOT NULL,
    content_ast JSONB NOT NULL, -- Rich AST content
    content_text TEXT NOT NULL, -- Markdown content
    anchor_from INT, -- rich ast text selection start index
    anchor_to INT, -- rich ast text selection end index
    anchor_text_preview VARCHAR(255), -- Text snapshot when comment was added
    is_resolved BOOLEAN NOT NULL DEFAULT FALSE,
    resolved_by VARCHAR(128),
    resolved_at TIMESTAMPTZ,
    deleted_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX idx_comments_page ON page_comments(page_id, created_at ASC);
CREATE INDEX idx_comments_parent ON page_comments(parent_comment_id);

-- ============================================================================
-- SECTION 3: COMMON UTILITIES (Reusable with Task tracking counterpart)
-- ============================================================================

-- 9. LABELS & TAGS (Cross Project)
CREATE TABLE labels (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    organization_id UUID NOT NULL REFERENCES organizations(id) ON DELETE CASCADE,
    name VARCHAR(64) NOT NULL,
    color_hex VARCHAR(7) DEFAULT '#6B7280',
    CONSTRAINT unique_org_label UNIQUE(organization_id, name)
);

CREATE TABLE page_labels (
    page_id UUID NOT NULL REFERENCES pages(id) ON DELETE CASCADE,
    label_id UUID NOT NULL REFERENCES labels(id) ON DELETE CASCADE,
    PRIMARY KEY (page_id, label_id)
);

-- 10. Attachments (Image, file or Video metadata)
CREATE TABLE attachments (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    organization_id UUID NOT NULL REFERENCES organizations(id) ON DELETE CASCADE,
    project_id UUID NOT NULL REFERENCES projects(id) ON DELETE CASCADE,
    page_id UUID NOT NULL REFERENCES pages(id) ON DELETE CASCADE,
    file_name VARCHAR(255) NOT NULL,
    file_size_bytes BIGINT NOT NULL,
    mime_type VARCHAR(128) NOT NULL,
    object_store_key VARCHAR(512) NOT NULL,
    uploaded_by VARCHAR(128) NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX idx_attachments_page ON attachments(page_id);

-- 11. Project webhooks (Outgoing message alerts)
CREATE TABLE project_webhooks (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    organization_id UUID NOT NULL REFERENCES organizations(id) ON DELETE CASCADE,
    project_id UUID NOT NULL REFERENCES projects(id) ON DELETE CASCADE,
    platform VARCHAR(32) NOT NULL, -- 'slack' / 'discord' etc.
    webhook_url TEXT NOT NULL,
    events TEXT[] NOT NULL DEFAULT '{"PAGE_PUBLISHED", "COMMENT_ADDED"}',
    is_active BOOLEAN NOT NULL DEFAULT TRUE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX idx_webhooks_project ON project_webhooks(project_id) WHERE is_active = TRUE;

-- 12. Transactional Outbox (Search sync and asynchronous worker events)
-- Basically messaging queue in database but it is required here because of ACID properties
-- this table will be created in the query as write page
CREATE TABLE outbox_events (
    id BIGSERIAL PRIMARY KEY,
    organization_id UUID NOT NULL,
    aggregate_type VARCHAR(64) NOT NULL,
    aggregate_id UUID NOT NULL,
    event_type VARCHAR(64) NOT NULL, -- 'PAGE_PUBLISHED' / 'COMMENT_ADDED'
    payload JSONB NOT NULL,
    processed BOOLEAN NOT NULL DEFAULT FALSE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX idx_outbox_unprocessed ON outbox_events(id) WHERE processed = FALSE;

-- ============================================================================
-- SECTION 4: ROW-LEVEL SECURITY (RLS) POLICIES
-- ============================================================================

ALTER TABLE organizations ENABLE ROW LEVEL SECURITY;
ALTER TABLE teams ENABLE ROW LEVEL SECURITY;
ALTER TABLE projects ENABLE ROW LEVEL SECURITY;
ALTER TABLE sections ENABLE ROW LEVEL SECURITY;
ALTER TABLE pages ENABLE ROW LEVEL SECURITY;
ALTER TABLE page_revisions ENABLE ROW LEVEL SECURITY;
ALTER TABLE page_drafts ENABLE ROW LEVEL SECURITY;
ALTER TABLE page_comments ENABLE ROW LEVEL SECURITY;
ALTER TABLE attachments ENABLE ROW LEVEL SECURITY;
ALTER TABLE labels ENABLE ROW LEVEL SECURITY;
ALTER TABLE project_webhooks ENABLE ROW LEVEL SECURITY;

-- Tenant Isolation Policies based on PostgreSQL session variable 'app.current_org_id'

CREATE POLICY tenant_isolation_organizations ON organizations
    AS RESTRICTIVE
    USING (id = NULLIF(current_setting('app.current_org_id', true), '')::UUID);

CREATE POLICY tenant_isolation_teams ON teams
    AS RESTRICTIVE
    USING (organization_id = NULLIF(current_setting('app.current_org_id', true), '')::UUID);

CREATE POLICY tenant_isolation_projects ON projects
    AS RESTRICTIVE
    USING (organization_id = NULLIF(current_setting('app.current_org_id', true), '')::UUID);

CREATE POLICY tenant_isolation_sections ON sections
    AS RESTRICTIVE
    USING (organization_id = NULLIF(current_setting('app.current_org_id', true), '')::UUID);

CREATE POLICY tenant_isolation_pages ON pages
    AS RESTRICTIVE
    USING (organization_id = NULLIF(current_setting('app.current_org_id', true), '')::UUID);

CREATE POLICY tenant_isolation_revisions ON page_revisions
    AS RESTRICTIVE
    USING (organization_id = NULLIF(current_setting('app.current_org_id', true), '')::UUID);

CREATE POLICY tenant_isolation_drafts ON page_drafts
    AS RESTRICTIVE
    USING (organization_id = NULLIF(current_setting('app.current_org_id', true), '')::UUID);

CREATE POLICY tenant_isolation_comments ON page_comments
    AS RESTRICTIVE
    USING (organization_id = NULLIF(current_setting('app.current_org_id', true), '')::UUID);

CREATE POLICY tenant_isolation_attachments ON attachments
    AS RESTRICTIVE
    USING (organization_id = NULLIF(current_setting('app.current_org_id', true), '')::UUID);

CREATE POLICY tenant_isolation_labels ON labels
    AS RESTRICTIVE
    USING (organization_id = NULLIF(current_setting('app.current_org_id', true), '')::UUID);

CREATE POLICY tenant_isolation_project_webhooks ON project_webhooks
    AS RESTRICTIVE
    USING (organization_id = NULLIF(current_setting('app.current_org_id', true), '')::UUID);
