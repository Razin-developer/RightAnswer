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

```bash
cargo run --manifest-path apps/api/Cargo.toml --bin migrate_qdrant
```

The migration stops on empty PostgreSQL embeddings, empty vectors, failed
Qdrant writes, or count mismatches.
