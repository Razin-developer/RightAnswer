CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

CREATE TABLE IF NOT EXISTS users (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  email TEXT NOT NULL UNIQUE,
  password_hash TEXT NOT NULL,
  name TEXT NOT NULL DEFAULT '',
  role TEXT NOT NULL DEFAULT 'student',
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS chats (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  owner_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  local_id TEXT NOT NULL,
  name TEXT NOT NULL DEFAULT 'New Chat',
  subject_id TEXT,
  subject_name TEXT,
  chapter_ids TEXT[] NOT NULL DEFAULT '{}',
  chapter_names TEXT[] NOT NULL DEFAULT '{}',
  is_temporary BOOLEAN NOT NULL DEFAULT false,
  is_pinned BOOLEAN NOT NULL DEFAULT false,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE(owner_id, local_id)
);

CREATE TABLE IF NOT EXISTS chat_messages (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  owner_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  chat_id UUID NOT NULL REFERENCES chats(id) ON DELETE CASCADE,
  local_id TEXT NOT NULL,
  role TEXT NOT NULL,
  content TEXT NOT NULL,
  response_language TEXT,
  response_length TEXT,
  reasoning_level TEXT,
  token_count INTEGER NOT NULL DEFAULT 0,
  source_chunks TEXT[] NOT NULL DEFAULT '{}',
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE(chat_id, local_id)
);

CREATE TABLE IF NOT EXISTS answer_cache (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  exact_key TEXT NOT NULL UNIQUE,
  normalized_question TEXT NOT NULL,
  question TEXT NOT NULL,
  answer TEXT NOT NULL,
  embedding DOUBLE PRECISION[] NOT NULL DEFAULT '{}',
  model TEXT NOT NULL DEFAULT '',
  provider TEXT NOT NULL DEFAULT '',
  language TEXT,
  response_length TEXT NOT NULL DEFAULT 'normal',
  reasoning_level TEXT NOT NULL DEFAULT 'mid',
  subject_id TEXT,
  subject_name TEXT,
  chapter_ids TEXT[] NOT NULL DEFAULT '{}',
  source_chunks TEXT[] NOT NULL DEFAULT '{}',
  input_tokens INTEGER NOT NULL DEFAULT 0,
  output_tokens INTEGER NOT NULL DEFAULT 0,
  hit_count INTEGER NOT NULL DEFAULT 0,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS ai_usage_events (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id UUID REFERENCES users(id) ON DELETE SET NULL,
  route TEXT NOT NULL,
  provider TEXT NOT NULL,
  model TEXT NOT NULL,
  input_tokens INTEGER NOT NULL DEFAULT 0,
  output_tokens INTEGER NOT NULL DEFAULT 0,
  estimated_cost_usd DOUBLE PRECISION NOT NULL DEFAULT 0,
  served_from TEXT NOT NULL DEFAULT 'model',
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_chats_owner_updated ON chats(owner_id, updated_at DESC);
CREATE INDEX IF NOT EXISTS idx_messages_chat_created ON chat_messages(chat_id, created_at ASC);
CREATE INDEX IF NOT EXISTS idx_answer_cache_lookup
  ON answer_cache(language, response_length, reasoning_level, updated_at DESC);
CREATE INDEX IF NOT EXISTS idx_usage_created ON ai_usage_events(created_at DESC);
CREATE INDEX IF NOT EXISTS idx_usage_user_created ON ai_usage_events(user_id, created_at DESC);
