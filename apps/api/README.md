# RightAnswer Rust API

Compiled backend for RightAnswer.

## Stack

- Axum
- Tokio
- SQLx/PostgreSQL
- Qdrant
- Reqwest/OpenRouter
- Tower HTTP
- Tracing

## Run

```bash
cargo run --manifest-path apps/api/Cargo.toml
```

## Check

```bash
cargo check --manifest-path apps/api/Cargo.toml
```

## Migrate PostgreSQL Embeddings To Qdrant

Start Qdrant first:

```bash
node scripts/start-local-qdrant.mjs
```

```bash
cargo run --manifest-path apps/api/Cargo.toml --bin migrate_qdrant
```

The migration stops on empty PostgreSQL embeddings, empty vectors, failed
Qdrant writes, or count mismatches.

The migrator copies only vectors and retrieval payloads into Qdrant. PostgreSQL
remains the source of truth for users, chats, textbook metadata, cache entries,
usage events, and every other relational table. It prefers the pgvector
`Embedding.embedding_vector` column when present and uses
`Embedding.embedding_values` only as a compatibility fallback.
