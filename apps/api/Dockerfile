FROM rust:1.82-bookworm AS build
WORKDIR /app
COPY apps/api/Cargo.toml apps/api/Cargo.toml
COPY apps/api/src apps/api/src
COPY apps/api/migrations apps/api/migrations
WORKDIR /app/apps/api
RUN cargo build --release

FROM debian:bookworm-slim
RUN apt-get update && apt-get install -y --no-install-recommends ca-certificates && rm -rf /var/lib/apt/lists/*
WORKDIR /app
COPY --from=build /app/apps/api/target/release/right-answer-api /usr/local/bin/right-answer-api
ENV PORT=4000
EXPOSE 4000
CMD ["right-answer-api"]
