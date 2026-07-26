-- Full-page textbook scans, ingested from the per-page JSON metadata
-- written alongside each textbook's processed output
-- (storage/textbooks/processed/sslc/{subject}/{medium}/.../pages/*.json,
-- paired with .../assets/page-{NNN}.png — see
-- apps/api/src/bin/ingest_page_assets.rs). Previously a chunk's Qdrant
-- payload only ever carried a single "nearest" image_url, so citing the
-- same page from two different chunks looked like two sources instead of
-- deduping to one page with its actual page image.
CREATE TABLE IF NOT EXISTS page_assets (
  id BIGSERIAL PRIMARY KEY,
  subject_code TEXT NOT NULL,
  medium TEXT NOT NULL,
  chapter_number INTEGER NOT NULL,
  page_number INTEGER NOT NULL,
  asset_type TEXT NOT NULL,
  file_path TEXT NOT NULL,
  UNIQUE(subject_code, medium, chapter_number, page_number, file_path)
);
CREATE INDEX IF NOT EXISTS idx_page_assets_lookup
  ON page_assets(subject_code, medium, chapter_number, page_number);
