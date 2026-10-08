# Telemetry architecture

This diagram shows the telemetry paths in the local `kind` cluster. Argo CD
deploys the demo and observability components from the manifests under
`environments/`; this focuses on runtime telemetry flow.

```mermaid
flowchart LR
  subgraph demo["OpenTelemetry Demo · otel-demo namespace"]
    services["Instrumented demo services"]
    dependencies["Demo dependencies<br/>PostgreSQL · Kafka"]
    ad["Ad service"]
    firepit["FirePit"]
  end

  subgraph cluster["Local kind cluster"]
    subgraph observability["Observability · observability namespace"]
      operator["OpenTelemetry Operator<br/>Instrumentation resource"]

      subgraph collector["OpenTelemetry Collector · DaemonSet"]
        otlp["OTLP receiver<br/>gRPC :4317 · HTTP :4318"]
        legacy["Jaeger · Zipkin<br/>trace receivers"]
        native["Metrics receivers<br/>host · Kubernetes · kubelet<br/>Prometheus scrape · Kafka · PostgreSQL"]
        enrich["Kubernetes attributes<br/>resource detection · memory limit"]
        traces["Traces pipeline<br/>normalize · redact"]
        logs["Logs pipeline<br/>sanitize"]
        metrics["Metrics pipeline"]
        profiles["Profiles pipeline<br/>filter"]
        spanmetrics["Span metrics connector"]

        otlp --> enrich
        legacy --> enrich
        native --> enrich
        enrich --> traces
        enrich --> logs
        enrich --> metrics
        enrich --> profiles
        traces --> spanmetrics --> metrics
      end

      prometheus["Prometheus"]
      loki["Loki"]
      tempo["Tempo"]
      jaeger["Jaeger<br/>in-memory trace storage · UI"]
      grafana["Grafana"]
      pyroscope["Pyroscope"]
    end
  end

  operator -. "injects SDK configuration" .-> services
  services -->|"OTLP signals"| otlp
  dependencies -->|"scraped metrics"| native
  ad -->|"scraped metrics"| native
  traces -->|"OTLP/gRPC"| tempo
  traces -->|"OTLP/gRPC"| jaeger
  logs -->|"OTLP/HTTP"| loki
  metrics -->|"OTLP/HTTP"| prometheus
  profiles -->|"OTLP/gRPC"| firepit

  grafana -->|"queries"| prometheus
  grafana -->|"queries"| loki
  grafana -->|"queries"| tempo
  grafana -->|"queries"| pyroscope
  jaeger -. "metric queries" .-> prometheus

  classDef signal fill:#e8f1ff,stroke:#4472c4,color:#111;
  classDef backend fill:#f3f3f3,stroke:#666,color:#111;
  class traces,logs,metrics,profiles signal;
  class prometheus,loki,tempo,jaeger,grafana,pyroscope backend;
```

The Operator injects SDK configuration into annotated workloads. The shared
Instrumentation resource points SDKs at the Collector; most use OTLP/HTTP with
protobuf on port `4318`, while some existing demo workloads use OTLP/gRPC on
`4317`.

The Collector also gathers host and Kubernetes metrics, scrapes the demo's Ad
service, and collects PostgreSQL and Kafka metrics. It exports traces to both
Tempo and Jaeger, and derives span metrics that join the metrics pipeline.
Jaeger keeps traces in memory and uses Prometheus for metric queries.

Grafana is configured to query Prometheus, Loki, Tempo, and Pyroscope.
Currently, the Collector's profiles pipeline exports to the demo's FirePit
service; no profile export to Pyroscope is configured.
