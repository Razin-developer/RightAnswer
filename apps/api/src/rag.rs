use std::collections::HashMap;

use crate::{
    content_policy::ChapterInfo,
    error::ApiError,
    models::{AiChatRequest, SourceInfo},
    qdrant::RetrievedChunk,
    routes::AppState,
};

#[derive(Default, Clone)]
pub struct ContextMeta {
    pub subject_id: Option<String>,
    pub subject_name: Option<String>,
    pub chapter_id: Option<String>,
    pub chapter_name: Option<String>,
}

pub struct SelectedContexts {
    pub sources: Vec<SourceInfo>,
    pub primary_meta: ContextMeta,
}

pub struct BetaConfirmation {
    pub chapter_id: String,
    pub chapter_name: String,
    pub subject_name: String,
}

pub enum ContextsOutcome {
    Ready(SelectedContexts),
    NeedsBetaConfirmation(BetaConfirmation),
}

#[derive(Clone, Default)]
struct ChunkMeta {
    subject_id: Option<String>,
    subject_name: Option<String>,
    chapter_id: Option<String>,
    chapter_name: Option<String>,
    page_number: Option<i32>,
    image_url: Option<String>,
}

/// Qdrant stores image_url as a path relative to storage/ (e.g.
/// "textbooks/processed/sslc/mathematics/en/.../page-057-embedded-01.jpeg"),
/// which nginx serves as a static file under /textbook-assets/ — see
/// deploy/nginx/rightanswer.conf. Turns that into a full URL the app can
/// hand directly to an image widget.
fn full_image_url(app_url: &str, relative_path: &str) -> String {
    format!(
        "{}/textbook-assets/{}",
        app_url.trim_end_matches('/'),
        relative_path.trim_start_matches('/')
    )
}

/// Retrieves and reranks context for a question. Subject/chapter selection
/// is optional — when the client doesn't pick a chapter, retrieval runs a
/// global vector search restricted to "ready" chapters (see
/// content_policy), and the top-ranked chunk's own metadata is used to
/// classify the resulting chat.
///
/// Before answering, a fast embeddings-only (no rerank) peek checks whether
/// the best-matching content actually lives in a chapter that isn't ready
/// yet ("beta"). If so, the caller gets NeedsBetaConfirmation instead of an
/// answer, so the app can ask the user whether they still want it. Resending
/// the same request with `confirmBetaChapterId` set bypasses the gate for
/// that one chapter.
pub async fn select_contexts(
    state: &AppState,
    request: &AiChatRequest,
    question: &str,
    question_embedding: Option<&[f32]>,
) -> Result<ContextsOutcome, ApiError> {
    let direct_sources: Vec<SourceInfo> = request
        .contexts
        .clone()
        .or_else(|| request.source_chunks.clone())
        .unwrap_or_default()
        .into_iter()
        .map(|value| value.trim().to_string())
        .filter(|value| !value.is_empty())
        .map(|text| SourceInfo {
            text,
            page_number: None,
            subject_name: None,
            chapter_name: None,
            image_url: None,
        })
        .collect();

    let explicit_chapter_ids = request.chapter_ids.clone().unwrap_or_default();
    let confirmed_chapter_id = request.confirm_beta_chapter_id.clone();

    let owned_embedding;
    let embedding = if let Some(embedding) = question_embedding {
        embedding
    } else {
        owned_embedding = state.ai.embed(question).await.unwrap_or_default().0;
        &owned_embedding
    };

    if embedding.is_empty() {
        return Ok(ContextsOutcome::Ready(
            finalize(direct_sources, Vec::new(), question, state).await,
        ));
    }

    let chapter_index = state.db.list_chapter_info().await.unwrap_or_default();
    let index_by_id: HashMap<&str, &ChapterInfo> = chapter_index
        .iter()
        .map(|info| (info.chapter_id.as_str(), info))
        .collect();

    // A disabled chapter only trips the beta gate when it's a genuinely
    // *better* match than anything the enabled scope offers — otherwise a
    // low-relevance disabled hit (e.g. shared boilerplate text, or a
    // question that's actually well-covered by enabled content) would
    // needlessly block a perfectly answerable question. Qdrant scores are
    // cosine similarity in [-1, 1]; a hit has to beat the best enabled
    // score by this margin to count as "actually better", not just present.
    const BETA_GATE_MARGIN: f32 = 0.03;

    let search_scope: Vec<String> = if !explicit_chapter_ids.is_empty() {
        explicit_chapter_ids.clone()
    } else {
        let mut ids: Vec<String> = chapter_index
            .iter()
            .filter(|info| info.enabled)
            .map(|info| info.chapter_id.clone())
            .collect();
        if let Some(id) = &confirmed_chapter_id {
            if !ids.contains(id) {
                ids.push(id.clone());
            }
        }
        ids
    };
    let enabled_scope_results = state
        .qdrant
        .search(embedding, &search_scope, 12)
        .await
        .unwrap_or_default();
    let enabled_top_score = enabled_scope_results
        .first()
        .map(|chunk| chunk.score)
        .unwrap_or(f32::MIN);

    // Beta gate: peek at the best match outside Front Matter (embeddings
    // only, no rerank — rerank is comparatively expensive and unnecessary
    // just to classify readiness) before committing to a real answer.
    // Front Matter (chapter 0) is generic textbook boilerplate — legend,
    // table of contents — never real subject content, and its short,
    // generic phrasing scores deceptively well against short questions in
    // any language. It's excluded from the peek scope entirely rather than
    // relying on the margin to filter it out, since it isn't a genuine
    // "better match" case, it's a structural false positive.
    let peek_scope: Vec<String> = chapter_index
        .iter()
        .filter(|info| info.chapter_number != 0)
        .map(|info| info.chapter_id.clone())
        .collect();
    let peek = state
        .qdrant
        .search(embedding, &peek_scope, 3)
        .await
        .unwrap_or_default();
    if let Some(top) = peek.first() {
        let already_confirmed = confirmed_chapter_id.is_some()
            && confirmed_chapter_id.as_deref() == top.chapter_id.as_deref();
        let beats_enabled_scope = top.score > enabled_top_score + BETA_GATE_MARGIN;
        if !already_confirmed && beats_enabled_scope {
            if let Some(info) = top.chapter_id.as_deref().and_then(|id| index_by_id.get(id)) {
                if !info.enabled {
                    return Ok(ContextsOutcome::NeedsBetaConfirmation(BetaConfirmation {
                        chapter_id: info.chapter_id.clone(),
                        chapter_name: info.chapter_name.clone(),
                        subject_name: info.subject_name.clone(),
                    }));
                }
            }
        }
    }

    Ok(ContextsOutcome::Ready(
        finalize(direct_sources, enabled_scope_results, question, state).await,
    ))
}

async fn finalize(
    direct_sources: Vec<SourceInfo>,
    retrieved: Vec<RetrievedChunk>,
    question: &str,
    state: &AppState,
) -> SelectedContexts {
    let mut meta_by_text: HashMap<String, ChunkMeta> = HashMap::new();
    let mut candidates: Vec<String> = Vec::with_capacity(direct_sources.len() + retrieved.len());

    for source in &direct_sources {
        candidates.push(source.text.clone());
    }

    for chunk in retrieved {
        let page = chunk
            .page_number
            .map(|page| format!("Page {page}: "))
            .unwrap_or_default();
        let full_image_url = chunk
            .image_url
            .as_deref()
            .map(|relative| full_image_url(&state.config.app_url, relative));
        let image = full_image_url
            .as_ref()
            .map(|url| format!("\nImage: {url}"))
            .unwrap_or_default();
        let text = format!("{page}{}{}", chunk.text, image);
        meta_by_text.insert(
            text.clone(),
            ChunkMeta {
                subject_id: chunk.subject_id,
                subject_name: chunk.subject_name,
                chapter_id: chunk.chapter_id,
                chapter_name: chunk.chapter_name,
                page_number: chunk.page_number,
                image_url: full_image_url,
            },
        );
        candidates.push(text);
    }

    if candidates.is_empty() {
        return SelectedContexts {
            sources: vec![],
            primary_meta: ContextMeta::default(),
        };
    }

    let ranked = state.ai.rerank(question, &candidates).await;
    let target = ranked.len().clamp(3, 5).min(ranked.len());
    let top_texts: Vec<String> = ranked.into_iter().take(target).collect();

    let primary_meta = top_texts
        .iter()
        .find_map(|text| meta_by_text.get(text))
        .map(|meta| ContextMeta {
            subject_id: meta.subject_id.clone(),
            subject_name: meta.subject_name.clone(),
            chapter_id: meta.chapter_id.clone(),
            chapter_name: meta.chapter_name.clone(),
        })
        .unwrap_or_default();

    let sources: Vec<SourceInfo> = top_texts
        .iter()
        .map(|text| {
            let meta = meta_by_text.get(text);
            SourceInfo {
                text: text.clone(),
                page_number: meta.and_then(|meta| meta.page_number),
                subject_name: meta.and_then(|meta| meta.subject_name.clone()),
                chapter_name: meta.and_then(|meta| meta.chapter_name.clone()),
                image_url: meta.and_then(|meta| meta.image_url.clone()),
            }
        })
        .collect();

    SelectedContexts {
        sources,
        primary_meta,
    }
}
