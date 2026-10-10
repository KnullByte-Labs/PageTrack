ALTER TABLE organizations
    ADD COLUMN display_name VARCHAR(255),
    ADD COLUMN image_url TEXT,
    ADD COLUMN live_url TEXT,
    ADD COLUMN description TEXT;