from fastapi import FastAPI, Request
from prometheus_client import Counter, Histogram, make_asgi_app
from opentelemetry import trace
from opentelemetry.sdk.resources import Resource
from opentelemetry.sdk.trace import TracerProvider
from opentelemetry.sdk.trace.export import BatchSpanProcessor
from opentelemetry.exporter.otlp.proto.grpc.trace_exporter import OTLPSpanExporter
from opentelemetry.instrumentation.fastapi import FastAPIInstrumentor
import os
import time

app = FastAPI(title="DevOps Showcase API")

# Tracing — exports spans to Tempo via OTLP/gRPC. Tempo's address is injected
# via env var so the same image works in any cluster without rebuilding.
trace.set_tracer_provider(
    TracerProvider(resource=Resource.create({"service.name": "signal-api"}))
)
trace.get_tracer_provider().add_span_processor(
    BatchSpanProcessor(
        OTLPSpanExporter(
            endpoint=os.environ.get("OTEL_EXPORTER_OTLP_ENDPOINT", "tempo.monitoring.svc.cluster.local:4317"),
            insecure=True,
        )
    )
)
# Metrics — label cardinality is intentionally bounded (endpoint + status only)
REQUEST_COUNT = Counter(
    "api_requests_total",
    "Total number of requests",
    ["endpoint", "status"],
)
REQUEST_DURATION = Histogram(
    "api_request_duration_seconds",
    "Request duration in seconds",
    ["endpoint"],
    buckets=[0.01, 0.05, 0.1, 0.25, 0.5, 1.0],
)

@app.middleware("http")
async def record_metrics(request: Request, call_next):
    start = time.time()
    response = await call_next(request)
    duration = time.time() - start
    endpoint = request.url.path
    REQUEST_COUNT.labels(endpoint=endpoint, status=response.status_code).inc()
    REQUEST_DURATION.labels(endpoint=endpoint).observe(duration)

    # Log the trace ID alongside each request — Loki ingests this line, so a
    # span in Tempo can be correlated directly to its log output in Grafana.
    span = trace.get_current_span()
    trace_id = format(span.get_span_context().trace_id, "032x")
    print(f'trace_id={trace_id} method={request.method} path={endpoint} status={response.status_code} duration={duration:.3f}s')

    return response

# Instrument AFTER the custom middleware is registered — Starlette wraps
# middleware in reverse-add order, so this makes OTel's span middleware the
# outermost layer and ensures record_metrics sees an active span/trace_id.
FastAPIInstrumentor.instrument_app(app)

@app.get("/health")
def health():
    return {"status": "ok"}

@app.get("/")
def root():
    return {"service": "devops-showcase", "version": "1.0.0"}

# Mount Prometheus metrics endpoint
metrics_app = make_asgi_app()
app.mount("/metrics", metrics_app)
