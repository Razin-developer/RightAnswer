-- Sharing system: 10-minute expiring links for chats (reference an
-- existing chat directly) and generic content (an uploaded ZIP blob, used
-- for exam/study-plan exports). Ported from the pre-Rust-migration Node
-- backend's ShareLink/ContentShare models — the Flutter client already
-- expects this exact contract (POST /api/chats/by-local/:id/share,
-- GET /api/share/:token, POST /api/content).

CREATE TABLE IF NOT EXISTS content_shares (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  owner_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  filename TEXT NOT NULL,
  mime_type TEXT NOT NULL DEFAULT 'application/zip',
  metadata JSONB NOT NULL DEFAULT '{}',
  bytes BYTEA NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS share_links (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  owner_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  token TEXT NOT NULL UNIQUE,
  share_type TEXT NOT NULL, -- 'chat' | 'content'
  ref_id UUID NOT NULL,
  access_level TEXT NOT NULL DEFAULT 'full',
  use_count INTEGER NOT NULL DEFAULT 0,
  expires_at TIMESTAMPTZ NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_share_links_token ON share_links(token);
CREATE INDEX IF NOT EXISTS idx_share_links_expires ON share_links(expires_at);
