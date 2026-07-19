use reqwest::Client;
use serde::{Deserialize, Serialize};
use serde_json::{json, Value};

use crate::{
    config::Config,
    error::ApiError,
    models::{AiAnswer, AiChatRequest, ChatPromptMessage},
};

#[derive(Clone)]
pub struct AiGateway {
    config: Config,
    client: Client,
}

#[derive(Debug, Deserialize)]
struct ChatResponse {
    choices: Vec<ChatChoice>,
    usage: Option<Usage>,
}

#[derive(Debug, Deserialize)]
struct ChatChoice {
    message: ChatMessage,
}

#[derive(Debug, Deserialize)]
struct ChatMessage {
    content: Option<String>,
}

#[derive(Debug, Deserialize)]
struct Usage {
    prompt_tokens: Option<i32>,
    completion_tokens: Option<i32>,
}

#[derive(Debug, Deserialize)]
struct EmbeddingResponse {
    data: Vec<EmbeddingItem>,
}

#[derive(Debug, Deserialize)]
struct EmbeddingItem {
    embedding: Vec<f32>,
}

#[derive(Debug, Deserialize)]
struct RerankResponse {
    results: Option<Vec<RerankItem>>,
}

#[derive(Debug, Deserialize)]
struct RerankItem {
    index: usize,
    relevance_score: Option<f32>,
}

#[derive(Debug, Serialize)]
struct ProviderMessage<'a> {
    role: &'a str,
    content: &'a str,
}

impl AiGateway {
    pub fn new(config: Config) -> Self {
        Self {
            config,
            client: Client::new(),
        }
    }

    pub async fn chat(
        &self,
        request: &AiChatRequest,
        selected_contexts: &[String],
    ) -> Result<AiAnswer, ApiError> {
        let provider = self.config.provider()?;
        let question = request
            .question
            .as_deref()
            .or(request.message.as_deref())
            .or(request.content.as_deref())
            .map(str::trim)
            .filter(|value| !value.is_empty())
            .ok_or_else(|| ApiError::BadRequest("question is required".into()))?;

        let rich =
            request.rich_answer == Some(true) || request.answer_format.as_deref() == Some("rich");
        let json_mode =
            request.json_mode == Some(true) || request.response_format.as_deref() == Some("json");
        let model = choose_model(&self.config, request, question);
        let system = build_system_prompt(request, selected_contexts, rich, json_mode);

        let mut messages = vec![ProviderMessage {
            role: "system",
            content: &system,
        }];
        let mut history = request.history.clone().unwrap_or_default();
        if history.len() > 18 {
            history = history.split_off(history.len() - 18);
        }
        let history_strings: Vec<ChatPromptMessage> = history;
        let mut owned_messages = Vec::new();
        for item in &history_strings {
            owned_messages.push(ProviderMessage {
                role: item.role.as_str(),
                content: item.content.as_str(),
            });
        }
        messages.extend(owned_messages);
        messages.push(ProviderMessage {
            role: "user",
            content: question,
        });

        let body = json!({
            "model": model,
            "messages": messages,
            "temperature": request.temperature.unwrap_or(if request.reasoning_level.as_deref() == Some("high") { 0.35 } else { 0.25 }),
            "max_tokens": request.max_tokens.unwrap_or(if rich { 6000 } else if request.response_length.as_deref() == Some("large") { 4096 } else { 2048 }),
            "response_format": if json_mode || rich { json!({"type": "json_object"}) } else { Value::Null }
        });

        let response = self
            .client
            .post(format!("{}/chat/completions", provider.base_url))
            .headers(provider_headers(&provider.api_key, &self.config.app_url))
            .json(&body)
            .send()
            .await
            .map_err(|error| ApiError::Upstream(error.to_string()))?;

        if !response.status().is_success() {
            let status = response.status();
            let text = response.text().await.unwrap_or_default();
            return Err(ApiError::Upstream(format!(
                "AI provider failed ({status}): {text}"
            )));
        }

        let data: ChatResponse = response
            .json()
            .await
            .map_err(|error| ApiError::Upstream(error.to_string()))?;
        let content = data
            .choices
            .first()
            .and_then(|choice| choice.message.content.clone())
            .unwrap_or_default()
            .trim()
            .to_string();
        if content.is_empty() {
            return Err(ApiError::Upstream(
                "AI provider returned empty content".into(),
            ));
        }
        let input_tokens = data
            .usage
            .as_ref()
            .and_then(|u| u.prompt_tokens)
            .unwrap_or(0);
        let output_tokens = data
            .usage
            .as_ref()
            .and_then(|u| u.completion_tokens)
            .unwrap_or_else(|| estimate_tokens(&content));

        Ok(AiAnswer {
            content,
            served_from: "model".into(),
            model,
            provider: provider.name.into(),
            input_tokens,
            output_tokens,
            source_chunks: selected_contexts.to_vec(),
        })
    }

    pub async fn embed(&self, text: &str) -> Result<Vec<f32>, ApiError> {
        let provider = self.config.provider()?;
        let response = self
            .client
            .post(format!("{}/embeddings", provider.base_url))
            .headers(provider_headers(&provider.api_key, &self.config.app_url))
            .json(&json!({
                "model": self.config.embedding_model,
                "input": text,
            }))
            .send()
            .await
            .map_err(|error| ApiError::Upstream(error.to_string()))?;

        if !response.status().is_success() {
            return Ok(vec![]);
        }

        let data: EmbeddingResponse = response
            .json()
            .await
            .map_err(|error| ApiError::Upstream(error.to_string()))?;
        Ok(data
            .data
            .first()
            .map(|item| item.embedding.clone())
            .unwrap_or_default())
    }

    pub async fn rerank(&self, question: &str, documents: &[String]) -> Vec<String> {
        if documents.len() <= 1 {
            return documents.to_vec();
        }
        let Ok(provider) = self.config.provider() else {
            return keyword_rerank(question, documents);
        };
        let response = self
            .client
            .post(format!("{}/rerank", provider.base_url))
            .headers(provider_headers(&provider.api_key, &self.config.app_url))
            .json(&json!({
                "model": self.config.rerank_model,
                "query": question,
                "documents": documents,
            }))
            .send()
            .await;

        let Ok(response) = response else {
            return keyword_rerank(question, documents);
        };
        if !response.status().is_success() {
            return keyword_rerank(question, documents);
        }
        let Ok(data) = response.json::<RerankResponse>().await else {
            return keyword_rerank(question, documents);
        };
        let mut ranked = data.results.unwrap_or_default();
        ranked.sort_by(|a, b| {
            b.relevance_score
                .unwrap_or(0.0)
                .total_cmp(&a.relevance_score.unwrap_or(0.0))
        });
        let output: Vec<String> = ranked
            .into_iter()
            .filter_map(|item| documents.get(item.index).cloned())
            .collect();
        if output.is_empty() {
            keyword_rerank(question, documents)
        } else {
            output
        }
    }
}

fn provider_headers(api_key: &str, app_url: &str) -> reqwest::header::HeaderMap {
    let mut headers = reqwest::header::HeaderMap::new();
    headers.insert(
        reqwest::header::AUTHORIZATION,
        format!("Bearer {api_key}")
            .parse()
            .expect("valid auth header"),
    );
    headers.insert(
        "HTTP-Referer",
        app_url.parse().expect("valid app url header"),
    );
    headers.insert(
        "X-OpenRouter-Title",
        "Right Answer".parse().expect("valid title header"),
    );
    headers
}

fn choose_model(config: &Config, request: &AiChatRequest, question: &str) -> String {
    let high = request.reasoning_level.as_deref() == Some("high")
        || request.response_length.as_deref() == Some("large")
        || question.len() > 320;
    if high {
        config.reasoning_model.clone()
    } else {
        config.simple_model.clone()
    }
}

fn build_system_prompt(
    request: &AiChatRequest,
    contexts: &[String],
    rich: bool,
    json_mode: bool,
) -> String {
    if let Some(system) = request
        .system_prompt
        .as_ref()
        .filter(|s| !s.trim().is_empty())
    {
        return append_context(system, contexts);
    }

    let mut lines = vec![
        "You are Right Answer, a careful AI study partner for school students.".to_string(),
        "Answer directly and stay grounded in supplied textbook context.".to_string(),
    ];
    if let Some(subject) = &request.subject_name {
        lines.push(format!("Subject: {subject}."));
    }
    if let Some(language) = &request.response_language {
        lines.push(format!("Respond in {language}."));
    }
    lines.push(format!(
        "Response length: {}.",
        request.response_length.as_deref().unwrap_or("normal")
    ));
    lines.push(format!(
        "Reasoning depth: {}.",
        request.reasoning_level.as_deref().unwrap_or("mid")
    ));
    if rich && !json_mode {
        lines.push("Return valid JSON using schema right_answer.rich_answer.v1 with renderMarkdown, speechText, blocks, sources, needsMoreContext, and limitations.".into());
        lines.push("Use Markdown, LaTeX, tables, charts, geometry, SVG, images, code, or timeline blocks only when useful.".into());
        lines.push("speechText must be clean speaker-only prose without #, *, Markdown tables, raw LaTeX, code fences, or JSON.".into());
    }
    append_context(&lines.join("\n"), contexts)
}

fn append_context(base: &str, contexts: &[String]) -> String {
    if contexts.is_empty() {
        base.to_string()
    } else {
        format!(
            "{base}\n\nSelected textbook context:\n{}",
            contexts.join("\n\n")
        )
    }
}

fn keyword_rerank(question: &str, documents: &[String]) -> Vec<String> {
    let tokens: std::collections::HashSet<String> = question
        .split_whitespace()
        .map(|s| s.to_lowercase())
        .collect();
    let mut docs = documents.to_vec();
    docs.sort_by_key(|doc| {
        let score = doc
            .split_whitespace()
            .filter(|word| tokens.contains(&word.to_lowercase()))
            .count();
        std::cmp::Reverse(score)
    });
    docs
}

fn estimate_tokens(text: &str) -> i32 {
    ((text.len() as f32) / 4.0).ceil() as i32
}
