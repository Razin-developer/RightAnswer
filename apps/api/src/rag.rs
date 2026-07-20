use std::collections::HashMap;

use crate::{error::ApiError, models::AiChatRequest, routes::AppState};

#[derive(Default, Clone)]
pub struct ContextMeta {
    pub subject_id: Option<String>,
    pub subject_name: Option<String>,
    pub chapter_id: Option<String>,
    pub chapter_name: Option<String>,
}

pub struct SelectedContexts {
    pub texts: Vec<String>,
    pub primary_meta: ContextMeta,
}

/// Retrieves and reranks context for a question. Subject/chapter selection
/// is fully server-driven: the client no longer picks a subject or chapter,
/// so retrieval always runs a global (or explicitly chapter-scoped, if
/// provided) vector search, and the top-ranked chunk's own metadata is used
/// to classify the resulting chat.
pub async fn select_contexts(
    state: &AppState,
    request: &AiChatRequest,
    question: &str,
    question_embedding: Option<&[f32]>,
) -> Result<SelectedContexts, ApiError> {
    let direct_contexts = request
        .contexts
        .clone()
        .or_else(|| request.source_chunks.clone())
        .unwrap_or_default()
        .into_iter()
        .map(|value| value.trim().to_string())
        .filter(|value| !value.is_empty())
        .collect::<Vec<_>>();

    let mut candidates = direct_contexts;
    let mut meta_by_text: HashMap<String, ContextMeta> = HashMap::new();
    let chapter_ids = request.chapter_ids.clone().unwrap_or_default();

    let owned_embedding;
    let embedding = if let Some(embedding) = question_embedding {
        embedding
    } else {
        owned_embedding = state.ai.embed(question).await.unwrap_or_default();
        &owned_embedding
    };

    if !embedding.is_empty() {
        let retrieved = state
            .qdrant
            .search(embedding, &chapter_ids, 12)
            .await
            .unwrap_or_default();
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
                ContextMeta {
                    subject_id: chunk.subject_id,
                    subject_name: chunk.subject_name,
                    chapter_id: chunk.chapter_id,
                    chapter_name: chunk.chapter_name,
                },
            );
            candidates.push(text);
        }
    }

    if candidates.is_empty() {
        return Ok(SelectedContexts {
            texts: vec![],
            primary_meta: ContextMeta::default(),
        });
    }

    let ranked = state.ai.rerank(question, &candidates).await;
    let target = ranked.len().clamp(3, 5);
    let top: Vec<String> = ranked.into_iter().take(target).collect();

    let primary_meta = top
        .iter()
        .find_map(|text| meta_by_text.get(text).cloned())
        .unwrap_or_default();

    Ok(SelectedContexts {
        texts: top,
        primary_meta,
    })
}
