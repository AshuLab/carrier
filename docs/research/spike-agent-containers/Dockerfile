FROM node:26-bookworm-slim
RUN apt-get update && apt-get install -y --no-install-recommends git ca-certificates curl procps gh && rm -rf /var/lib/apt/lists/*
RUN npm i -g pnpm@12.4.1 @anthropic-ai/claude-code@2.1.301 @openai/codex@0.153.4 2>&1 | tail -5
RUN git config --system safe.directory '*'
