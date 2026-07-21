use reqwest::Client;
use serde::{Deserialize, Serialize};
use serde_json::{json, Value};

use crate::{
    config::{Config, ProviderConfig},
    error::ApiError,
    models::{AiAnswer, AiChatRequest, ChatPromptMessage, SourceInfo},
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
    rankings: Option<Vec<RerankItem>>,
}

#[derive(Debug, Deserialize)]
struct RerankItem {
    index: usize,
    logit: Option<f32>,
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
        selected_sources: &[SourceInfo],
    ) -> Result<AiAnswer, ApiError> {
        let selected_contexts: Vec<String> =
            selected_sources.iter().map(|s| s.text.clone()).collect();
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
        let system = build_system_prompt(request, &selected_contexts, rich, json_mode);

        let mut messages = vec![ProviderMessage {
            role: "system",
            content: &system,
        }];
        // Trimmed from 18 to 12 turns: older turns rarely change the answer
        // to the current question but cost real tokens on every request.
        let mut history = request.history.clone().unwrap_or_default();
        if history.len() > 12 {
            history = history.split_off(history.len() - 12);
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
        let raw_content = data
            .choices
            .first()
            .and_then(|choice| choice.message.content.clone())
            .unwrap_or_default()
            .trim()
            .to_string();
        if raw_content.is_empty() {
            return Err(ApiError::Upstream(
                "AI provider returned empty content".into(),
            ));
        }

        // When json_mode/rich was requested, the model returns a JSON
        // envelope rather than plain prose. Extract the human-readable
        // display text from it instead of showing the raw JSON blob to the
        // user — a prior bug did exactly that, making answers appear
        // blank/garbled in the app whenever the model (or a client-supplied
        // system prompt) used a different JSON schema than expected.
        let extracted = if json_mode || rich {
            extract_rich_envelope(&raw_content)
        } else {
            None
        };
        let content = extracted
            .as_ref()
            .and_then(|envelope| envelope.display_text.clone())
            .filter(|text| !text.trim().is_empty())
            .unwrap_or(raw_content);
        // A degenerate JSON envelope (e.g. "{}") with no usable field falls
        // through to here as raw_content itself — better to surface this as
        // an upstream failure than silently show "{}" as if it were a real
        // answer.
        if content.trim().is_empty() || content.trim() == "{}" {
            return Err(ApiError::Upstream(
                "AI provider returned an empty/degenerate response".into(),
            ));
        }
        let mut speech_text = extracted.as_ref().and_then(|e| e.speech_text.clone());
        let mut blocks = extracted.as_ref().and_then(|e| e.blocks.clone());
        let mut content = content;
        let mut final_model = model.clone();

        let mut input_tokens = data
            .usage
            .as_ref()
            .and_then(|u| u.prompt_tokens)
            .unwrap_or(0);
        let mut output_tokens = data
            .usage
            .as_ref()
            .and_then(|u| u.completion_tokens)
            .unwrap_or_else(|| estimate_tokens(&content));

        // Most questions are answerable from text alone — a second,
        // vision-model call only happens when the first pass explicitly
        // says it needs to actually see a page image (a diagram, graph, or
        // table) to answer precisely, and a retrieved source has one. This
        // keeps the common case at one call/one token budget instead of
        // always paying for a vision call up front.
        let needs_visual_source = extracted
            .as_ref()
            .map(|e| e.needs_visual_source)
            .unwrap_or(false);
        if rich && needs_visual_source {
            if let Some(image_url) = selected_sources
                .iter()
                .find_map(|source| source.image_url.as_deref())
            {
                if let Ok(visual) = self
                    .chat_with_image(request, question, image_url, &provider)
                    .await
                {
                    content = visual.content;
                    speech_text = visual.speech_text.or(speech_text);
                    blocks = visual.blocks.or(blocks);
                    final_model = visual.model;
                    input_tokens += visual.input_tokens;
                    output_tokens += visual.output_tokens;
                }
                // A failed/degenerate vision pass silently keeps the
                // text-only pass-1 answer rather than erroring the whole
                // request — a refinement attempt, not a requirement.
            }
        }

        Ok(AiAnswer {
            content,
            speech_text,
            blocks,
            served_from: "model".into(),
            model: final_model,
            provider: provider.name.into(),
            input_tokens,
            output_tokens,
            source_chunks: selected_contexts,
            sources: selected_sources.to_vec(),
        })
    }

    /// Second-pass refinement call: sends the flagged source's page image to
    /// a vision-capable model with a deliberately short prompt (no need to
    /// resend the full multi-chunk text context — pass 1 already used that
    /// to identify which image matters; this pass just needs to look at it
    /// and answer precisely).
    async fn chat_with_image(
        &self,
        request: &AiChatRequest,
        question: &str,
        image_url: &str,
        provider: &ProviderConfig,
    ) -> Result<AiAnswer, ApiError> {
        let model = if request.reasoning_level.as_deref() == Some("high") {
            self.config.vlm_thinking_model.clone()
        } else {
            self.config.vlm_instruct_model.clone()
        };

        let mut system = "You are Right Answer, a careful AI study partner. You already \
            drafted an answer but flagged that you needed to see the actual textbook page \
            image to be precise (a diagram, graph, or table). Look at the attached image and \
            give the final, accurate answer grounded in what it actually shows."
            .to_string();
        if let Some(language) = &request.response_language {
            system.push_str(&format!(" Respond in {language}."));
        }
        system.push_str(
            " Return valid JSON using schema right_answer.rich_answer.v1 with renderMarkdown, \
            speechText, and blocks. renderMarkdown must be a non-empty, complete answer.",
        );

        let body = json!({
            "model": model,
            "messages": [
                {"role": "system", "content": system},
                {"role": "user", "content": [
                    {"type": "text", "text": question},
                    {"type": "image_url", "image_url": {"url": image_url}}
                ]}
            ],
            "temperature": 0.25,
            "max_tokens": 2048,
            "response_format": {"type": "json_object"}
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
                "Vision AI provider failed ({status}): {text}"
            )));
        }

        let data: ChatResponse = response
            .json()
            .await
            .map_err(|error| ApiError::Upstream(error.to_string()))?;
        let raw_content = data
            .choices
            .first()
            .and_then(|choice| choice.message.content.clone())
            .unwrap_or_default()
            .trim()
            .to_string();

        let envelope = extract_rich_envelope(&raw_content);
        let content = envelope
            .as_ref()
            .and_then(|e| e.display_text.clone())
            .filter(|text| !text.trim().is_empty())
            .ok_or_else(|| ApiError::Upstream("Vision pass returned no usable text".into()))?;

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
            speech_text: envelope.as_ref().and_then(|e| e.speech_text.clone()),
            blocks: envelope.as_ref().and_then(|e| e.blocks.clone()),
            served_from: "model".into(),
            model,
            provider: provider.name.into(),
            input_tokens,
            output_tokens,
            source_chunks: Vec::new(),
            sources: Vec::new(),
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

    /// Reranking always goes through NVIDIA's dedicated reranking API,
    /// independent of AI_METHOD (which only governs chat/embeddings). Falls
    /// back to a local keyword heuristic if the key is missing or the call
    /// fails, so retrieval quality degrades gracefully rather than erroring.
    pub async fn rerank(&self, question: &str, documents: &[String]) -> Vec<String> {
        if documents.len() <= 1 {
            return documents.to_vec();
        }
        let Some(api_key) = self.config.nvidia_api_key.as_deref() else {
            return keyword_rerank(question, documents);
        };

        let passages: Vec<Value> = documents
            .iter()
            .map(|text| json!({ "text": text }))
            .collect();
        let response = self
            .client
            .post("https://ai.api.nvidia.com/v1/retrieval/nvidia/reranking")
            .header(reqwest::header::AUTHORIZATION, format!("Bearer {api_key}"))
            .json(&json!({
                "model": self.config.rerank_model,
                "query": { "text": question },
                "passages": passages,
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
        let mut ranked = data.rankings.unwrap_or_default();
        ranked.sort_by(|a, b| b.logit.unwrap_or(0.0).total_cmp(&a.logit.unwrap_or(0.0)));
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

struct RichEnvelope {
    display_text: Option<String>,
    speech_text: Option<String>,
    blocks: Option<Value>,
    needs_visual_source: bool,
}

/// Parses a model response that was requested in json_mode/rich mode.
/// Tolerant of a couple of schema shapes seen in practice (the backend's
/// own right_answer.rich_answer.v1 schema using `renderMarkdown`, and a
/// simpler `{"answer": "..."}` shape some client-supplied system prompts
/// use) and of models wrapping JSON in a ```json fenced code block.
fn extract_rich_envelope(raw: &str) -> Option<RichEnvelope> {
    let trimmed = raw.trim();
    let unfenced = trimmed
        .strip_prefix("```json")
        .or_else(|| trimmed.strip_prefix("```"))
        .map(str::trim_start)
        .and_then(|value| value.strip_suffix("```"))
        .map(str::trim)
        .unwrap_or(trimmed);

    let value: Value = serde_json::from_str(unfenced).ok()?;
    let object = value.as_object()?;

    let display_text = object
        .get("renderMarkdown")
        .or_else(|| object.get("answer"))
        .or_else(|| object.get("content"))
        .or_else(|| object.get("text"))
        .and_then(Value::as_str)
        .map(str::to_string);

    let speech_text = object
        .get("speechText")
        .and_then(Value::as_str)
        .map(str::to_string);

    let blocks = object.get("blocks").cloned();

    let needs_visual_source = object
        .get("needsVisualSource")
        .and_then(Value::as_bool)
        .unwrap_or(false);

    Some(RichEnvelope {
        display_text,
        speech_text,
        blocks,
        needs_visual_source,
    })
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
    if rich || json_mode {
        // Whenever JSON output is requested at all (rich or plain json_mode),
        // the model must be told what shape to use — leaving it unguided
        // while forcing response_format=json_object produces degenerate
        // output like "{}" for anything without an obvious canonical shape.
        lines.push("Return valid JSON using schema right_answer.rich_answer.v1 with renderMarkdown, speechText, blocks, needsVisualSource, sources, needsMoreContext, and limitations. renderMarkdown must always be a non-empty, complete answer to the question.".into());
        lines.push("Use Markdown, LaTeX, tables, charts, geometry, SVG, images, code, or timeline blocks only when useful. A chart/graph block should appear whenever the answer describes data, trends, or comparisons the context provides numbers for.".into());
        lines.push("Set needsVisualSource: true only if you cannot answer precisely without actually seeing a diagram/graph/table image from the source page (not just describing one from text) — most questions don't need this. Still give your best text answer in renderMarkdown either way; a follow-up pass with the image may refine it.".into());
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
