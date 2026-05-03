# Roadmap

Phase-based build plan. Each phase is bounded by a deliverable, not by time. With AI-assisted build, each phase can complete in hours.

---

## Phase 0 — Repo scaffold ✅

- [x] Repo created
- [x] README, CONTRIBUTING, LICENSE, VERSION, CHANGELOG
- [x] Directory layout
- [x] Architecture and concept docs
- [x] Glossary
- [x] Initial ADRs

**Deliverable:** A repo a human or AI can read end-to-end and understand what's being built and why.

---

## Phase 1 — Protocol foundation

- [ ] Task envelope JSON Schema, finalized
- [ ] Event JSON Schema, finalized
- [ ] Agent card JSON Schema, finalized
- [ ] Error taxonomy
- [ ] NATS subject reference (`SUBJECTS.md`)
- [ ] Webhook contract (`WEBHOOK-SPEC.md`)
- [ ] Protocol spec doc, complete with examples

**Deliverable:** `protocol/` directory ready to be tagged v1.0.0. All implementations downstream depend on this.

**Definition of done:** A new contributor can read `protocol/PROTOCOL-SPEC.md` and write a conforming adapter without asking questions.

---

## Phase 2 — Substrate

- [ ] `infrastructure/docker-compose.yml` boots NATS + MinIO + Postgres + OTel + Tempo + Loki + Grafana
- [ ] NATS streams pre-created via init container
- [ ] MinIO buckets pre-created with lifecycle policies
- [ ] Postgres schemas migrated by an init container
- [ ] Grafana dashboards pre-loaded
- [ ] Smoke-test script in `install/11-verification.md`

**Deliverable:** `docker-compose up` on a fresh VM yields a functioning AI-AO substrate.

**Definition of done:** All install guides under `install/` execute end-to-end on a fresh Ubuntu 22.04 VM with Docker.

---

## Phase 3 — Orchestrator core

- [ ] Stateless Go service receiving GitHub webhooks
- [ ] Agent registry implementation in NATS KV
- [ ] Capability-based routing
- [ ] Idempotency (seen-set in NATS KV)
- [ ] Reconciliation loop for missed webhooks
- [ ] Git mirroring of significant events

**Deliverable:** Tasks can flow end-to-end through a stub adapter that echoes input as output.

---

## Phase 4 — First native adapter (OpenClaw)

- [ ] Go SDK in `sdk/go/` for speaking AI-AO from native code
- [ ] OpenClaw adapter under `adapters/openclaw/`
- [ ] End-to-end test: human files issue, OpenClaw VM does work, result lands in Git

**Deliverable:** A real OpenClaw VM completes a real task end-to-end.

---

## Phase 5 — First closed-platform adapter (Perplexity Computer)

- [ ] API-based adapter under `adapters/perplexity-computer/`
- [ ] Rate limiting and per-platform concurrency caps
- [ ] Output normalization to schema
- [ ] Cost tracking emitted with every event

**Deliverable:** Perplexity Computer is reachable as a peer through AI-AO.

---

## Phase 6 — Policy & verifier

- [ ] Policy engine: budget caps, autonomy levels, data classification, circuit breakers
- [ ] Verifier engine: configurable per-task verification policies
- [ ] First reference verifier agent (cheap LLM-based fact-checker)
- [ ] Dead-letter handling and `tools/replay-cli`

**Deliverable:** A misbehaving agent or budget overrun cannot take down the system.

---

## Phase 7 — Second closed-platform adapter (Manus)

- [ ] Browser-based adapter under `adapters/manus/`
- [ ] Establishes the browser-automation pattern for any UI-only platform
- [ ] Session management and re-authentication on expiry

**Deliverable:** Three platforms (OpenClaw, Perplexity Computer, Manus) coordinate on a single multi-step task.

---

## Phase 8 — Observability hardening

- [ ] OTel context propagation through every NATS message and Git commit
- [ ] Cost dashboards (per-task, per-agent, per-project, per-day)
- [ ] SLA dashboards (latency, success rate, queue depth)
- [ ] Alerting rules

**Deliverable:** Pick any `task_id`, reconstruct the entire run in one trace view.

---

## Phase 9 — Security hardening

- [ ] mTLS between all internal services
- [ ] NATS auth via per-agent JWTs
- [ ] GitHub App with fine-grained per-repo permissions
- [ ] Signed commits required on all repos
- [ ] Signed bus messages
- [ ] Secret rotation playbook in `install/runbooks/`

**Deliverable:** Security review-ready.

---

## Phase 10 — Chaos & load testing

- [ ] Adapter kill scenarios pass recovery
- [ ] NATS reconnect pass
- [ ] Backpressure verified under saturation
- [ ] DLQ replay tested
- [ ] Audit reconstruction tested

**Deliverable:** Documented resilience against the failure modes catalogued in `docs/ARCHITECTURE.md#failure-model`.

---

## Phase 11 — Adapter SDK + conformance suite

- [ ] `adapters/_scaffold/` template generator
- [ ] `tools/conformance-test/` validates any adapter against the protocol
- [ ] Documentation: "write a new adapter in 1 hour"

**Deliverable:** Adding a new platform is a clearly-bounded few-hour exercise, not a research project.

---

## Phase 12 — Admin Portal integration

- [ ] Portal subscribes to NATS for live events
- [ ] Portal reads Git for durable state
- [ ] Portal calls orchestrator HTTP API for control actions
- [ ] All AI-AO event types visualized

**Deliverable:** Operators have a single pane of glass for all AI-AO activity. See [`ADMIN-PORTAL-UPGRADE.md`](ADMIN-PORTAL-UPGRADE.md).

---

## Beyond v1.0

- Multi-tenancy (per-tenant subject prefixes, JWT scopes, billing aggregation)
- Federated AI-AO clusters (multi-region NATS leaf nodes)
- Open standard: publish protocol spec for third-party agent vendors to implement directly
