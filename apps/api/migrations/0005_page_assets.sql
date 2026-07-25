-- Per-page embedded illustrations/tables/graphs, ingested from the
-- per-asset JSON manifests written alongside each textbook's processed
-- output (storage/textbooks/processed/sslc/{subject}/{medium}/.../assets/
-- *.json — see scripts/ingest-page-assets.mjs). Previously a chunk's
-- Qdrant payload only ever carried a single "nearest" image_url, so a
-- page with multiple embedded figures only ever surfaced one of them, and
-- citing the same page from two different chunks looked like two sources
-- instead of deduping to one page with all of its real assets.
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
