# Pipecat Cloud Migration

The official Pipecat quickstart uses a runner-based bot with Daily WebRTC and RTVI. Pipecat Cloud is not a drop-in host for the current `pipecat_agent.py` endpoint because this project currently uses a custom raw PCM WebSocket client in Godot.

## Current local/hosted path

```text
Godot custom WebSocket -> FastAPI Pipecat -> Deepgram -> LLM -> ElevenLabs
```

This path is prepared for a normal WebSocket host such as Railway. It uses `/ws/voice` and raw 16 kHz mono PCM input with 24 kHz mono PCM output.

## Pipecat Cloud path

```text
Godot Daily-compatible client -> Daily WebRTC/RTVI -> Pipecat Cloud runner bot
```

The cloud bot must use the Pipecat runner entrypoint and a supported transport such as Daily. The current Godot client cannot connect to that transport directly because the repository has no Daily SDK or Godot Daily native extension.

## Required migration work

1. Create a runner-based `bot.py` using the official Pipecat quickstart pattern.
2. Replace the custom FastAPI WebSocket transport with `DailyParams` or the supported WebRTC transport.
3. Use Pipecat RTVI events for transcripts, bot state, errors, and connection lifecycle.
4. Add a Daily-compatible Android/native client or a Godot native bridge.
5. Add the official `pcc-deploy.toml` with an agent name, secret set, and at least one warm agent:

```toml
agent_name = "habi-friend"
secret_set = "habi-friend-secrets"

[scaling]
min_agents = 1
```

6. Install and authenticate the CLI, upload secrets, and deploy:

```powershell
uv tool install "pipecat-ai[cli]" --with pipecatcloud
pipecat cloud auth login
pipecat cloud secrets set habi-friend-secrets --file .env
pipecat cloud deploy
```

Do not upload the current `.env` until provider credentials have been rotated and a production-only secret file has been created.

## Decision

Keep the current authenticated raw PCM service for local testing and Railway deployment. Do not point the existing Godot client at Pipecat Cloud until the Daily/RTVI client bridge is implemented. Pipecat Cloud may reduce infrastructure and cold-start latency, but it cannot reduce the OpenRouter or ElevenLabs provider latency by itself.
