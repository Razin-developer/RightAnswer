use std::env;

use anyhow::{anyhow, Context};

#[derive(Clone, Debug)]
pub struct Config {
    pub port: u16,
    pub database_url: String,
    pub jwt_secret: String,
    pub app_url: String,
    pub cors_origins: Vec<String>,
    pub ai_method: AiMethod,
    pub openrouter_api_key: Option<String>,
    pub hackai_api_key: Option<String>,
    pub nvidia_api_key: Option<String>,
    pub simple_model: String,
    pub reasoning_model: String,
    pub embedding_model: String,
    pub rerank_model: String,
    /// Config-only for now: no image-input path exists in AiChatRequest yet,
    /// so these aren't wired into any chat call. Present so switching
    /// AI_MODEL_FAMILY=qwen has the right values ready once image input
    /// lands.
    #[allow(dead_code)]
    pub vlm_thinking_model: String,
    #[allow(dead_code)]
    pub vlm_instruct_model: String,
    pub qdrant_url: String,
    pub qdrant_api_key: Option<String>,
    pub qdrant_collection: String,
    pub semantic_cache_threshold: f32,
    pub plans: PlanConfig,
}

/// Per-tier limits and pricing for the plan system — every value is
/// env-overridable (settable over SSH without a redeploy needing a code
/// change) so pricing/limits can be tuned as real usage data comes in.
#[derive(Clone, Debug)]
pub struct PlanConfig {
    pub hobby_daily_question_limit: i64,
    pub hobby_weekly_credit_usd: f64,
    pub pro_daily_question_limit: i64,
    pub pro_weekly_credit_usd: f64,
    pub pro_price_inr: i64,
    pub pro_credits_usd: f64,
    pub scholar_daily_question_limit: i64,
    pub scholar_weekly_credit_usd: f64,
    pub scholar_price_inr: i64,
    pub scholar_credits_usd: f64,
    /// Percent of the tighter of (daily question limit, weekly credit
    /// limit) at which the client should show a dismissible usage warning
    /// banner — e.g. 90 means "warn once 90% used / 10% remaining".
    pub usage_warning_threshold_percent: f64,
}

impl PlanConfig {
    fn from_env() -> Self {
        Self {
            hobby_daily_question_limit: read("PLAN_HOBBY_DAILY_QUESTION_LIMIT")
                .and_then(|v| v.parse().ok())
                .unwrap_or(15),
            hobby_weekly_credit_usd: read("PLAN_HOBBY_WEEKLY_CREDIT_USD")
                .and_then(|v| v.parse().ok())
                .unwrap_or(0.5),
            pro_daily_question_limit: read("PLAN_PRO_DAILY_QUESTION_LIMIT")
                .and_then(|v| v.parse().ok())
                .unwrap_or(150),
            pro_weekly_credit_usd: read("PLAN_PRO_WEEKLY_CREDIT_USD")
                .and_then(|v| v.parse().ok())
                .unwrap_or(5.0),
            pro_price_inr: read("PLAN_PRO_PRICE_INR")
                .and_then(|v| v.parse().ok())
                .unwrap_or(200),
            pro_credits_usd: read("PLAN_PRO_CREDITS_USD")
                .and_then(|v| v.parse().ok())
                .unwrap_or(5.0),
            scholar_daily_question_limit: read("PLAN_SCHOLAR_DAILY_QUESTION_LIMIT")
                .and_then(|v| v.parse().ok())
                .unwrap_or(400),
            scholar_weekly_credit_usd: read("PLAN_SCHOLAR_WEEKLY_CREDIT_USD")
                .and_then(|v| v.parse().ok())
                .unwrap_or(15.0),
            scholar_price_inr: read("PLAN_SCHOLAR_PRICE_INR")
                .and_then(|v| v.parse().ok())
                .unwrap_or(1000),
            scholar_credits_usd: read("PLAN_SCHOLAR_CREDITS_USD")
                .and_then(|v| v.parse().ok())
                .unwrap_or(25.0),
            usage_warning_threshold_percent: read("USAGE_WARNING_THRESHOLD_PERCENT")
                .and_then(|v| v.parse().ok())
                .unwrap_or(90.0),
        }
    }
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub enum AiMethod {
    OpenRouter,
    HackAi,
}

/// Which model family's names to default to for chat/vision, when the
/// specific AI_*_MODEL env vars aren't set. Both families route through
/// whichever provider AI_METHOD selects — no separate API key needed.
#[derive(Clone, Debug, PartialEq, Eq)]
pub enum ModelFamily {
    Gemma,
    Qwen,
}

#[derive(Clone, Debug)]
pub struct ProviderConfig {
    pub name: &'static str,
    pub base_url: &'static str,
    pub api_key: String,
}

impl Config {
    pub fn from_env() -> anyhow::Result<Self> {
        let ai_method = match read("AI_METHOD")
            .or_else(|| read("AI_METHOS"))
            .unwrap_or_else(|| "openrouter".to_string())
            .to_lowercase()
            .as_str()
        {
            "hackai" | "hack_ai" | "hackclub" => AiMethod::HackAi,
            "openrouter" => AiMethod::OpenRouter,
            other => return Err(anyhow!("unsupported AI_METHOD: {other}")),
        };

        let model_family = match read("AI_MODEL_FAMILY")
            .unwrap_or_else(|| "gemma".to_string())
            .to_lowercase()
            .as_str()
        {
            "qwen" => ModelFamily::Qwen,
            "gemma" => ModelFamily::Gemma,
            other => return Err(anyhow!("unsupported AI_MODEL_FAMILY: {other}")),
        };
        let (default_simple, default_reasoning, default_vlm_thinking, default_vlm_instruct) =
            match model_family {
                ModelFamily::Gemma => (
                    "google/gemma-3-12b-it",
                    "google/gemma-4-31b-it",
                    "google/gemma-3-12b-it",
                    "google/gemma-3-12b-it",
                ),
                ModelFamily::Qwen => (
                    "qwen/qwen3-8b",
                    "qwen/qwen3-14b",
                    "qwen/qwen3-vl-8b-thinking",
                    "qwen/qwen3-vl-8b-instruct",
                ),
            };

        Ok(Self {
            port: read("PORT").and_then(|v| v.parse().ok()).unwrap_or(4000),
            database_url: read("DATABASE_URL").context("DATABASE_URL is required")?,
            jwt_secret: read("JWT_SECRET").context(
                "JWT_SECRET is required (no insecure default is provided; set a long random value)",
            )?,
            app_url: read("APP_URL")
                .or_else(|| read("NEXT_PUBLIC_APP_URL"))
                .unwrap_or_else(|| "http://localhost:3000".into()),
            cors_origins: read("CORS_ORIGINS")
                .map(|value| {
                    value
                        .split(',')
                        .map(str::trim)
                        .filter(|value| !value.is_empty())
                        .map(ToString::to_string)
                        .collect()
                })
                .unwrap_or_default(),
            ai_method,
            openrouter_api_key: read("OPENROUTER_API_KEY").or_else(|| read("openrouter_api_key")),
            hackai_api_key: read("HACKAI_API_KEY").or_else(|| read("hackai_api_key")),
            nvidia_api_key: read("NVIDIA_API_KEY"),
            simple_model: read("AI_SIMPLE_MODEL").unwrap_or_else(|| default_simple.into()),
            reasoning_model: read("AI_REASONING_MODEL").unwrap_or_else(|| default_reasoning.into()),
            embedding_model: read("AI_EMBEDDING_MODEL")
                .unwrap_or_else(|| "perplexity/pplx-embed-v1-0.6b".into()),
            rerank_model: read("AI_RERANK_MODEL")
                .unwrap_or_else(|| "nvidia/rerank-qa-mistral-4b".into()),
            vlm_thinking_model: read("AI_VLM_THINKING_MODEL")
                .unwrap_or_else(|| default_vlm_thinking.into()),
            vlm_instruct_model: read("AI_VLM_INSTRUCT_MODEL")
                .unwrap_or_else(|| default_vlm_instruct.into()),
            qdrant_url: read("QDRANT_URL").unwrap_or_else(|| "http://localhost:6333".into()),
            qdrant_api_key: read("QDRANT_API_KEY"),
            qdrant_collection: read("QDRANT_COLLECTION")
                .unwrap_or_else(|| "right_answer_textbook_chunks".into()),
            semantic_cache_threshold: read("SEMANTIC_CACHE_THRESHOLD")
                .and_then(|value| value.parse().ok())
                .unwrap_or(0.90),
            plans: PlanConfig::from_env(),
        })
    }

    pub fn provider(&self) -> anyhow::Result<ProviderConfig> {
        match self.ai_method {
            AiMethod::OpenRouter => Ok(ProviderConfig {
                name: "openrouter",
                base_url: "https://openrouter.ai/api/v1",
                api_key: self
                    .openrouter_api_key
                    .clone()
                    .context("OPENROUTER_API_KEY is required")?,
            }),
            AiMethod::HackAi => Ok(ProviderConfig {
                name: "hackai",
                base_url: "https://ai.hackclub.com/proxy/v1",
                api_key: self
                    .hackai_api_key
                    .clone()
                    .context("HACKAI_API_KEY is required")?,
            }),
        }
    }
}

fn read(key: &str) -> Option<String> {
    env::var(key).ok().filter(|value| !value.trim().is_empty())
}
