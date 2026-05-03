# ADR-0001: Three substrates — Git, NATS, MinIO

- **Status:** Accepted
- **Date:** 2026-05-03
- **Deciders:** Tony Lnng

## Context

Multi-agent orchestration needs durable state, real-time coordination, and large-artifact storage. Each has different latency, durability, and access-pattern requirements. A single substrate cannot serve all three well.

## Decision

Adopt three substrates, each for what it is best at:

- **GitHub** as the durable system of record (tasks, decisions, artifact references, audit). Versioned, signable, ACL-aware, human-AI shared.
- **NATS JetStream** as the real-time message bus (task assignment, lifecycle events, heartbeats, KV registry). Sub-millisecond latency, durable streams, consumer groups, KV.
- **MinIO** as the artifact store (large outputs). Bytes here, references in Git.

Postgres is added as a fourth, narrower substrate for cost aggregation and long-term audit reporting (not as system of record).

## Consequences

**Easier:**
- Each substrate optimized for its access pattern
- Audit and replay work naturally
- Humans and AI share the same view of project state via GitHub
- Adding new agents or platforms doesn't require schema changes to a central database

**Harder:**
- Operating three services instead of one
- Keeping NATS and Git in sync requires explicit reconciliation
- Multi-substrate observability requires unified tracing (OTel handles this)

## Alternatives considered

- **Single relational database (Postgres only):** rejected. Loses Git's audit, signing, ACL, and human-readable surface. Reinvents issue tracking.
- **Single graph database / event store:** rejected. Same problem — no human surface, custom tooling burden.
- **Just GitHub:** rejected. Latency too high for task ack and live progress; no consumer groups; rate limits.
- **Just NATS:** rejected. No human-readable audit; no version history.
- **Kafka instead of NATS:** rejected. Operational overhead, awkward request-reply, partition model fights dynamic subjects. NATS JetStream covers Kafka's relevant features at one-fifth the operational complexity.

## References

- [`docs/ARCHITECTURE.md`](../ARCHITECTURE.md)
- [NATS JetStream documentation](https://docs.nats.io/nats-concepts/jetstream)
