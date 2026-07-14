# Scaling and Failure Analysis

## Objective

Ensure Right Answer can serve normal study usage and exam-night spikes without runaway cost or systemic collapse.

## Scale Scenarios

### 10K Concurrent Users

- Redis and CDN handle most cached reads
- One PostgreSQL primary with one read replica is sufficient
- Small worker pool handles ingestion and pre-generation
- Cheap model usage must still be capped by plan

### 100K Concurrent Users

- Redis cluster required
- API horizontally scaled across regions if needed
- Queue depth monitoring becomes critical
- Hot cache and pre-generated answers carry peak load

### 1M Concurrent Users

- Exam mode or cached-only submodes become mandatory
- Strong CDN edge caching for static revision assets
- Strict request coalescing and queue prioritization
- Live generation reserved mostly for premium cohorts

### 10M Registered Users

- Usage events, model calls, and retrieval logs must be partitioned
- Data warehouse pipeline may be added later
- Subscription and authentication services should be isolated clearly

## Failure Modes and Mitigations

### Provider 429 Errors

- Exponential backoff
- Shift traffic to alternate cheap provider
- Reduce free-user live generation immediately

### Database Overload

- Read replicas for read-heavy content queries
- aggressive Redis caching
- precomputed chapter payloads

### Vector Search Overload

- Retrieval cache reuse
- hybrid search fallback with stronger metadata filtering
- separate vector-worker service later if needed

### Cache Stampede

- request coalescing
- stale-safe serving
- hot cache warming

### Queue Overload

- priority queues by plan
- rate-reduce non-urgent teacher exports
- defer heavy pregeneration during live traffic peaks

### AI Cost Spike

- daily and monthly provider budget caps
- exam mode
- cached-only mode
- disable premium routes for non-critical traffic

### Payment Abuse

- webhook verification
- fraud review flags
- subscription grace state before activation

### Bot Abuse

- IP throttles
- device fingerprinting
- login hardening
- anonymous ask restrictions

## Infrastructure Controls

- CDN for static assets and public pages
- Redis for caching, hot keys, limits, and queues
- BullMQ or equivalent queue system
- worker autoscaling by queue depth
- model gateway with circuit breaker
- budget caps at route and provider level
- read replicas for PostgreSQL
- local-first storage abstraction for textbook artifacts

## Cached-Only Mode

This emergency mode should:

- serve exact, semantic, verified, and pre-generated caches only
- reject new live free-user generation
- allow queued premium generation only if budget and provider health allow

## Acceptance Criteria

- System can degrade gracefully instead of failing fully
- Operator can activate exam mode or cached-only mode quickly
- Scale plan preserves economics, not just uptime
