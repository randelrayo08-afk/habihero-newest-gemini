# Voice Companion REST API Setup Guide

## Overview

This replaces LiveKit with a simpler REST API-based voice companion. No GDExtension needed.

## Files Created

- **`voice_companion_rest.gd`** - Core voice handler (REST API)
- **`voice_companion_ui.gd`** - UI integration example

## Quick Setup (5 minutes)

### 1. Add to Your Godot Project

```gdscript
# In your home.gd or guidance.gd, add at the top:
var _voice_ui: Control = null

# In _ready():
_voice_ui = VoiceCompanionUI.new()
add_child(_voice_ui)
```

### 2. Ensure Backend is Running

Your `habi-backend/` must have these endpoints working:

```bash
cd habi-backend
npm install
npm start
```

Verify endpoints work:
```bash
curl http://localhost:3000/health

# Test chat endpoint
curl -X POST http://localhost:3000/api/companion/chat \
  -H "Content-Type: application/json" \
  -d '{"message": "Hi", "companionName": "Habi Friend"}'
```

### 3. Configure Backend URL (for APK)

When building APK for production, update `habi_backend.gd`:

```gdscript
# Change from localhost to your deployed server
func get_backend_url() -> String:
	return "https://your-deployed-backend.com"  # Your server URL
```

### 4. Test in Editor

1. Run your Godot project
2. Click the "🎤 Press to Talk" button
3. Speak into your microphone
4. Wait for transcription and reply

## Features

✅ **Voice Input** - Records audio, sends to backend STT
✅ **AI Response** - Gets reply from LLM via backend
✅ **Voice Output** - Plays TTS audio response
✅ **Text Chat** - Fallback text-only chat
✅ **Error Handling** - Graceful error messages
✅ **No GDExtension** - No compilation issues

## Supported Endpoints

| Endpoint | Method | Purpose |
|----------|--------|---------|
| `/api/companion/voice` | POST | Full voice pipeline (STT + LLM + TTS) |
| `/api/companion/chat` | POST | Text chat only |
| `/api/companion/stt` | POST | Speech-to-text only |
| `/api/companion/tts` | POST | Text-to-speech only |

## Backend Environment Variables

Your `.env` must have:

```env
# Required for LLM responses
GROQ_API_KEY=your_groq_key
LLM_PROVIDER=groq
LLM_MODEL=mixtral-8x7b-32768

# Optional: STT provider (uses Deepgram by default)
DEEPGRAM_API_KEY=your_deepgram_key

# Optional: TTS provider (uses Piper by default for local)
ELEVENLABS_API_KEY=your_elevenlabs_key
ELEVENLABS_VOICE_ID=EXAVITQu4vr4xnSDxMaL
```

## APK Deployment Checklist

- [ ] Backend deployed to cloud (Render, DigitalOcean, Heroku)
- [ ] SSL certificate configured (HTTPS required)
- [ ] `habi_backend.gd` updated with production URL
- [ ] APK manifest includes `RECORD_AUDIO` permission
- [ ] Tested voice end-to-end on Android device
- [ ] Error handling tested (no internet, backend down, etc.)

## Troubleshooting

### "Connection refused" Error
- Ensure backend is running: `npm start` in `habi-backend/`
- Check backend URL in `habi_backend.gd`
- For APK, ensure URL is publicly accessible (not localhost)

### No Audio Recorded
- Check microphone permissions in APK settings
- Verify `RECORD_AUDIO` permission in Android manifest

### No Reply Received
- Check backend logs: `tail -f agent-startup.log`
- Verify LLM API key (GROQ, OpenAI, etc.)
- Test manually: `curl http://localhost:3000/api/companion/chat ...`

### Audio Quality Issues
- Try different voice ID: `_voice_companion.set_voice_id("nova")`
- Check sample rate (default 16000 Hz)
- Try different TTS provider in `.env`

## Configuration Examples

### Production Setup (Recommended)

```env
# .env in habi-backend/

# Production LLM
LLM_PROVIDER=groq
GROQ_API_KEY=gsk_xxxxxxxxxxxxxxxx
LLM_MODEL=mixtral-8x7b-32768

# STT
DEEPGRAM_API_KEY=xxxxxxxxxxxx
DEEPGRAM_MODEL=nova-2-general

# TTS
ELEVENLABS_API_KEY=sk_xxxxxxxx
ELEVENLABS_VOICE_ID=EXAVITQu4vr4xnSDxMaL
ELEVENLABS_MODEL=eleven_flash_v2_5

# Port
PORT=3000
NODE_ENV=production
```

### Local Development Setup

```env
# .env in habi-backend/

# Local LLM (Ollama)
LLM_PROVIDER=local-ollama
LOCAL_OLLAMA_URL=http://localhost:11434

# Local STT (Whisper.cpp)
LOCAL_STT_PROVIDER=whisper
WHISPER_CPP_PATH=/path/to/whisper.cpp

# Local TTS (Piper)
LOCAL_TTS_PROVIDER=piper
PIPER_TTS_URL=http://localhost:8000

# Port
PORT=3000
NODE_ENV=development
```

## Monitoring

Check backend health:
```bash
curl http://localhost:3000/health
# Response: {"status": "ok"}
```

Check logs:
```bash
tail -f habi-backend/agent-startup.log
```

## Next Steps

1. Test voice companion in development
2. Deploy backend to production
3. Build and test APK on Android device
4. Monitor voice usage and quality
5. Iterate on prompt/voice settings

## Support

If you encounter issues:
1. Check backend logs
2. Test endpoints manually with `curl`
3. Verify API keys are valid
4. Check GitHub issues: https://github.com/NodotProject/godot-livekit/issues
