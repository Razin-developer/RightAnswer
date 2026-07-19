import json
import os
import sys
import traceback

import torch
import torch.nn.functional as F
from torch import Tensor
from transformers import AutoModel, AutoTokenizer


def last_token_pool(last_hidden_states: Tensor, attention_mask: Tensor) -> Tensor:
    left_padding = (attention_mask[:, -1].sum() == attention_mask.shape[0])
    if left_padding:
        return last_hidden_states[:, -1]

    sequence_lengths = attention_mask.sum(dim=1) - 1
    batch_size = last_hidden_states.shape[0]
    return last_hidden_states[
        torch.arange(batch_size, device=last_hidden_states.device), sequence_lengths
    ]


def mean_pool(last_hidden_states: Tensor, attention_mask: Tensor) -> Tensor:
    mask = attention_mask.unsqueeze(-1).to(last_hidden_states.dtype)
    masked = last_hidden_states * mask
    summed = masked.sum(dim=1)
    counts = mask.sum(dim=1).clamp(min=1)
    return summed / counts


MODEL_ID = os.environ.get("RIGHT_ANSWER_EMBEDDING_MODEL", "perplexity-ai/pplx-embed-v1-0.6b")
MAX_LENGTH = int(os.environ.get("RIGHT_ANSWER_EMBEDDING_MAX_LENGTH", "2048"))
CPU_THREADS = int(os.environ.get("RIGHT_ANSWER_EMBEDDING_THREADS", "8"))
QUERY_INSTRUCTION = os.environ.get(
    "RIGHT_ANSWER_QUERY_INSTRUCTION",
    "Given a Kerala SSLC student question, retrieve the most relevant textbook passages that answer it.",
)


def infer_default_dimensions(model_id: str) -> int:
    if "pplx-embed-v1-4b" in model_id or "pplx-embed-context-v1-4b" in model_id:
        return 2560
    if "pplx-embed-v1-0.6b" in model_id or "pplx-embed-context-v1-0.6b" in model_id:
        return 1024
    if "Qwen3-Embedding-8B" in model_id:
        return 4096
    if "Qwen3-Embedding-4B" in model_id:
        return 2560
    return 1024


OUTPUT_DIMENSIONS = int(
    os.environ.get("RIGHT_ANSWER_EMBEDDING_DIMENSIONS", str(infer_default_dimensions(MODEL_ID)))
)


def infer_model_family(model_id: str) -> str:
    normalized = model_id.lower()
    if "pplx-embed" in normalized or "perplexity-ai/" in normalized:
        return "pplx"
    if "qwen3-embedding" in normalized:
        return "qwen"
    return "generic"


MODEL_FAMILY = infer_model_family(MODEL_ID)

requested_device = os.environ.get("RIGHT_ANSWER_EMBEDDING_DEVICE", "").strip().lower()
if requested_device:
    DEVICE = requested_device
else:
    DEVICE = "cuda" if torch.cuda.is_available() else "cpu"

torch_dtype = torch.float16 if DEVICE.startswith("cuda") else torch.float32
if not DEVICE.startswith("cuda"):
    torch.set_num_threads(max(1, CPU_THREADS))
    try:
        torch.set_num_interop_threads(1)
    except RuntimeError:
        pass

tokenizer = AutoTokenizer.from_pretrained(MODEL_ID, padding_side="left", use_fast=False)
model = AutoModel.from_pretrained(MODEL_ID, dtype=torch_dtype, trust_remote_code=True)
model.to(DEVICE)
model.eval()


def format_query(text: str) -> str:
    if MODEL_FAMILY == "pplx":
        return text
    return f"Instruct: {QUERY_INSTRUCTION}\nQuery: {text}"


def coerce_text(value) -> str:
    if value is None:
        return ""
    if isinstance(value, str):
        return value
    if isinstance(value, bytes):
        return value.decode("utf-8", errors="ignore")
    if isinstance(value, (dict, list, tuple)):
        try:
            return json.dumps(value, ensure_ascii=False)
        except Exception:
            return str(value)
    return str(value)


def clean_text_for_tokenizer(text: str) -> str:
    cleaned = text.replace("\x00", " ").strip()
    try:
        cleaned = cleaned.encode("utf-8", errors="ignore").decode("utf-8", errors="ignore")
    except Exception:
        pass
    return cleaned


def tokenize_inputs(input_texts: list[str]):
    return tokenizer(
        input_texts,
        padding=True,
        truncation=True,
        max_length=MAX_LENGTH,
        return_tensors="pt",
    )


def run_model(input_texts: list[str]) -> list[list[float]]:
    batch = tokenize_inputs(input_texts)
    batch = {key: value.to(model.device) for key, value in batch.items()}

    with torch.inference_mode():
        outputs = model(**batch)
        if MODEL_FAMILY == "qwen":
            embeddings = last_token_pool(outputs.last_hidden_state, batch["attention_mask"])
        else:
            embeddings = mean_pool(outputs.last_hidden_state, batch["attention_mask"])
        embeddings = F.normalize(embeddings, p=2, dim=1)
        if 0 < OUTPUT_DIMENSIONS < embeddings.shape[1]:
            embeddings = embeddings[:, :OUTPUT_DIMENSIONS]
            embeddings = F.normalize(embeddings, p=2, dim=1)
        return embeddings.cpu().tolist()


def embed_texts(texts: list[str], mode: str) -> list[list[float]]:
    normalized_texts = [clean_text_for_tokenizer(coerce_text(text)) for text in texts]
    input_texts = [format_query(text) if mode == "query" else text for text in normalized_texts]

    try:
        return run_model(input_texts)
    except TypeError:
        results: list[list[float]] = []
        for text in input_texts:
            safe_text = text if text else "[empty]"
            try:
                single = run_model([safe_text])
            except Exception:
                single = run_model(["[unreadable]"])
            results.append(single[0])
        return results


print(
    json.dumps(
        {
            "type": "ready",
            "model": MODEL_ID,
            "device": DEVICE,
            "dimensions": OUTPUT_DIMENSIONS,
        }
    ),
    flush=True,
)

for raw_line in sys.stdin:
    line = raw_line.strip()
    if not line:
        continue

    request_id = None
    try:
        payload = json.loads(line)
        request_id = payload.get("id")
        texts = payload.get("texts") or []
        mode = payload.get("mode") or "document"

        result = embed_texts(texts, mode)
        print(json.dumps({"id": request_id, "ok": True, "embeddings": result}), flush=True)
    except Exception as exc:  # pragma: no cover - operational error path
        print(
            json.dumps(
                {
                    "id": request_id,
                    "ok": False,
                    "error": str(exc),
                    "traceback": traceback.format_exc(),
                }
            ),
            flush=True,
        )
