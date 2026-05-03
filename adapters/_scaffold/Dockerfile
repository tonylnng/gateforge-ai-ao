# Generic adapter Dockerfile — replace base + build steps for your language.
FROM golang:1.23-alpine AS build
WORKDIR /src
COPY . .
RUN go mod download && CGO_ENABLED=0 go build -o /out/adapter ./src

FROM gcr.io/distroless/static-debian12:nonroot
COPY --from=build /out/adapter /adapter
COPY agent-card.yaml /etc/aiao/agent-card.yaml
EXPOSE 8201
USER nonroot:nonroot
HEALTHCHECK --interval=15s --timeout=3s --retries=3 \
  CMD ["/adapter", "healthcheck"]
ENTRYPOINT ["/adapter"]
