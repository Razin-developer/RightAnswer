use reqwest::Client;
use serde::{Deserialize, Serialize};
use serde_json::{json, Value};

use crate::{config::Config, error::ApiError};

#[derive(Clone)]
pub struct QdrantGateway {
    config: Config,
    client: Client,
}

#[derive(Debug, Serialize, Deserialize)]
pub struct RetrievedChunk {
    pub id: String,
    pub text: String,
    pub score: f32,
    pub page_number: Option<i32>,
    pub image_url: Option<String>,
    pub content_type: Option<String>,
    pub subject_id: Option<String>,
    pub subject_name: Option<String>,
    pub chapter_id: Option<String>,
    pub chapter_name: Option<String>,
}

impl QdrantGateway {
    pub fn new(config: Config) -> Self {
        Self {
            config,
            client: Client::new(),
        }
    }

    pub async fn search(
        &self,
        query_vector: &[f32],
        chapter_ids: &[String],
        limit: usize,
    ) -> Result<Vec<RetrievedChunk>, ApiError> {
        if query_vector.is_empty() {
            return Ok(vec![]);
        }

        let mut body = json!({
            "vector": query_vector,
            "limit": limit,
            "with_payload": true,
        });
        if !chapter_ids.is_empty() {
            body["filter"] = json!({
                "must": [{
                    "key": "chapter_id",
                    "match": { "any": chapter_ids }
                }]
            });
        }

        let mut request = self.client.post(format!(
            "{}/collections/{}/points/search",
            self.config.qdrant_url.trim_end_matches('/'),
            self.config.qdrant_collection
        ));
        if let Some(key) = &self.config.qdrant_api_key {
            request = request.header("api-key", key);
        }

        let response = request
            .json(&body)
            .send()
            .await
            .map_err(|error| ApiError::Upstream(error.to_string()))?;

        if !response.status().is_success() {
            return Ok(vec![]);
        }

        let value: Value = response
            .json()
            .await
            .map_err(|error| ApiError::Upstream(error.to_string()))?;
        let result = value["result"].as_array().cloned().unwrap_or_default();
        Ok(result
            .into_iter()
            .filter_map(|point| {
                let payload = point["payload"].as_object()?;
                let text = payload.get("text")?.as_str()?.to_string();
                Some(RetrievedChunk {
                    id: point["id"].to_string(),
                    text,
                    score: point["score"].as_f64().unwrap_or_default() as f32,
                    page_number: payload
                        .get("page_number")
                        .and_then(|value| value.as_i64())
                        .map(|value| value as i32),
                    image_url: payload
                        .get("image_url")
                        .and_then(|value| value.as_str())
                        .map(ToString::to_string),
                    content_type: payload
                        .get("content_type")
                        .and_then(|value| value.as_str())
                        .map(ToString::to_string),
                    subject_id: payload
                        .get("subject_id")
                        .and_then(|value| value.as_str())
                        .map(ToString::to_string),
                    subject_name: payload
                        .get("subject_name")
                        .and_then(|value| value.as_str())
                        .map(ToString::to_string),
                    chapter_id: payload
                        .get("chapter_id")
                        .and_then(|value| value.as_str())
                        .map(ToString::to_string),
                    chapter_name: payload
                        .get("chapter_name")
                        .and_then(|value| value.as_str())
                        .map(ToString::to_string),
                })
            })
            .collect())
    }
}
