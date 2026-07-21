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
        })
        .collect();

    let explicit_chapter_ids = request.chapter_ids.clone().unwrap_or_default();
    let confirmed_chapter_id = request.confirm_beta_chapter_id.clone();

    let owned_embedding;
    let embedding = if let Some(embedding) = question_embedding {
        embedding
    } else {
        owned_embedding = state.ai.embed(question).await.unwrap_or_default();
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

    // Beta gate: peek at the best match (embeddings only, no rerank —
    // rerank is comparatively expensive and unnecessary just to classify
    // readiness) before committing to a real answer.
    let peek_scope: Vec<String> = if explicit_chapter_ids.is_empty() {
        Vec::new()
    } else {
        explicit_chapter_ids.clone()
    };
    let peek = state
        .qdrant
        .search(embedding, &peek_scope, 3)
        .await
        .unwrap_or_default();
    if let Some(top) = peek.first() {
        let already_confirmed = confirmed_chapter_id.is_some()
            && confirmed_chapter_id.as_deref() == top.chapter_id.as_deref();
        if !already_confirmed {
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

    let search_scope: Vec<String> = if !explicit_chapter_ids.is_empty() {
        explicit_chapter_ids
    } else {
        let mut ids: Vec<String> = chapter_index
            .iter()
            .filter(|info| info.enabled)
            .map(|info| info.chapter_id.clone())
            .collect();
        if let Some(id) = confirmed_chapter_id {
            if !ids.contains(&id) {
                ids.push(id);
            }
        }
        ids
    };
    let retrieved = state
        .qdrant
        .search(embedding, &search_scope, 12)
        .await
        .unwrap_or_default();

    Ok(ContextsOutcome::Ready(
        finalize(direct_sources, retrieved, question, state).await,
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
        let image = chunk
            .image_url
            .clone()
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
            }
        })
        .collect();

    SelectedContexts {
        sources,
        primary_meta,
    }
}
