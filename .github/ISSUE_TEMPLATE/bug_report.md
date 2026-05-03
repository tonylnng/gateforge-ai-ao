---
name: Bug report
about: Something is broken in the orchestrator, an adapter, or the protocol
title: "[bug] "
labels: bug
---

### What happened
<!-- One-paragraph description -->

### Expected
<!-- What should have happened -->

### Reproduction
<!-- Minimal steps. Include task ID if applicable. -->

```
docker compose ps
docker compose logs --tail=100 orchestrator
```

### Environment
- Repo SHA:
- Protocol version (from `/protocol/version.txt`):
- Affected component: [ ] orchestrator [ ] adapter:_____ [ ] protocol [ ] infra
- Deployment env: [ ] dev [ ] staging [ ] prod

### Logs / traces
<!-- Paste relevant logs or link a Grafana trace -->
