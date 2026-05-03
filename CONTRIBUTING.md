# Contributing to GateForge AI-AO

Thank you for considering a contribution. This document explains how the project is structured, how changes are reviewed, and what rules govern the most sensitive parts of the codebase.

---

## Project structure recap

```
protocol/         ← the wire-level contract; changes are tightly governed
install/          ← AI-operable setup guides; must stay accurate and self-contained
infrastructure/   ← docker configs; must match install guides exactly
orchestrator/     ← prime-AI router service
sdk/              ← libraries for native agents
adapters/         ← one folder per external platform
tools/            ← operator CLIs
docs/             ← architecture, concepts, ADRs, glossary
.github/          ← CI workflows and issue templates
```

---

## Branching model

- `main` — always green, always deployable
- `feat/<slug>` — feature branches
- `fix/<slug>` — bugfix branches
- `protocol/<slug>` — changes that touch `protocol/` (extra review required)

Trunk-based, short-lived branches, squash-and-merge.

---

## Schema and protocol changes

Anything under `protocol/` is **the wire contract**. Treat it like an API.

### Rules

1. **Additive within a major version.** New optional fields, new event types, new error codes — fine. Renames, removals, type changes, required-field additions — require a major version bump.
2. **Bump `protocol/version.txt` on every PR that touches schemas.** Use SemVer: PATCH for clarifications, MINOR for additive changes, MAJOR for breaking changes.
3. **Update all four artifacts together** when changing a schema:
   - JSON Schema file in `protocol/schema/`
   - Generated TypeScript / Go types in `sdk/`
   - Examples in `protocol/PROTOCOL-SPEC.md`
   - CHANGELOG entry under "Protocol"
4. **Backward-compatible deserialization.** Adapters and orchestrator must accept envelopes with unknown fields and ignore them gracefully.
5. **Conformance tests must pass.** `tools/conformance-test/` validates that every adapter accepts canonical envelopes and emits canonical events. Breaking conformance blocks merge.

### Major version transitions

When MAJOR is bumped:
- Both versions ship side-by-side for at least one MINOR cycle of the new major
- Adapters declare which protocol versions they speak in their agent card
- Orchestrator handles version negotiation

---

## Install guide rules

`install/` is read by AI agents to bootstrap stacks. Drift between docs and reality silently breaks deployments. Therefore:

1. Every command in `install/` must be **copy-pasteable** and runnable on a fresh Ubuntu 22.04+ VM with Docker installed
2. Every config file referenced in `install/` must exist at the exact path stated
3. CI runs the install guides end-to-end on every PR that touches `install/` or `infrastructure/`
4. Use **explicit version pins** for all images (`nats:2.10.20`, never `nats:latest`)

---

## Commit messages

Conventional Commits format:

```
<type>(<scope>): <subject>

<body>

<footer>
```

Types: `feat`, `fix`, `docs`, `chore`, `refactor`, `test`, `proto`, `infra`.
Scopes: `protocol`, `orchestrator`, `sdk`, `adapter:<name>`, `install`, `infra`, `docs`.

Example: `proto(protocol): add verification.policy field to task envelope (v1.1)`

---

## Pull request checklist

- [ ] Branch from `main`, rebase before opening PR
- [ ] All CI checks pass (lint, test, conformance, install-smoke)
- [ ] CHANGELOG updated
- [ ] If schema changed: `protocol/version.txt` bumped, types regenerated, examples updated
- [ ] If install guide changed: end-to-end smoke run on a fresh VM
- [ ] Diagrams updated in `docs/diagrams/` if architecture changed
- [ ] One reviewer for normal changes; **two reviewers for protocol/ changes**

---

## ADRs

Architectural decisions go in `docs/adr/` as numbered, never-deleted Markdown files. Use the template in `docs/adr/0000-template.md`. New ADRs are required for:

- Protocol changes that introduce new concepts (not just fields)
- Substrate changes (swapping NATS, MinIO, Postgres for something else)
- New adapter classes (e.g. introducing email-based adapters)
- Security model changes

---

## License

By contributing, you agree your contributions are licensed under the project license (see [LICENSE](./LICENSE)).
