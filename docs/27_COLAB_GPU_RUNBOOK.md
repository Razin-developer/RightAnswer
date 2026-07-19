# Colab GPU Runbook

This runbook is for running the full SSLC textbook ingestion and embedding batch on **Google Colab GPU**, not on the local development machine.

## Goal

- Clone the repo from GitHub
- Install Node.js, pnpm, and Python dependencies
- Start the local embedded PostgreSQL instance inside Colab
- Run the CSV-driven textbook batch processor
- Zip the `storage/` folder
- Download the zip archive back to your machine

## Recommended Embedding Settings

- Model: `perplexity-ai/pplx-embed-v1-0.6b`
- Dimensions: `1024`
- Device: `cuda`

## One-Cell Colab Commands

```bash
%%bash
set -euo pipefail

cd /content
git clone https://github.com/Razin-developer/rightanswer-2.git
cd rightanswer-2

chmod +x scripts/colab/*.sh

export RIGHT_ANSWER_WORKDIR=/content/rightanswer-2
export RIGHT_ANSWER_EMBEDDING_MODEL=perplexity-ai/pplx-embed-v1-0.6b
export RIGHT_ANSWER_EMBEDDING_DIMENSIONS=1024
export RIGHT_ANSWER_EMBEDDING_DEVICE=cuda
export RIGHT_ANSWER_CHAPTER_WORKERS=8
export RIGHT_ANSWER_OCR_WORKERS=8
export RIGHT_ANSWER_BATCH_PARALLEL=1
export RIGHT_ANSWER_BATCH_ATTEMPTS=3

bash scripts/colab/bootstrap-right-answer.sh https://github.com/Razin-developer/rightanswer-2.git
```

After that, upload your `ingest.csv` into `/content/rightanswer-2/`.

Then run:

```bash
%%bash
set -euo pipefail

cd /content/rightanswer-2
export RIGHT_ANSWER_WORKDIR=/content/rightanswer-2
export RIGHT_ANSWER_EMBEDDING_MODEL=perplexity-ai/pplx-embed-v1-0.6b
export RIGHT_ANSWER_EMBEDDING_DIMENSIONS=1024
export RIGHT_ANSWER_EMBEDDING_DEVICE=cuda
export RIGHT_ANSWER_CHAPTER_WORKERS=8
export RIGHT_ANSWER_OCR_WORKERS=8
export RIGHT_ANSWER_BATCH_PARALLEL=1
export RIGHT_ANSWER_BATCH_ATTEMPTS=3

bash scripts/colab/run-right-answer-batch.sh ingest.csv colab-pplx06b-full-run
```

Zip the storage folder:

```bash
%%bash
set -euo pipefail

cd /content/rightanswer-2
export RIGHT_ANSWER_WORKDIR=/content/rightanswer-2
bash scripts/colab/zip-storage.sh right-answer-storage.zip
```

Download the zip in a Python cell:

```python
from google.colab import files
files.download('/content/rightanswer-2/right-answer-storage.zip')
```

## All-in-One Alternative

If `ingest.csv` is already in the repo root on Colab:

```bash
%%bash
set -euo pipefail

cd /content/rightanswer-2
chmod +x scripts/colab/*.sh

export RIGHT_ANSWER_WORKDIR=/content/rightanswer-2
export RIGHT_ANSWER_EMBEDDING_MODEL=perplexity-ai/pplx-embed-v1-0.6b
export RIGHT_ANSWER_EMBEDDING_DIMENSIONS=1024
export RIGHT_ANSWER_EMBEDDING_DEVICE=cuda
export RIGHT_ANSWER_CHAPTER_WORKERS=8
export RIGHT_ANSWER_OCR_WORKERS=8

bash scripts/colab/all-in-one.sh \
  https://github.com/Razin-developer/rightanswer-2.git \
  ingest.csv \
  colab-pplx06b-full-run \
  right-answer-storage.zip
```

## Observability During Colab Run

Useful commands:

```bash
tail -f /content/rightanswer-2/storage/logs/local-postgres.log
tail -f /content/rightanswer-2/storage/logs/ingestion/batch-*.log
cd /content/rightanswer-2 && pnpm ops:db:check
```

## Expected Output

At the end you should have:

- `/content/rightanswer-2/storage/textbooks/raw/...`
- `/content/rightanswer-2/storage/textbooks/processed/...`
- `/content/rightanswer-2/storage/logs/ingestion/...`
- `/content/rightanswer-2/right-answer-storage.zip`
