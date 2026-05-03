# `/tools` — Operator scripts

Helper scripts for verifying, exercising, and stress-testing an AI-AO deployment.

| Script              | Purpose                                                |
| ------------------- | ------------------------------------------------------ |
| `smoke-test.sh`     | End-to-end happy-path probe (publish → ack → complete) |
| `chaos-test.sh`     | Kill containers mid-task; assert no work is lost       |
| `load-test.sh`      | Sustained throughput probe with configurable RPS       |
| `provision-jetstream.sh` | Apply `infrastructure/nats/jetstream-streams.yaml` |

All scripts assume:

- The compose stack is up (`docker compose ps` shows healthy).
- `nats` and `mc` CLIs are on `$PATH` **or** you run via the helper containers (each script auto-falls-back).

Run from repo root:

```bash
./tools/smoke-test.sh
```
