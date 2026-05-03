# ADR-0003: Event-driven communication, no polling

- **Status:** Accepted
- **Date:** 2026-05-03
- **Deciders:** Tony Lnng

## Context

Agents need to know when tasks are accepted, when they're done, and when they fail. Two options: agents publish events on state change, or orchestrator polls.

## Decision

All inter-agent and orchestrator-to-agent communication is event-driven via NATS JetStream. Polling is forbidden in normal operation. The only periodic loop is a 60-second reconciliation that exists solely as a safety net for missed GitHub webhooks.

Acknowledgements are immediate: an adapter publishes `task.accepted` within a second of receiving `task.assigned`. The orchestrator never asks "did you get my task?".

## Consequences

**Easier:**
- Sub-second responsiveness without burning credits or rate limits
- Scales linearly with task volume
- Live progress visible to humans through the Admin Portal

**Harder:**
- Must handle reconnection and message redelivery in every consumer
- Requires durable streams (covered by JetStream)
- Reconciliation loop must exist as belt-and-suspenders

## Alternatives considered

- **HTTP polling:** rejected. Wastes resources, adds latency, doesn't scale.
- **Long polling:** rejected. Awkward to operate, no replay semantics.
- **Webhooks between agents:** rejected. Closed platforms cannot host webhook servers; design must work for them too.

## References

- [`docs/ARCHITECTURE.md#failure-model`](../ARCHITECTURE.md#failure-model)
