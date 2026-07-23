-- Exams and study plans previously had no server-side persistence at all
-- (only the manual export/share ZIP flow) — the client's SQLite copy was
-- the only copy, lost on uninstall/device change. Each is stored as one
-- row with its full local shape (exam + questions, or plan + days + tasks)
-- in `data`, mirroring the client's own toMap()/fromMap() round trip
-- rather than a fully normalized schema — simplest thing that actually
-- gets this data onto the server and back.

CREATE TABLE IF NOT EXISTS exams (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  owner_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  local_id TEXT NOT NULL,
  name TEXT NOT NULL,
  data JSONB NOT NULL DEFAULT '{}',
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE(owner_id, local_id)
);
CREATE INDEX IF NOT EXISTS idx_exams_owner ON exams(owner_id, updated_at DESC);

CREATE TABLE IF NOT EXISTS study_plans (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  owner_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  local_id TEXT NOT NULL,
  name TEXT NOT NULL,
  data JSONB NOT NULL DEFAULT '{}',
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE(owner_id, local_id)
);
CREATE INDEX IF NOT EXISTS idx_study_plans_owner ON study_plans(owner_id, updated_at DESC);
