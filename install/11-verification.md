# 11 — Verification

End-to-end checks to confirm the stack is healthy.

---

## Quick smoke test

```bash
cd /opt/gateforge-ai-ao
./tools/smoke-test.sh
```

The smoke test runs ~10 checks and reports pass/fail for each. If everything passes, the stack is functional.

What it verifies:

1. NATS reachable + streams created + KV buckets created
2. MinIO reachable + buckets exist + lifecycle rules applied
3. Postgres reachable + schemas migrated
4. OTel pipeline ingesting (sends a test trace)
5. Grafana datasources healthy
6. Orchestrator `/v1/health` returns ok
7. At least one adapter heartbeating in the registry
8. Synthetic task round-trips: assigned → accepted → completed
9. Cost event landed in Postgres
10. Trace visible in Tempo for the synthetic task

---

## Full chaos test

```bash
./tools/chaos-test.sh
```

Sequence (with cleanup after each):

| Scenario | Expected behavior |
|----------|-------------------|
| Kill an adapter mid-task | Task redelivered via JetStream; same adapter restarts and resumes idempotently |
| Kill orchestrator | Bus continues operating; orchestrator restarts and reconciles state from NATS KV + Git |
| Disconnect NATS for 30s | All services reconnect on backoff; no events lost (JetStream durable) |
| Saturate one adapter | Backpressure kicks in; new tasks routed elsewhere or queued |
| Inject malformed envelope | Schema validation rejects, error logged, no crash |
| Trip cost circuit breaker | New tasks rejected with `policy.budget_exceeded`; in-flight complete normally |
| Force a verification failure | Original task transitions to `failed` per `verification.policy` |

Each scenario has a corresponding entry in `runbooks/` if it does not pass.

---

## Performance baseline

```bash
./tools/load-test.sh --concurrency 50 --duration 5m
```

On a 4 vCPU / 8 GB VM, baseline targets:

| Metric | Target |
|--------|--------|
| Throughput | ≥ 100 tasks/min sustained |
| p50 task ack latency | ≤ 50 ms |
| p95 task ack latency | ≤ 200 ms |
| End-to-end p95 (echo adapter) | ≤ 500 ms |
| Memory steady state | ≤ 4 GB |
| CPU steady state | ≤ 60% |

Run before declaring a stack production-ready and after any infrastructure change.

---

## Manual end-to-end check

For a tactile verification:

1. Open a project repo on GitHub that has the AI-AO App installed
2. File an issue with title "test research task" and label `capability:echo`
3. Within ~5 seconds you should see:
   - A new file at `tasks/open/<task_id>.md` (committed by the orchestrator)
   - The issue gains a comment like "Task assigned to adapter-echo, ETA 1s"
4. Within ~5 more seconds:
   - File moves to `tasks/done/<task_id>.md`
   - Issue gets a final comment with artifact link (echo writes a one-line markdown to MinIO)
   - Issue is closed
5. In Grafana → Explore → Tempo, search for the task_id; the full trace appears

If all of that happens, **the stack is ready**.

---

## Troubleshooting matrix

| Failed check | First place to look |
|--------------|---------------------|
| NATS not reachable | `docker compose logs nats` |
| MinIO bucket missing | `docker compose run --rm init-minio` |
| Postgres schema missing | `docker compose run --rm init-postgres` |
| Orchestrator unhealthy | `docker compose logs orchestrator` |
| Adapter not heartbeating | `docker compose logs adapter-<name>` |
| Trace missing in Tempo | `docker compose logs otel-collector` |
| Webhook deliveries failing | GitHub App → Advanced → Recent Deliveries |
| Issue not picked up | Webhook URL wrong, or label not in capability set |

Detailed troubleshooting in [`runbooks/troubleshooting.md`](runbooks/troubleshooting.md).
