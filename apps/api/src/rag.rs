use crate::{error::ApiError, models::AiChatRequest, routes::AppState};

pub async fn select_contexts(
    state: &AppState,
    request: &AiChatRequest,
    question: &str,
    question_embedding: Option<&[f32]>,
) -> Result<Vec<String>, ApiError> {
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
    let chapter_ids = request.chapter_ids.clone().unwrap_or_default();
    if !chapter_ids.is_empty() {
        let owned_embedding;
        let embedding = if let Some(embedding) = question_embedding {
            embedding
        } else {
            owned_embedding = state.ai.embed(question).await.unwrap_or_default();
            &owned_embedding
        };
        let retrieved = state
            .qdrant
            .search(embedding, &chapter_ids, 12)
            .await
            .unwrap_or_default();
        candidates.extend(retrieved.into_iter().map(|chunk| {
            let page = chunk
                .page_number
                .map(|page| format!("Page {page}: "))
                .unwrap_or_default();
            let image = chunk
                .image_url
                .map(|url| format!("\nImage: {url}"))
                .unwrap_or_default();
            format!("{page}{}{}", chunk.text, image)
        }));
    }

    if candidates.is_empty() {
        return Ok(vec![]);
    }

    let ranked = state.ai.rerank(question, &candidates).await;
    let target = ranked.len().clamp(3, 5);
    Ok(ranked.into_iter().take(target).collect())
}
