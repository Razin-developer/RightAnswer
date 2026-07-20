FROM rust:1.90-bookworm AS build
WORKDIR /app
COPY apps/api/Cargo.toml apps/api/Cargo.toml
COPY apps/api/Cargo.lock apps/api/Cargo.lock
COPY apps/api/src apps/api/src
COPY apps/api/migrations apps/api/migrations
WORKDIR /app/apps/api
RUN cargo build --release --bins

FROM debian:bookworm-slim
RUN apt-get update && apt-get install -y --no-install-recommends ca-certificates curl && rm -rf /var/lib/apt/lists/*
WORKDIR /app
COPY --from=build /app/apps/api/target/release/right-answer-api /usr/local/bin/right-answer-api
COPY --from=build /app/apps/api/target/release/migrate_qdrant /usr/local/bin/migrate_qdrant
COPY --from=build /app/apps/api/target/release/test_ai_providers /usr/local/bin/test_ai_providers
ENV PORT=4000
EXPOSE 4000
CMD ["right-answer-api"]
