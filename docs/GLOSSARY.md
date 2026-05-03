# Glossary

Every term used in GateForge AI-AO, defined once, in one place.

---

**Adapter**
A small service that translates between the AI-AO protocol and a specific agent platform's native interface. Three classes: native (speaks the AI-AO SDK directly), API-based (calls a platform HTTP API), browser-based (drives a browser via Playwright). Adapters are stateless.

**Agent**
A unit of AI capability that can accept tasks. May be a SaaS product (Perplexity Computer, Manus), a self-hosted model (an OpenClaw VM), or a specialized service (a verifier). Identified by an `agent_id`.

**Agent card**
A self-describing manifest published by every agent declaring its capabilities, cost profile, reliability metrics, endpoint, constraints, and the protocol version it speaks. Lives in NATS KV (live) and `AGENTS.md` (declarative).

**AI-AO**
GateForge AI-AO. The orchestration framework this repo defines. Vendor-neutral, methodology-neutral.

**Artifact**
Any file produced by an agent. Stored in MinIO. Referenced from Git by URI + SHA256.

**Audit firehose**
A NATS subject (`audit.<project>`) that receives a copy of every significant event for long-term retention. Mirrored to Postgres and optionally to Git.

**Autonomy level**
A constraint on a task: `autonomous` (agent acts freely), `supervised` (agent acts but events are watched), `approval-required` (human must approve before execution).

**Capability**
A generic verb describing what an agent can do. Methodology-neutral. Examples: `research`, `system-design`, `code-review`, `fact-check`. Routing happens by capability, not by vendor.

**Circuit breaker**
A policy mechanism that stops routing to an agent or platform after N consecutive failures within a window. Prevents cascading failures.

**Class A / B / C**
Document classification used by the GateForge Guideline (not by AI-AO directly). A = runtime contract, B = methodology, C = project-specific. AI-AO is methodology-neutral and does not enforce this classification.

**Conformance suite**
A test suite under `tools/conformance-test/` that validates an adapter against the protocol. Every adapter must pass.

**Context refs**
Git URIs included in a task envelope, pointing to documents the receiving agent must read before starting work. The mechanism that makes agents stateless.

**Correlation ID**
An identifier used in NATS request-reply patterns to match a reply to its original request. Often the `task_id`.

**Dead letter queue (DLQ)**
A NATS subject (`*.dlq`) that receives messages that exceeded their max-deliver count. Triaged manually via `tools/replay-cli`.

**Deliverable type**
A field in the task envelope that declares what the output should look like. Examples: `markdown_report`, `code_patch`, `structured_doc`, `binary_artifact`.

**Distributed trace**
An OpenTelemetry trace spanning multiple services, joined by `trace_id`. Used to reconstruct multi-hop, multi-vendor task execution.

**Event**
A lifecycle update on a task. Types: `assigned`, `accepted`, `rejected`, `progress`, `completed`, `failed`, `cancelled`, `input_required`. All durable in NATS streams.

**GateForge Guideline**
The reference SDLC methodology that runs on AI-AO. Lives in [gateforge-openclaw-guideline](https://github.com/tonylnng/gateforge-openclaw-guideline). Optional from AI-AO's perspective.

**GateForge Admin Portal**
The operational dashboard. Lives in [gateforge-admin-portal-site](https://github.com/tonylnng/gateforge-admin-portal-site). Subscribes to NATS and reads Git to display live state.

**GitHub App**
The identity AI-AO uses to read and write project repos. Has fine-grained permissions per repo. Required for orchestrator to commit task state and react to webhooks.

**Heartbeat**
A periodic message (every 10s) from each agent on `agent.<id>.heartbeat`, declaring liveness, current load, and queue depth. Used for routing decisions and stale-agent detection.

**Idempotency**
The property that re-running an operation has the same effect as running it once. Required for adapters because brokers offer at-least-once delivery.

**JetStream**
NATS's persistence layer. Provides durable streams, consumer groups, KV store, and replay. Used as the message broker for AI-AO.

**JSON Schema**
The format used to define wire-level types in `protocol/schema/`. Each schema is versioned independently.

**JWT (JSON Web Token)**
The mechanism used to authenticate agents to NATS. Each agent has a per-agent JWT scoped to its allowed subjects.

**KV (key-value store)**
NATS JetStream's KV API. Used by AI-AO to hold the live agent registry — agents publish their cards here on startup.

**MinIO**
An S3-compatible object store. Self-hosted via Docker. Stores all artifacts produced by agents.

**Methodology**
A higher-level framework that defines how to do something (e.g. how to build software). Sits above AI-AO. AI-AO is methodology-neutral.

**Methodology layer**
The optional layer that maps methodology concepts onto AI-AO primitives. The GateForge Guideline ships its own methodology layer that translates phases and roles into AI-AO capabilities.

**mTLS (mutual TLS)**
Both client and server present certificates. Used between AI-AO internal services for trust.

**NATS**
A message broker. Single binary, sub-millisecond latency. The "nervous system" of AI-AO.

**OpenClaw**
A multi-agent runtime framework. The "native" agent platform AI-AO supports out of the box (you bring your own OpenClaw VMs).

**OpenTelemetry (OTel)**
A standard for distributed tracing, metrics, and logs. Used throughout AI-AO for observability.

**Orchestrator**
The "prime AI" router service. Receives webhooks, picks agents, publishes tasks, watches for completion. Stateless. Pluggable — today's orchestrator can be replaced tomorrow with no other component changes.

**Policy engine**
A component of the orchestrator that enforces budget caps, autonomy levels, data classification, and circuit breakers.

**Postgres**
A relational database. Used for cost aggregation, long-term audit, and operational reporting. Not used as the system of record (Git is).

**Project repo**
A GitHub repository representing one project. Contains tasks, decisions, AGENTS.md, artifact references, and audit. Per-project boundary.

**Protocol version**
The semver of the AI-AO wire protocol the agent or adapter speaks. Declared in agent cards. Negotiated by the orchestrator.

**Reconciliation loop**
A 60-second loop in the orchestrator that compares Git state to NATS KV state and synthesizes missing events for resilience against missed webhooks.

**Replay**
The ability to re-process events from a NATS stream from any historical point. Used for debugging, audit reconstruction, and DLQ triage.

**SDK**
A library that lets a native agent speak NATS using AI-AO's conventions without writing low-level NATS code. Available in Go and TypeScript.

**Subject**
A NATS topic. AI-AO uses a hierarchical naming scheme: `project.<repo>.task.<id>.<event-type>`, `agent.<id>.heartbeat`, etc. See [`protocol/SUBJECTS.md`](../protocol/SUBJECTS.md).

**Substrate**
A foundational layer. AI-AO has three: Git (memory), NATS (nervous system), MinIO (artifacts).

**Task envelope**
The unit of delegated work. A JSON document defined by `protocol/schema/task-envelope.v1.json`. Contains goal, success criteria, deliverable type, constraints, callbacks, and metadata.

**Task ID**
A UUIDv7 that uniquely identifies a task. Used as idempotency key.

**Trace ID**
An OpenTelemetry trace identifier propagated across all hops of a multi-agent task. The query key for "what happened during this task."

**Verifier / Verification**
A second-pass check on a task's output. Configurable per task type. The verifier is just another agent with a `verifier`-class capability.

**Webhook**
An HTTP callback. AI-AO uses them at the edges (GitHub → orchestrator) but not for internal agent-to-agent communication (that's NATS).
