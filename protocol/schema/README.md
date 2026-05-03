# Protocol Schemas

JSON Schema (Draft 2020-12) source files for the AI-AO wire protocol.

| File | Defines |
|------|---------|
| [`task-envelope.v1.json`](task-envelope.v1.json) | Task envelope |
| [`event.v1.json`](event.v1.json) | Lifecycle event |
| [`agent-card.v1.json`](agent-card.v1.json) | Agent self-description |
| [`error.v1.json`](error.v1.json) | Structured error |

## Validation

```bash
# Install ajv-cli
npm install -g ajv-cli ajv-formats

# Validate an envelope against the schema
ajv validate -c ajv-formats \
  -s task-envelope.v1.json \
  -d examples/canonical-task.json
```

## Code generation

Generated TypeScript and Go types live in `sdk/typescript/` and `sdk/go/` and are regenerated from these schemas via the build pipeline. Do not edit generated files directly.

## Versioning

Each schema is independently versioned. Filename pattern: `<name>.v<MAJOR>.json`. New MAJOR ⇒ new file, old file retained for back-compat.
