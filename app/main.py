from fastapi import FastAPI, Request
from prometheus_client import Counter, Histogram, make_asgi_app
import time

app = FastAPI(title="DevOps Showcase API")

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
    return response

@app.get("/health")
def health():
    return {"status": "ok"}

@app.get("/")
def root():
    return {"service": "devops-showcase", "version": "1.0.0"}

# Mount Prometheus metrics endpoint
metrics_app = make_asgi_app()
app.mount("/metrics", metrics_app)
