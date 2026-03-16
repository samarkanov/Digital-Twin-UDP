FROM ghcr.io/astral-sh/uv:python3.10-bookworm-slim AS builder
ENV UV_COMPILE_BYTECODE=1 UV_LINK_MODE=copy
WORKDIR /app
# Install dependencies first for better caching
RUN --mount=type=cache,target=/root/.cache/uv \
    --mount=type=bind,source=python/publisher/pyproject.toml,target=python/publisher/pyproject.toml \
    uv sync --no-install-project --no-dev --project python/publisher

ADD . /app
RUN --mount=type=cache,target=/root/.cache/uv \
    uv sync --no-dev --project python/publisher

FROM python:3.10-slim-bookworm
WORKDIR /app
COPY --from=builder /app /app
ENV PATH="/app/python/publisher/.venv/bin:$PATH"
WORKDIR /app/python/publisher
CMD ["python", "udp_offset_publisher.py"]
