# ── Build stage ──────────────────────────────────────────────────────────────
FROM docker.io/library/rust:1.85-slim AS builder

WORKDIR /build

# Install build dependencies (needed for some transitive crates)
RUN apt-get update && apt-get install -y --no-install-recommends \
    pkg-config \
    && rm -rf /var/lib/apt/lists/*

# Cache dependency compilation separately from source changes
COPY Cargo.toml Cargo.lock* ./
RUN mkdir -p src && echo 'fn main() {}' > src/main.rs
RUN cargo build --release 2>/dev/null; true

# Build the real binary
COPY src ./src
RUN touch src/main.rs && cargo build --release

# ── Runtime stage ────────────────────────────────────────────────────────────
FROM docker.io/library/debian:bookworm-slim AS runtime

# Install CA certs for TLS connections to the agent
RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates \
    && rm -rf /var/lib/apt/lists/*

# Run as non-root
RUN useradd -u 10001 -m plugin
USER 10001

COPY --from=builder /build/target/release/plugin /usr/local/bin/plugin

# Required env vars — values injected at runtime by the EOS operator:
#   PLUGIN_ID, PLUGIN_TOKEN, IOT_AGENT_WS_URL
ENV RUST_LOG=plugin=info,tokio_tungstenite=warn

ENTRYPOINT ["/usr/local/bin/plugin"]
