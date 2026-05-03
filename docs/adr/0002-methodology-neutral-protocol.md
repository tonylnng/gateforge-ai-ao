# ADR-0002: AI-AO is methodology-neutral

- **Status:** Accepted
- **Date:** 2026-05-03
- **Deciders:** Tony Lnng

## Context

Multi-agent orchestration could embed methodology assumptions (phases, roles, blueprints, quality gates) directly in the protocol. The author runs the GateForge Guideline as the primary methodology, so it would be tempting to bake its concepts into AI-AO.

## Decision

AI-AO is **methodology-neutral**. The protocol contains no concept of phases, roles, blueprints, or quality gates. Instead, it provides primitives:

- **Capabilities** — generic verbs like `research`, `system-design`, `code-review`
- **Verification** — a generic post-task check, configurable per task
- **Autonomy levels** — `autonomous`, `supervised`, `approval-required`
- **Metadata extension namespace** — methodologies stash their own fields here; AI-AO ignores them

Methodologies (including the GateForge Guideline) layer above AI-AO. They map their concepts onto AI-AO capabilities and use the metadata namespace for their own state.

## Consequences

**Easier:**
- AI-AO can be adopted by teams without subscribing to GateForge methodology
- AI-AO can be productized as a vendor-neutral, methodology-neutral standard
- Methodologies can iterate without protocol pressure
- Multiple methodologies can coexist on one AI-AO deployment

**Harder:**
- Methodology authors must build their own mapping layer
- Slight cognitive overhead distinguishing "AI-AO concept" from "GateForge concept"

## Alternatives considered

- **Bake GateForge phases into the protocol:** rejected. Couples AI-AO's success to GateForge's, blocks third-party methodologies, makes AI-AO a sub-component of GateForge rather than a standalone framework.
- **Provide methodology hooks but no extension namespace:** rejected. Half-measure; methodologies will need methodology-specific state and forcing them to invent it elsewhere creates a leaky abstraction.

## References

- [`docs/CONCEPTS.md`](../CONCEPTS.md)
- [GateForge Guideline](https://github.com/tonylnng/gateforge-openclaw-guideline)
