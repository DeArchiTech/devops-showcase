FROM python:3.12-alpine AS builder
WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir --prefix=/install -r requirements.txt

FROM python:3.12-alpine AS runner
WORKDIR /app

# Non-root user — principle of least privilege
RUN addgroup -S appgroup && adduser -S appuser -G appgroup

COPY --from=builder /install /usr/local
COPY main.py .

USER appuser
EXPOSE 8000
CMD ["uvicorn", "main:app", "--host", "0.0.0.0", "--port", "8000"]
