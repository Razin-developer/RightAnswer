use std::{env, process::ExitCode, time::Instant};

use reqwest::Client;
use serde_json::{json, Value};

/// Standalone smoke test for the configured AI provider (OpenRouter or
/// HackAI, per AI_METHOD) and API key. Exercises all four model roles the
/// app depends on: fast chat, reasoning chat, embeddings, and reranking.
/// Run after every deploy — a non-zero exit means something is broken
/// before real users hit it.
#[tokio::main]
async fn main() -> ExitCode {
    dotenvy::dotenv().ok();

    let ai_method = env::var("AI_METHOD").unwrap_or_else(|_| "openrouter".into());
    let (provider_name, base_url, api_key) = match ai_method.to_lowercase().as_str() {
        "hackai" => (
            "hackai",
            "https://ai.hackclub.com/proxy/v1",
            env::var("HACKAI_API_KEY").ok(),
        ),
        _ => (
            "openrouter",
            "https://openrouter.ai/api/v1",
            env::var("OPENROUTER_API_KEY").ok(),
        ),
    };

    let Some(api_key) = api_key.filter(|key| !key.trim().is_empty()) else {
        eprintln!(
            "FAIL  api-key        provider={provider_name} — no API key set for AI_METHOD={ai_method}"
        );
        return ExitCode::FAILURE;
    };

    let simple_model =
        env::var("AI_SIMPLE_MODEL").unwrap_or_else(|_| "google/gemma-3-12b-it".into());
    let reasoning_model =
        env::var("AI_REASONING_MODEL").unwrap_or_else(|_| "google/gemma-4-31b-it".into());
    let embedding_model = env::var("AI_EMBEDDING_MODEL")
        .unwrap_or_else(|_| "perplexity/pplx-embed-v1-0.6b".into());
    let rerank_model =
        env::var("AI_RERANK_MODEL").unwrap_or_else(|_| "nvidia/rerank-qa-mistral-4b".into());
    let nvidia_api_key = env::var("NVIDIA_API_KEY").ok();
    let app_url = env::var("APP_URL").unwrap_or_else(|_| "https://razin.hackclub.app".into());

    println!("Testing provider={provider_name} base_url={base_url}");

    let client = Client::new();
    let mut all_ok = true;

    all_ok &= run_check("chat:fast", &simple_model, || {
        chat_check(&client, base_url, &api_key, &app_url, &simple_model)
    })
    .await;

    all_ok &= run_check("chat:reasoning", &reasoning_model, || {
        chat_check(&client, base_url, &api_key, &app_url, &reasoning_model)
    })
    .await;

    all_ok &= run_check("embeddings", &embedding_model, || {
        embed_check(&client, base_url, &api_key, &app_url, &embedding_model)
    })
    .await;

    match nvidia_api_key.as_deref().filter(|key| !key.trim().is_empty()) {
        Some(nvidia_key) => {
            all_ok &= run_check("rerank", &rerank_model, || {
                rerank_check(&client, nvidia_key, &rerank_model)
            })
            .await;
        }
        None => {
            eprintln!(
                "FAIL  {:<15} model={rerank_model:<40} NVIDIA_API_KEY is not set — reranking will silently fall back to keyword search",
                "rerank"
            );
            all_ok = false;
        }
    }

    if all_ok {
        println!("\nAll AI provider checks passed.");
        ExitCode::SUCCESS
    } else {
        eprintln!("\nOne or more AI provider checks failed.");
        ExitCode::FAILURE
    }
}

async fn run_check<F, Fut>(label: &str, model: &str, check: F) -> bool
where
    F: FnOnce() -> Fut,
    Fut: std::future::Future<Output = Result<String, String>>,
{
    let start = Instant::now();
    match check().await {
        Ok(detail) => {
            println!(
                "PASS  {label:<15} model={model:<40} {:>5}ms  {detail}",
                start.elapsed().as_millis()
            );
            true
        }
        Err(error) => {
            eprintln!(
                "FAIL  {label:<15} model={model:<40} {:>5}ms  {error}",
                start.elapsed().as_millis()
            );
            false
        }
    }
}

fn headers(api_key: &str, app_url: &str) -> reqwest::header::HeaderMap {
    let mut headers = reqwest::header::HeaderMap::new();
    headers.insert(
        reqwest::header::AUTHORIZATION,
        format!("Bearer {api_key}").parse().expect("valid header"),
    );
    headers.insert("HTTP-Referer", app_url.parse().expect("valid header"));
    headers.insert(
        "X-OpenRouter-Title",
        "Right Answer".parse().expect("valid header"),
    );
    headers
}

async fn chat_check(
    client: &Client,
    base_url: &str,
    api_key: &str,
    app_url: &str,
    model: &str,
) -> Result<String, String> {
    let response = client
        .post(format!("{base_url}/chat/completions"))
        .headers(headers(api_key, app_url))
        .json(&json!({
            "model": model,
            "messages": [
                {"role": "user", "content": "Reply with exactly one word: pong"}
            ],
            "max_tokens": 8,
            "temperature": 0
        }))
        .send()
        .await
        .map_err(|error| format!("request failed: {error}"))?;

    let status = response.status();
    let body: Value = response
        .json()
        .await
        .map_err(|error| format!("status={status} invalid json: {error}"))?;

    if !status.is_success() {
        return Err(format!("status={status} body={body}"));
    }

    let content = body["choices"][0]["message"]["content"]
        .as_str()
        .unwrap_or_default()
        .trim();
    if content.is_empty() {
        return Err(format!("status={status} empty content, body={body}"));
    }
    Ok(format!("reply={content:?}"))
}

async fn embed_check(
    client: &Client,
    base_url: &str,
    api_key: &str,
    app_url: &str,
    model: &str,
) -> Result<String, String> {
    let response = client
        .post(format!("{base_url}/embeddings"))
        .headers(headers(api_key, app_url))
        .json(&json!({ "model": model, "input": "test embedding" }))
        .send()
        .await
        .map_err(|error| format!("request failed: {error}"))?;

    let status = response.status();
    let body: Value = response
        .json()
        .await
        .map_err(|error| format!("status={status} invalid json: {error}"))?;

    if !status.is_success() {
        return Err(format!("status={status} body={body}"));
    }

    let dims = body["data"][0]["embedding"]
        .as_array()
        .map(|values| values.len())
        .unwrap_or(0);
    if dims == 0 {
        return Err(format!("status={status} empty embedding, body={body}"));
    }
    Ok(format!("dims={dims}"))
}

async fn rerank_check(client: &Client, api_key: &str, model: &str) -> Result<String, String> {
    let passages = [
        json!({"text": "Photosynthesis converts light energy into chemical energy."}),
        json!({"text": "The Kerala backwaters are a network of lagoons and lakes."}),
        json!({"text": "Newton's second law relates force, mass, and acceleration."}),
    ];
    let response = client
        .post("https://integrate.api.nvidia.com/v1/retrieval/reranking")
        .header(reqwest::header::AUTHORIZATION, format!("Bearer {api_key}"))
        .json(&json!({
            "model": model,
            "query": "What is Newton's second law?",
            "passages": passages,
        }))
        .send()
        .await
        .map_err(|error| format!("request failed: {error}"))?;

    let status = response.status();
    let body: Value = response
        .json()
        .await
        .map_err(|error| format!("status={status} invalid json: {error}"))?;

    if !status.is_success() {
        return Err(format!("status={status} body={body}"));
    }

    let results = body["rankings"]
        .as_array()
        .map(|values| values.len())
        .unwrap_or(0);
    if results == 0 {
        return Err(format!("status={status} no rankings, body={body}"));
    }
    Ok(format!("ranked={results}"))
}
