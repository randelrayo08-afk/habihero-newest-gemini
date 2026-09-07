# Railway Pipecat Deployment

## Create the service

Create a separate Railway service from the `habi-backend` directory. Railway should use the included `Dockerfile`.

Set these variables in the Pipecat service:

```text
PORT=8000
PIPECAT_SESSION_SECRET=<long-random-value>
DEEPGRAM_API_KEY=<provider-key>
OPENROUTER_API_KEY=<provider-key>
OPENROUTER_MODEL=openai/gpt-4o-mini
PIPECAT_LLM_PROVIDER=openrouter
ELEVENLABS_API_KEY=<provider-key>
ELEVENLABS_VOICE_ID=<voice-id>
ELEVENLABS_MODEL=eleven_flash_v2_5
```

Set the exact same `PIPECAT_SESSION_SECRET` in the Node API Railway service. Never commit these values.

The service starts with the Docker command and exposes:

```text
GET  /health
WS   /ws/voice?token=<short-lived-session-token>
```

## Node API

The Node service must expose the authenticated endpoint:

```text
POST /api/pipecat/session
Authorization: Bearer <Firebase ID token>
```

It returns a short-lived token used by the Godot client. Keep the Pipecat service URL separate from the Node API URL.

## Godot

Set the exported `websocket_url` in `pipecat_voice_client.gd` to the Railway URL using `wss://`:

```text
wss://<pipecat-service>.up.railway.app/ws/voice
```

The client obtains the session token from the authenticated Node API before connecting.

## Verification

1. Open the Railway `/health` URL and confirm the response is `{"status":"ok","service":"pipecat"}`.
2. Start the Node API with the same `PIPECAT_SESSION_SECRET`.
3. Log in through Firebase and confirm `POST /api/pipecat/session` returns a token.
4. Run the Godot app outside the local network and test the microphone.
5. Check Pipecat logs for first LLM text and first audio timing.
6. Confirm missing or expired tokens receive WebSocket close code `1008`.
