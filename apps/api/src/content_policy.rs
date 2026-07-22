//! Temporary content-readiness gating.
//!
//! Only English-medium content is considered "ready" for general use right
//! now, with two exceptions: the two Malayalam-language subjects
//! (malayalam-at/malayalam-bt) are naturally taught in Malayalam, so their
//! ml-medium chapters are ready too. Hindi/Urdu/Sanskrit/Arabic subjects
//! aren't ready in either medium yet. Chapter 0 ("Front Matter") is never
//! real chapter content and is always excluded.
//!
//! This is explicitly a "for now" rule (per product decision), not a
//! permanent architecture choice — when more content is verified, extend
//! the allowlists below or replace this with a per-textbook-version
//! `is_published` flag.

const EXCLUDED_SUBJECTS: [&str; 6] = [
    "hindi",
    "urdu",
    "sanskrit-academic",
    "sanskrit-oriental",
    "arabic-academic",
    "arabic-oriental",
];

const MALAYALAM_LANGUAGE_SUBJECTS: [&str; 2] = ["malayalam-at", "malayalam-bt"];

#[derive(Clone, Debug)]
pub struct ChapterInfo {
    pub chapter_id: String,
    pub chapter_number: i32,
    pub chapter_name: String,
    pub subject_id: String,
    pub subject_name: String,
    pub subject_code: String,
    #[allow(dead_code)]
    pub medium: String,
    /// e.g. "Part 1" / "Part 2" for subjects (Maths, English, ...) whose
    /// textbook is split into multiple physical volumes; None for subjects
    /// with a single textbook.
    pub part_label: Option<String>,
    pub enabled: bool,
}

pub fn is_chapter_enabled(subject_code: &str, medium: &str, chapter_number: i32) -> bool {
    if chapter_number == 0 {
        return false; // Front Matter
    }
    if EXCLUDED_SUBJECTS.contains(&subject_code) {
        return false;
    }
    if MALAYALAM_LANGUAGE_SUBJECTS.contains(&subject_code) {
        return medium == "en" || medium == "ml";
    }
    medium == "en"
}
