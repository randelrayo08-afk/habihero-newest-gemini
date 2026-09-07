import express from 'express';
import cors from 'cors';
import dotenv from 'dotenv';
import admin from 'firebase-admin';
import fs from 'fs';
import path from 'path';
import os from 'os';
import { spawnSync } from 'child_process';
import { fileURLToPath } from 'url';
import { AccessToken, AgentDispatchClient, RoomServiceClient } from 'livekit-server-sdk';
import { WebSocketServer, WebSocket } from 'ws';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

dotenv.config({ path: path.join(__dirname, '.env') });

const app = express();
const PORT = process.env.PORT || 5000;
const GEMINI_LIVE_MODEL = process.env.GEMINI_LIVE_MODEL || 'models/gemini-2.5-flash-native-audio-latest';
const GEMINI_VOICE_NAME = process.env.GEMINI_VOICE_NAME || 'Puck';
const SAFETY_REFUSAL = "I can't help with weapons, explosives, harming someone, or anything dangerous. Please talk to a trusted adult if you are worried about safety.";
const GEMINI_SYSTEM_INSTRUCTION = `You are Habi Friend, a kind and concise voice companion for Grade 6 students. Use simple, age-appropriate, faith-friendly language. Keep spoken replies brief, warm, and practical. Do not use markdown, emojis, or profanity. Never provide instructions, recipes, materials, quantities, or steps for weapons, bombs, explosives, arson, violence, self-harm, or harming another person. If asked about those topics, refuse briefly and encourage the student to speak with a trusted adult or emergency services if someone is in immediate danger.`;
const DEFAULT_LIVEKIT_ROOM_NAME = 'habi-voice-room';
const DEFAULT_LIVEKIT_AGENT_NAME = 'habi-friend';

// Middleware
app.use(cors());
// Allow larger JSON payloads for base64-encoded audio uploads (push-to-talk recordings)
app.use(express.json({ limit: '15mb' }));

// Firebase Admin SDK Initialization
let serviceAccount;
try {
  const serviceAccountPath = ['serviceAccountKey.json', 'serviceaccountkey.json']
    .map(fileName => path.join(__dirname, fileName))
    .find(filePath => fs.existsSync(filePath));

  if (serviceAccountPath) {
    const serviceAccountFile = fs.readFileSync(serviceAccountPath);
    serviceAccount = JSON.parse(serviceAccountFile);
    console.log('✓ Service account key loaded from file');
  } else {
    const encodedPrivateKey = String(process.env.FIREBASE_PRIVATE_KEY_BASE64 || '').trim();
    const privateKey = (encodedPrivateKey
      ? Buffer.from(encodedPrivateKey, 'base64').toString('utf8')
      : String(process.env.FIREBASE_PRIVATE_KEY || ''))
      .trim()
      .replace(/^['"]|['"]$/g, '')
      .replace(/\\\\n/g, '\n')
      .replace(/\\n/g, '\n');
    const clientEmail = String(process.env.FIREBASE_CLIENT_EMAIL || '').trim();
    const projectId = String(process.env.FIREBASE_PROJECT_ID || '').trim();
    if (!privateKey || !clientEmail || !projectId) {
      throw new Error('Set FIREBASE_PROJECT_ID, FIREBASE_CLIENT_EMAIL, and FIREBASE_PRIVATE_KEY in the environment, or provide serviceAccountKey.json');
    }
    serviceAccount = { project_id: projectId, client_email: clientEmail, private_key: privateKey };
    console.log('✓ Firebase service account loaded from environment');
  }
} catch (error) {
  console.error('✗ Failed to load service account key:', error.message);
  process.exit(1);
}

try {
  const firebaseProjectId = process.env.FIREBASE_PROJECT_ID || serviceAccount.project_id || 'adv-habi';
  const firebaseDatabaseUrl = process.env.FIREBASE_DATABASE_URL || `https://${firebaseProjectId}-default-rtdb.firebaseio.com`;
  const serviceAccountProjectId = String(serviceAccount.project_id || '').trim();
  if (serviceAccountProjectId && firebaseProjectId && serviceAccountProjectId !== firebaseProjectId) {
    throw new Error(`Firebase project mismatch: environment expects "${firebaseProjectId}" but the service account belongs to "${serviceAccountProjectId}".`);
  }
  admin.initializeApp({
    credential: admin.credential.cert(serviceAccount),
    databaseURL: firebaseDatabaseUrl
  });
  console.log('✓ Firebase initialized successfully for project:', firebaseProjectId);
} catch (error) {
  console.error('✗ Firebase initialization failed:', error.message);
  process.exit(1);
}

const db = admin.database();
const LOCAL_TTS_PROVIDER = process.env.LOCAL_TTS_PROVIDER || 'elevenlabs';
const PIPER_TTS_URL = process.env.PIPER_TTS_URL || process.env.LOCAL_TTS_BASE_URL || 'http://127.0.0.1:5002/api/tts';
const PIPER_OUTPUT_FORMAT = process.env.PIPER_OUTPUT_FORMAT || 'wav';
const PIPER_DEFAULT_VOICE_ID = process.env.PIPER_DEFAULT_VOICE_ID || 'en_US-lessac-medium';
const LOCAL_TTS_FALLBACK = process.env.LOCAL_TTS_FALLBACK || 'openai';
const OPENAI_CHAT_MODEL = process.env.OPENAI_CHAT_MODEL || 'gpt-4.1-mini';
const deepgramLanguage = process.env.DEEPGRAM_LANGUAGE || 'auto';
const STT_PROVIDER = String(process.env.STT_PROVIDER || 'deepgram').toLowerCase();

console.log('TTS configuration:');
console.log('  LOCAL_TTS_PROVIDER =', LOCAL_TTS_PROVIDER);
console.log('  PIPER_TTS_URL =', PIPER_TTS_URL);
console.log('  LOCAL_TTS_FALLBACK =', LOCAL_TTS_FALLBACK);
console.log('  DEEPGRAM_LANGUAGE =', deepgramLanguage);
console.log('  STT_PROVIDER =', STT_PROVIDER);

function normalizeLiveKitHostForServerSdk(rawUrl) {
  const cleaned = String(rawUrl || '').trim();
  if (!cleaned) {
    return '';
  }

  if (cleaned.startsWith('ws://')) {
    return `http://${cleaned.slice('ws://'.length)}`;
  }

  if (cleaned.startsWith('wss://')) {
    return `https://${cleaned.slice('wss://'.length)}`;
  }

  return cleaned;
}

function isOpenAiQuotaError(error) {
  const msg = String(error?.message || error || '').toLowerCase();
  return !!(
    error?.status === 429 ||
    msg.includes('credit_balance_exhausted') ||
    msg.includes('insufficient_quota') ||
    msg.includes('no credits remaining') ||
    msg.includes('quota') ||
    msg.includes('429')
  );
}

function disableOpenAiQuotaKey() {
  const current = (process.env.OPENAI_API_KEY || '').trim();
  if (current) {
    console.warn('[provider] OpenAI API key is exhausted or invalid; disabling it for this session to avoid repeated quota failures.');
    process.env.OPENAI_API_KEY = '';
  }
}

// ============ LOCAL TTS HELPERS ============

function escapeForPowerShellSingleQuotedString(value) {
  return String(value || '').replace(/'/g, "''");
}

function synthesizeWithWindowsSapi(text, voiceName) {
  const outputPath = path.join(os.tmpdir(), `habi_tts_${Date.now()}.wav`);
  const escapedText = escapeForPowerShellSingleQuotedString(text);
  const escapedVoiceName = escapeForPowerShellSingleQuotedString(voiceName);

  const command = [
    "Add-Type -AssemblyName System.Speech",
    "$synth = New-Object System.Speech.Synthesis.SpeechSynthesizer",
    `$voice = '${escapedVoiceName}'`,
    "if ($voice -ne '') { try { $synth.SelectVoice($voice) } catch {} }",
    `$output = '${escapeForPowerShellSingleQuotedString(outputPath)}'`,
    "$synth.SetOutputToWaveFile($output)",
    `$synth.Speak('${escapedText}')`,
    "$synth.Dispose()",
    `Write-Output $output`
  ].join('; ');

  const result = spawnSync('powershell', ['-NoProfile', '-Command', command], {
    encoding: 'utf8'
  });

  if (result.status !== 0) {
    throw new Error((result.stderr || result.stdout || 'Windows SAPI synthesis failed').trim());
  }

  if (!fs.existsSync(outputPath)) {
    throw new Error('Windows SAPI did not produce an audio file');
  }

  const audioBuffer = fs.readFileSync(outputPath);
  fs.unlinkSync(outputPath);

  // Ensure WAV is in a compatible format (44.1kHz, 16-bit PCM) for clients
  const finalBuffer = ensureWavCompatible(audioBuffer) || audioBuffer;

  return {
    audioBuffer: finalBuffer,
    contentType: 'audio/wav',
    provider: 'windows-sapi'
  };
}

// Convert WAV to 44.1kHz 16-bit PCM using ffmpeg if available. Returns converted buffer or null on failure.
function ensureWavCompatible(buffer) {
  try {
    const tmpIn = path.join(os.tmpdir(), `habi_wav_in_${Date.now()}.wav`);
    const tmpOut = path.join(os.tmpdir(), `habi_wav_out_${Date.now()}.wav`);
    fs.writeFileSync(tmpIn, buffer);

    const ff = spawnSync('ffmpeg', ['-y', '-i', tmpIn, '-ar', '44100', '-ac', '1', '-c:a', 'pcm_s16le', tmpOut], { encoding: 'utf8' });

    // cleanup input file
    try { fs.unlinkSync(tmpIn); } catch (e) {}

    if (ff.status === 0 && fs.existsSync(tmpOut)) {
      const outBuf = fs.readFileSync(tmpOut);
      try { fs.unlinkSync(tmpOut); } catch (e) {}
      return outBuf;
    } else {
      // ffmpeg failed or not available; log for debugging
      console.warn('ensureWavCompatible: ffmpeg conversion failed or not available', ff.stderr || ff.stdout || ff.error || 'no output');
      try { if (fs.existsSync(tmpOut)) fs.unlinkSync(tmpOut); } catch (e) {}
      return null;
    }
  } catch (e) {
    console.warn('ensureWavCompatible error:', e.message || e);
    return null;
  }
}

function getWavDataInfo(buffer) {
  try {
    if (!buffer || buffer.length < 12) {
      return null;
    }

    const riff = buffer.toString('ascii', 0, 4);
    const wave = buffer.toString('ascii', 8, 12);
    if (riff !== 'RIFF' || wave !== 'WAVE') {
      return null;
    }

    let offset = 12;
    let fmt = null;
    let dataOffset = null;
    let dataSize = 0;

    while (offset + 8 <= buffer.length) {
      const chunkId = buffer.toString('ascii', offset, offset + 4);
      const chunkSize = buffer.readUInt32LE(offset + 4);
      const chunkStart = offset + 8;

      if (chunkId === 'fmt ') {
        const audioFormat = buffer.readUInt16LE(chunkStart + 0);
        const numChannels = buffer.readUInt16LE(chunkStart + 2);
        const sampleRate = buffer.readUInt32LE(chunkStart + 4);
        const byteRate = buffer.readUInt32LE(chunkStart + 8);
        const blockAlign = buffer.readUInt16LE(chunkStart + 12);
        const bitsPerSample = buffer.readUInt16LE(chunkStart + 14);
        fmt = { audioFormat, numChannels, sampleRate, byteRate, blockAlign, bitsPerSample };
      } else if (chunkId === 'data') {
        dataOffset = chunkStart;
        dataSize = chunkSize;
        break;
      }

      offset = chunkStart + chunkSize + (chunkSize % 2);
    }

    if (!fmt || dataOffset === null) {
      return null;
    }

    return { fmt, dataOffset, dataSize };
  } catch (e) {
    console.warn('getWavDataInfo error:', e.message || e);
    return null;
  }
}

function convertWavToSttCompatible(buffer) {
  try {
    const info = getWavDataInfo(buffer);
    if (!info || !info.fmt) {
      return null;
    }

    const fmt = info.fmt;
    if (fmt.audioFormat !== 1 || fmt.bitsPerSample !== 16) {
      console.warn('[convertWavToSttCompatible] unsupported WAV format:', fmt);
      return null;
    }

    const srcChannels = Math.max(1, fmt.numChannels || 1);
    const sampleRate = fmt.sampleRate || 44100;
    const bytesPerSample = fmt.bitsPerSample / 8;
    const sampleCount = Math.floor(info.dataSize / (bytesPerSample * srcChannels));
    if (sampleCount <= 0) {
      return null;
    }

    const source = new Int16Array(buffer.buffer, buffer.byteOffset + info.dataOffset, sampleCount * srcChannels);
    const monoSamples = new Array(sampleCount);

    for (let i = 0; i < sampleCount; i++) {
      const offsetIndex = i * srcChannels;
      let total = 0;
      const channelsToRead = Math.min(srcChannels, 2);
      for (let ch = 0; ch < channelsToRead; ch++) {
        total += source[offsetIndex + ch] || 0;
      }
      monoSamples[i] = Math.round(total / channelsToRead);
    }

    const targetRate = 16000;
    const targetCount = Math.max(1, Math.round(monoSamples.length * targetRate / sampleRate));
    const resampled = new Int16Array(targetCount);

    for (let i = 0; i < targetCount; i++) {
      const pos = i / Math.max(1, targetCount - 1) * (monoSamples.length - 1);
      const idx = Math.floor(pos);
      const frac = pos - idx;
      const a = monoSamples[idx] || 0;
      const b = monoSamples[Math.min(monoSamples.length - 1, idx + 1)] || 0;
      resampled[i] = Math.max(-32768, Math.min(32767, Math.round(a + (b - a) * frac)));
    }

    const output = Buffer.alloc(44 + resampled.length * 2);
    output.write('RIFF', 0);
    output.writeUInt32LE(36 + resampled.length * 2, 4);
    output.write('WAVE', 8);
    output.write('fmt ', 12);
    output.writeUInt32LE(16, 16);
    output.writeUInt16LE(1, 20);
    output.writeUInt16LE(1, 22);
    output.writeUInt32LE(targetRate, 24);
    output.writeUInt32LE(targetRate * 2, 28);
    output.writeUInt16LE(2, 32);
    output.writeUInt16LE(16, 34);
    output.write('data', 36);
    output.writeUInt32LE(resampled.length * 2, 40);

    for (let i = 0; i < resampled.length; i++) {
      output.writeInt16LE(resampled[i], 44 + i * 2);
    }

    return output;
  } catch (e) {
    console.warn('convertWavToSttCompatible error:', e.message || e);
    return null;
  }
}

// Parse basic WAV header info from a buffer. Returns null on failure.
function parseWavHeader(buffer) {
  try {
    if (!buffer || buffer.length < 44) return null;
    const sig = buffer.toString('ascii', 0, 4);
    const wave = buffer.toString('ascii', 8, 12);
    if (sig !== 'RIFF' || wave !== 'WAVE') return null;

    let offset = 12;
    let fmt = null;
    let data = null;

    while (offset + 8 <= buffer.length) {
      const chunkId = buffer.toString('ascii', offset, offset + 4);
      const chunkSize = buffer.readUInt32LE(offset + 4);
      const chunkStart = offset + 8;

      if (chunkId === 'fmt ') {
        const audioFormat = buffer.readUInt16LE(chunkStart + 0);
        const numChannels = buffer.readUInt16LE(chunkStart + 2);
        const sampleRate = buffer.readUInt32LE(chunkStart + 4);
        const byteRate = buffer.readUInt32LE(chunkStart + 8);
        const blockAlign = buffer.readUInt16LE(chunkStart + 12);
        const bitsPerSample = buffer.readUInt16LE(chunkStart + 14);
        fmt = { audioFormat, numChannels, sampleRate, byteRate, blockAlign, bitsPerSample };
      } else if (chunkId === 'data') {
        data = { dataSize: chunkSize, dataStart: chunkStart };
      }

      offset = chunkStart + chunkSize;
    }

    if (!fmt) return null;
    return {
      format: fmt.audioFormat,
      channels: fmt.numChannels,
      sampleRate: fmt.sampleRate,
      bitsPerSample: fmt.bitsPerSample,
      byteRate: fmt.byteRate,
      blockAlign: fmt.blockAlign,
      dataSize: data ? data.dataSize : 0
    };
  } catch (e) {
    console.warn('parseWavHeader error:', e.message || e);
    return null;
  }
}

function normalizeWavForStt(buffer, contentType) {
  try {
    if (!buffer || buffer.length === 0) {
      return buffer;
    }

    const header = parseWavHeader(buffer);
    const isWav = (contentType || '').toLowerCase().includes('wav') || (header !== null && buffer.toString('ascii', 0, 4) === 'RIFF');

    if (!isWav) {
      return buffer;
    }

    const tmpIn = path.join(os.tmpdir(), `habi_stt_in_${Date.now()}.wav`);
    const tmpOut = path.join(os.tmpdir(), `habi_stt_out_${Date.now()}.wav`);
    fs.writeFileSync(tmpIn, buffer);

    const ff = spawnSync('ffmpeg', [
      '-y',
      '-i', tmpIn,
      '-ar', '16000',
      '-ac', '1',
      '-c:a', 'pcm_s16le',
      '-f', 'wav',
      tmpOut
    ], { encoding: 'utf8' });

    try { fs.unlinkSync(tmpIn); } catch (e) {}

    if (ff.status === 0 && fs.existsSync(tmpOut)) {
      const outBuf = fs.readFileSync(tmpOut);
      try { fs.unlinkSync(tmpOut); } catch (e) {}
      const normalizedHeader = parseWavHeader(outBuf);
      console.log('[transcribeAudio] normalized wav -> sampleRate=', normalizedHeader?.sampleRate || 'unknown', 'channels=', normalizedHeader?.channels || 'unknown');
      return outBuf;
    }

    console.warn('[transcribeAudio] ffmpeg normalization failed or unavailable; trying JS fallback', ff.stderr || ff.stdout || ff.error || 'no output');
    try { if (fs.existsSync(tmpOut)) fs.unlinkSync(tmpOut); } catch (e) {}

    const jsNormalized = convertWavToSttCompatible(buffer);
    if (jsNormalized) {
      const normalizedHeader = parseWavHeader(jsNormalized);
      console.log('[transcribeAudio] JS normalized wav -> sampleRate=', normalizedHeader?.sampleRate || 'unknown', 'channels=', normalizedHeader?.channels || 'unknown');
      return jsNormalized;
    }

    return buffer;
  } catch (e) {
    console.warn('[transcribeAudio] normalizeWavForStt error:', e.message || e);
    return buffer;
  }
}

function wavHasMeaningfulAudio(buffer) {
  try {
    if (!buffer || buffer.length < 64) {
      return false;
    }

    const header = parseWavHeader(buffer);
    if (!header || header.dataSize <= 0) {
      return false;
    }

    console.log('[wavHasMeaningfulAudio] wav bytes=', buffer.length, 'sampleRate=', header.sampleRate, 'channels=', header.channels, 'bits=', header.bitsPerSample, 'dataSize=', header.dataSize);

    return true;
  } catch (error) {
    console.warn('[wavHasMeaningfulAudio] failed to inspect audio:', error.message || error);
    return true;
  }
}

async function transcribeAudio(buffer, contentType) {
  const normalizedBuffer = normalizeWavForStt(buffer, contentType);
  if (!wavHasMeaningfulAudio(normalizedBuffer)) {
    throw new Error('Recorded audio is empty, too short, or too quiet for transcription. Please speak clearly for a few seconds.');
  }

  const deepgramKey = (process.env.DEEPGRAM_API_KEY || '').trim();
  const deepgramModel = process.env.DEEPGRAM_MODEL || 'nova-2-general';
  const deepgramLang = process.env.DEEPGRAM_LANGUAGE || '';
  const languageQuery = deepgramLang && deepgramLang.toLowerCase() !== 'auto' ? `&language=${encodeURIComponent(deepgramLang)}` : '';
  const openAiKey = (process.env.OPENAI_API_KEY || '').trim();

  let deepgramError = null;

  if (deepgramKey && STT_PROVIDER !== 'openai') {
    try {
      const accountResp = await fetch('https://api.deepgram.com/v1/projects', {
        method: 'GET',
        headers: {
          'Authorization': `Token ${deepgramKey}`,
          'Accept': 'application/json'
        }
      });

      if (!accountResp.ok) {
        const accountText = await accountResp.text();
        const accountMessage = accountText || 'Deepgram account validation failed';
        deepgramError = new Error(`Deepgram API authentication or credits check failed (${accountResp.status}): ${accountMessage}`);
        console.warn('[transcribeAudio] Deepgram key rejected by Deepgram API:', deepgramError.message);
      } else {
        const dgUrl = `https://api.deepgram.com/v1/listen?model=${encodeURIComponent(deepgramModel)}${languageQuery}`;
        // Try Deepgram once, and retry a single time if it returns an empty transcript
        const dgResp = await fetch(dgUrl, {
          method: 'POST',
          headers: {
            'Content-Type': contentType || 'audio/wav',
            'Authorization': `Token ${deepgramKey}`
          },
          body: normalizedBuffer
        });

        if (!dgResp.ok) {
          const txt = await dgResp.text();
          deepgramError = new Error(`Deepgram STT failed (${dgResp.status}): ${txt}`);
          console.warn('[transcribeAudio] Deepgram failed, trying OpenAI fallback:', deepgramError.message);
        } else {
          const dgJson = await dgResp.json();
          let transcript = dgJson?.results?.channels?.[0]?.alternatives?.[0]?.transcript || '';

          if (transcript.trim().length === 0) {
            // Retry once after a short backoff — sometimes short/partial audio can return empty on first try
            try {
              await new Promise((r) => setTimeout(r, 200));
              const dgResp2 = await fetch(dgUrl, {
                method: 'POST',
                headers: {
                  'Content-Type': contentType || 'audio/wav',
                  'Authorization': `Token ${deepgramKey}`
                },
                body: normalizedBuffer
              });
              if (dgResp2.ok) {
                const dgJson2 = await dgResp2.json();
                transcript = dgJson2?.results?.channels?.[0]?.alternatives?.[0]?.transcript || '';
                if (transcript.trim().length > 0) {
                  return { transcript, raw: dgJson2, provider: 'deepgram' };
                }
              }
            } catch (e) {
              console.warn('[transcribeAudio] Deepgram retry failed:', e.message || e);
            }
          }

          if (transcript.trim().length > 0) {
            return { transcript, raw: dgJson, provider: 'deepgram' };
          }

          deepgramError = new Error('Deepgram returned an empty transcript');
          console.warn('[transcribeAudio] Deepgram returned empty transcript, trying OpenAI fallback');
        }
      }
    } catch (error) {
      deepgramError = error;
      console.warn('[transcribeAudio] Deepgram request failed, trying OpenAI fallback:', error.message || error);
    }
  }

  if (deepgramError) {
    throw deepgramError;
  }

  if (openAiKey) {
    throw new Error('OpenAI Whisper returned an empty transcript');
  }

  throw new Error('No STT provider configured on server (set DEEPGRAM_API_KEY or OPENAI_API_KEY)');
}

async function buildCompanionReply(message, companionName) {
  const cleaned = String(message || '').trim();
  if (!cleaned) {
    return "I couldn’t catch that. Could you say it again?";
  }

  if (isUnsafeInstructionRequest(cleaned)) {
    return SAFETY_REFUSAL;
  }

  const lowerMessage = cleaned.toLowerCase();
  const mathReply = tryMathReply(cleaned);
  const profanityReply = tryProfanityReply(lowerMessage);

  if (mathReply) {
    return profanityReply
      ? `${mathReply} Also, please remember that such words are not fitting for a kind and respectful student. Let us speak gently and with honor as we learn.`
      : mathReply;
  }

  const llmProvider = String(process.env.LLM_PROVIDER || 'openai').trim().toLowerCase();
  const llmKey = llmProvider === 'openrouter'
    ? String(process.env.OPENROUTER_API_KEY || '').trim()
    : String(process.env.OPENAI_API_KEY || '').trim();
  if (llmKey) {
    try {
      return await generateAIBasedReply(cleaned, companionName, llmKey, llmProvider);
    } catch (error) {
      console.warn(`[buildCompanionReply] ${llmProvider} fallback:`, error.message || error);
    }
  }

  return buildFallbackCompanionReply(cleaned);
}

function buildFallbackCompanionReply(message) {
  const cleaned = String(message || '').trim();
  if (!cleaned) {
    return "I couldn’t catch that. Could you say it again?";
  }

  const lowerMessage = cleaned.toLowerCase();
  const mathReply = tryMathReply(cleaned);
  const suggestionReply = trySuggestionReply(lowerMessage);
  const generalKnowledgeReply = tryGeneralKnowledgeReply(lowerMessage);
  const educationReply = tryEducationalReply(lowerMessage);
  const emotionReply = tryEmotionReply(lowerMessage);
  const profanityReply = tryProfanityReply(lowerMessage);

  const candidates = [
    { reply: mathReply, score: mathReply ? 70 : 0 },
    { reply: generalKnowledgeReply, score: generalKnowledgeReply ? 60 : 0 },
    { reply: suggestionReply, score: suggestionReply ? 50 : 0 },
    { reply: educationReply, score: educationReply ? 45 : 0 },
    { reply: emotionReply, score: emotionReply ? 35 : 0 }
  ].filter((item) => item.reply);

  if (candidates.length > 0) {
    candidates.sort((a, b) => b.score - a.score);
    const chosen = candidates[0].reply;
    return profanityReply
      ? `${chosen} Also, please remember that such words are not fitting for a kind and respectful student. Let us speak gently and with honor as we learn.`
      : chosen;
  }

  if (profanityReply) {
    return profanityReply;
  }

  let reply = `Thank you for sharing that with me. I'm here with you, and I want to understand more.`;

  if (/\b(sad|hurt|stress|tired|cry)\b/.test(lowerMessage)) {
    reply = `You seem to be having a bad day. Do you want to talk about it?`;
  } else if (/\b(happy|achieve|proud|win|success)\b/.test(lowerMessage)) {
    reply = `That is amazing, and I am genuinely proud of you. You worked for that moment, and you deserve to feel good about it. What part of it means the most to you?`;
  } else if (/\b(anxious|afraid|worry|panic|overwhelm)\b/.test(lowerMessage)) {
    reply = `Thank you for trusting me with that. Let's slow it down together. What feels like the biggest thing on your mind right now?`;
  } else if (/\b(lonely|alone|nobody)\b/.test(lowerMessage)) {
    reply = `I'm here with you right now. Feeling alone can hurt a lot, and your feelings matter. Do you want to talk about what has been making you feel this way?`;
  }

  return reply;
}

async function generateAIBasedReply(message, companionName, apiKey, provider = 'openai') {
  const trimmedName = String(companionName || 'Habi Friend').trim() || 'Habi Friend';
  const knowledgeText = '';
  const promptSystem = `You are ${trimmedName}, an AI companion for Grade 6 students. Your most important rules are:
- Do not use profanity.
- Keep responses age-appropriate and faith-friendly.
- Respond with emotional intelligence when the user is sad, happy, worried, or excited.
- Be gentle, kind, and supportive, especially in emotional situations.
- Use simple language and stay friendly.
- When helpful, refer the student to guidance, faith values, and respectful support.
You may use your own knowledge and reasoning; you do not need training examples from the user.`;
  const promptUser = knowledgeText
    ? `The user said: "${message}"

Use the following Habi Hero knowledge when answering:
${knowledgeText}

As ${trimmedName}, respond thoughtfully and directly. Show that you understand the user's message and explain your answer in a friendly, personal voice. Avoid sounding robotic or overly formal. If this is a question, answer it clearly using your own knowledge. If it is an emotion or problem, respond with empathy and practical support.`
    : `The user said: "${message}"

As ${trimmedName}, respond thoughtfully and directly. Show that you understand the user's message and explain your answer in a friendly, personal voice. Avoid sounding robotic or overly formal. If this is a question, answer it clearly using your own knowledge. If it is an emotion or problem, respond with empathy and practical support.`;

  const payload = {
    model: provider === 'openrouter'
      ? (process.env.OPENROUTER_MODEL || 'openai/gpt-4o-mini')
      : OPENAI_CHAT_MODEL,
    messages: [
      { role: 'system', content: promptSystem },
      { role: 'user', content: promptUser }
    ],
    temperature: 0.78,
    max_tokens: 220,
    top_p: 0.95,
    frequency_penalty: 0.2,
    presence_penalty: 0.2
  };

  const completionsUrl = provider === 'openrouter'
    ? 'https://openrouter.ai/api/v1/chat/completions'
    : 'https://api.openai.com/v1/chat/completions';
  const response = await fetch(completionsUrl, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      'Authorization': `Bearer ${apiKey}`
    },
    body: JSON.stringify(payload)
  });

  if (!response.ok) {
    const responseText = await response.text();
    const apiError = new Error(`${provider} chat completion failed (${response.status}): ${responseText}`);
    apiError.status = response.status;
    if (isOpenAiQuotaError(apiError)) {
      disableOpenAiQuotaKey();
    }
    throw apiError;
  }

  const data = await response.json();
  const reply = String(data?.choices?.[0]?.message?.content || '').trim();
  if (!reply) {
    throw new Error(`${provider} returned an empty chat reply`);
  }

  if (isUnsafeInstructionRequest(reply)) {
    return SAFETY_REFUSAL;
  }

  const profanityReply = tryProfanityReply(message.toLowerCase());
  if (profanityReply && !/\b(kind|respect|gentle|please|thank|sorry)\b/i.test(reply)) {
    return `${reply} ${profanityReply}`;
  }

  return reply;
}

function isUnsafeInstructionRequest(text) {
  const normalized = String(text || '').toLowerCase();
  const dangerousTopic = /\b(bomb|explosive|explosives|weapon|weapons|firebomb|grenade|detonator|arson|napalm|poison|harm someone|hurt someone|self[- ]harm)\b/.test(normalized);
  const instructionIntent = /\b(make|build|create|construct|assemble|craft|mix|detonate|ignite|use|steps?|instructions?|recipe|materials?|how to|how do i)\b/.test(normalized);
  return dangerousTopic && instructionIntent;
}

const numberUnits = {
  zero: 0, one: 1, two: 2, three: 3, four: 4, five: 5,
  six: 6, seven: 7, eight: 8, nine: 9, ten: 10,
  eleven: 11, twelve: 12, thirteen: 13, fourteen: 14, fifteen: 15,
  sixteen: 16, seventeen: 17, eighteen: 18, nineteen: 19
};
const numberTens = {
  twenty: 20, thirty: 30, forty: 40, fifty: 50,
  sixty: 60, seventy: 70, eighty: 80, ninety: 90
};
const numberScales = {
  hundred: 100,
  thousand: 1000,
  million: 1000000
};

function parseNumberPhrase(words) {
  let total = 0;
  let current = 0;
  let hadNumber = false;

  for (const word of words) {
    if (numberUnits[word] !== undefined) {
      current += numberUnits[word];
      hadNumber = true;
      continue;
    }
    if (numberTens[word] !== undefined) {
      current += numberTens[word];
      hadNumber = true;
      continue;
    }
    if (numberScales[word] !== undefined) {
      if (!hadNumber) {
        current = 1;
      }
      current *= numberScales[word];
      if (numberScales[word] >= 1000) {
        total += current;
        current = 0;
      }
      hadNumber = true;
      continue;
    }
    return null;
  }

  if (!hadNumber) {
    return null;
  }

  return total + current;
}

function isNumberToken(token) {
  const lower = token.toLowerCase();
  return (
    numberUnits[lower] !== undefined ||
    numberTens[lower] !== undefined ||
    numberScales[lower] !== undefined ||
    /^[-+]?[0-9]+(?:\.[0-9]+)?$/.test(lower)
  );
}

const ambiguousNumberWordMap = {
  tree: 'three',
  too: 'two',
  to: 'two',
  for: 'four',
  won: 'one',
  ate: 'eight'
};

function normalizeAmbiguousNumberWords(text) {
  return text
    .split(/\s+/)
    .map((token) => {
      const lower = token.toLowerCase();
      return ambiguousNumberWordMap[lower] !== undefined ? ambiguousNumberWordMap[lower] : token;
    })
    .join(' ');
}

function findAmbiguousNumberWords(text) {
  const tokens = text.toLowerCase().split(/\s+/).filter(Boolean);
  return tokens.filter((token) => Object.prototype.hasOwnProperty.call(ambiguousNumberWordMap, token));
}

function replaceNumberWordsInMathExpression(text) {
  const normalizedText = normalizeAmbiguousNumberWords(text);
  const tokens = normalizedText.split(/\s+/).filter(Boolean);
  const outputTokens = [];
  let buffer = [];

  const flushBuffer = () => {
    if (!buffer.length) {
      return;
    }
    const parsed = parseNumberPhrase(buffer);
    if (parsed !== null) {
      outputTokens.push(String(parsed));
    } else {
      outputTokens.push(...buffer);
    }
    buffer = [];
  };

  for (const token of tokens) {
    const lower = token.toLowerCase();
    if (numberUnits[lower] !== undefined || numberTens[lower] !== undefined || numberScales[lower] !== undefined) {
      buffer.push(lower);
      continue;
    }
    const invalidNumberWord = buffer.length > 0 && !isNumberToken(lower) && !/[+\-*/()=]/.test(lower);
    if (invalidNumberWord) {
      return text;
    }
    flushBuffer();
    outputTokens.push(token);
  }

  flushBuffer();
  return outputTokens.join(' ');
}

function extractNumbersFromText(text) {
  const normalized = text.toLowerCase().replace(/[^a-z0-9.,;\s\-]/g, ' ');
  const rawSegments = normalized.split(/[,;]+/).map((segment) => segment.trim()).filter(Boolean);
  const segments = [];

  for (const segment of rawSegments) {
    const phraseTokens = segment.split(/\s+/).filter(Boolean);
    const phraseParsed = parseNumberPhrase(phraseTokens);
    if (phraseParsed !== null && phraseTokens.length > 1 && !/[0-9]/.test(segment)) {
      segments.push(segment);
      continue;
    }

    const subSegments = segment.split(/\band\b|\bor\b/).map((part) => part.trim()).filter(Boolean);
    segments.push(...subSegments);
  }

  const numbers = [];

  for (const segment of segments) {
    const digitMatches = [...segment.matchAll(/[-+]?[0-9]+(?:\.[0-9]+)?/g)].map((m) => Number(m[0]));
    const hasOnlyDigits = digitMatches.length > 0 && segment.replace(/[-+]?[0-9]+(?:\.[0-9]+)?/g, '').trim() === '';
    if (hasOnlyDigits) {
      numbers.push(...digitMatches);
      continue;
    }

    const tokens = segment.split(/\s+/).filter(Boolean);
    if (tokens.length === 0) {
      continue;
    }

    const parsed = parseNumberPhrase(tokens);
    if (parsed !== null) {
      numbers.push(parsed);
    }
  }

  return numbers;
}

function tryMathReply(message) {
  const cleaned = String(message || '').trim();
  if (!cleaned) {
    return null;
  }

  const normalized = cleaned.toLowerCase();
  const ambiguousWords = findAmbiguousNumberWords(normalized);
  const mathIntentPattern = /\b(sum|difference|product|quotient|minus|plus|add|subtract|times|multiply|divide|divided by|over|average|mean|largest|smallest|highest|lowest|difference)\b/;
  const maybeNumbers = /\b(?:zero|one|two|three|four|five|six|seven|eight|nine|ten|eleven|twelve|thirteen|fourteen|fifteen|sixteen|seventeen|eighteen|nineteen|twenty|thirty|forty|fifty|sixty|seventy|eighty|ninety|hundred|thousand|million|[0-9]+)\b/;
  if (ambiguousWords.length && mathIntentPattern.test(normalized) && maybeNumbers.test(normalized)) {
    const uniqueWords = [...new Set(ambiguousWords)];
    const clarified = normalizeAmbiguousNumberWords(normalized);
    if (clarified !== normalized) {
      return `Do you mean: "${clarified}"? If so, I can solve that math question now.`;
    }
    return `I heard words like ${uniqueWords.join(', ')} that may sound like numbers. Could you repeat the question more clearly so I can solve it correctly?`;
  }
  const numbers = extractNumbersFromText(normalized);
  const largestPattern = /\b(largest|biggest|highest|maximum|max|greatest)\b/;
  const smallestPattern = /\b(smallest|lowest|minimum|min|least)\b/;
  const ordinalPattern = /\b(second|third|fourth|fifth|sixth|seventh|eighth|ninth|tenth)\b/;
  const sortPattern = /\b(sort|ordered|ascending|descending|order from|arrange)\b/;
  const sumPattern = /\b(sum|total|add|plus|together)\b/;
  const differencePattern = /\b(difference|minus|subtract|less)\b/;
  const productPattern = /\b(product|times|multiply|multiplied by)\b/;
  const quotientPattern = /\b(quotient|divide|divided by|over)\b/;
  const averagePattern = /\b(average|mean|median)\b/;
  const countPattern = /\b(how many|count|number of)\b/;

  if (numbers.length > 1 && /(middle|median)/.test(normalized)) {
    const sorted = numbers.slice().sort((a, b) => a - b);
    if (sorted.length % 2 === 1) {
      return `The middle number is ${sorted[(sorted.length - 1) / 2]}.`;
    }
    const mid1 = sorted[sorted.length / 2 - 1];
    const mid2 = sorted[sorted.length / 2];
    return `The middle values are ${mid1} and ${mid2}. The median is ${(mid1 + mid2) / 2}.`;
  }

  if (numbers.length > 1 && ordinalPattern.test(normalized)) {
    const ordered = numbers.slice().sort((a, b) => a - b);
    const ordinalMatch = normalized.match(ordinalPattern);
    const rankMap = {
      second: 2,
      third: 3,
      fourth: 4,
      fifth: 5,
      sixth: 6,
      seventh: 7,
      eighth: 8,
      ninth: 9,
      tenth: 10
    };
    const rank = ordinalMatch ? rankMap[ordinalMatch[1]] : null;
    if (rank && numbers.length >= rank) {
      if (largestPattern.test(normalized)) {
        return `The ${ordinalMatch[1]} largest number is ${ordered[ordered.length - rank]}.`;
      }
      if (smallestPattern.test(normalized)) {
        return `The ${ordinalMatch[1]} smallest number is ${ordered[rank - 1]}.`;
      }
    }
  }

  if (numbers.length > 1 && sortPattern.test(normalized)) {
    const sorted = numbers.slice().sort((a, b) => a - b);
    if (/\b(descending|largest to smallest|highest to lowest|reverse)\b/.test(normalized)) {
      return `The numbers in descending order are ${sorted.slice().reverse().join(', ')}.`;
    }
    return `The numbers in ascending order are ${sorted.join(', ')}.`;
  }

  if (numbers.length > 1 && largestPattern.test(normalized)) {
    return `The largest number is ${Math.max(...numbers)}.`;
  }
  if (numbers.length > 1 && smallestPattern.test(normalized)) {
    return `The smallest number is ${Math.min(...numbers)}.`;
  }
  if (numbers.length > 0 && countPattern.test(normalized)) {
    return `There are ${numbers.length} numbers in the list.`;
  }
  if (numbers.length > 1 && averagePattern.test(normalized)) {
    const sum = numbers.reduce((acc, n) => acc + n, 0);
    const avg = sum / numbers.length;
    return `The average is ${Number(avg.toFixed(2))}.`;
  }
  if (numbers.length > 1 && sumPattern.test(normalized)) {
    const sum = numbers.reduce((acc, n) => acc + n, 0);
    return `The sum is ${sum}.`;
  }
  if (numbers.length > 1 && productPattern.test(normalized)) {
    const product = numbers.reduce((acc, n) => acc * n, 1);
    return `The product is ${product}.`;
  }
  if (numbers.length > 1 && quotientPattern.test(normalized)) {
    const valid = numbers.every((n) => typeof n === 'number');
    if (valid && numbers[1] !== 0) {
      return `The quotient is ${numbers[0] / numbers[1]}.`;
    }
    return null;
  }

  let mathText = cleaned
    .toLowerCase()
    .replace(/what\s+(is|does|s|was|are|were|will be)/g, ' ')
    .replace(/what's/g, ' ')
    .replace(/calculate|find|solve|evaluate|work out|tell me|answer|how much is|how many is/g, ' ')
    .replace(/plus|add/g, ' + ')
    .replace(/minus|subtract/g, ' - ')
    .replace(/times|multiplied by|x\b/g, ' * ')
    .replace(/divided by|over|\/|÷/g, ' / ')
    .replace(/equals?|=/g, ' = ')
    .replace(/[^a-z0-9+\-*/().\s=]/g, ' ')
    .replace(/\s+/g, ' ')
    .trim();

  mathText = replaceNumberWordsInMathExpression(mathText);
  const parsedExpressionCheck = parseNumberPhrase(mathText.split(/\s+/).map((t) => t.toLowerCase()));
  if (typeof parsedExpressionCheck === 'number' && !/[+\-*/]/.test(mathText)) {
    // If the user gave a single number phrase only, don't treat it as an expression.
    return null;
  }

  mathText = mathText
    .replace(/\bzero\b/g, '0')
    .replace(/\bone\b/g, '1')
    .replace(/\btwo\b/g, '2')
    .replace(/\bthree\b/g, '3')
    .replace(/\bfour\b/g, '4')
    .replace(/\bfive\b/g, '5')
    .replace(/\bsix\b/g, '6')
    .replace(/\bseven\b/g, '7')
    .replace(/\beight\b/g, '8')
    .replace(/\bnine\b/g, '9')
    .replace(/\bten\b/g, '10')
    .replace(/[^0-9+\-*/().\s=]/g, ' ')
    .replace(/\s+/g, ' ')
    .trim();

  if (!mathText) {
    return null;
  }

  const match = mathText.match(/(?:^|\s)([-+]?[0-9]+(?:\.[0-9]+)?(?:\s*[+\-*/]\s*[-+]?[0-9]+(?:\.[0-9]+)?)+)(?:\s*=|\s|$)/);
  const expression = match ? match[1].replace(/\s+/g, '') : null;
  if (!expression) {
    return null;
  }

  const safeExpression = expression.replace(/\s+/g, '');
  if (!/^[0-9.+\-*/()]+$/.test(safeExpression)) {
    return null;
  }

  try {
    const value = Function(`"use strict"; return (${safeExpression})`)();
    if (typeof value !== 'number' || !Number.isFinite(value)) {
      return null;
    }

    const rounded = Number.isInteger(value)
      ? String(value)
      : Number(value.toFixed(6)).toString();

    return `The answer is ${rounded}.`;
  } catch (error) {
    return null;
  }
}

function tryProfanityReply(lowerMessage) {
  const normalized = String(lowerMessage || '')
    .toLowerCase()
    .replace(/@/g, 'a')
    .replace(/\$/g, 's')
    .replace(/!/g, 'i')
    .replace(/0/g, 'o')
    .replace(/1/g, 'i')
    .replace(/3/g, 'e')
    .replace(/4/g, 'a')
    .replace(/5/g, 's')
    .replace(/7/g, 't')
    .replace(/[*+_.-]/g, '')
    .replace(/[^a-z\s]/g, ' ')
    .replace(/\s+/g, ' ')
    .trim();

  const tokens = normalized.split(/\s+/).filter(Boolean);
  const compact = tokens.join('');
  const profanityWords = [
    'fuck', 'fucking', 'fck', 'fk',
    'shit', 'shitty', 'sh1t', 'sht',
    'bitch', 'b1tch', 'b!tch',
    'bastard',
    'asshole', 'ass',
    'damn', 'dmn', 'd@mn',
    'crap', 'crappy',
    'idiot', 'stfu',
    'screw you', 'screwyou',
    'dick',
    'motherfucker', 'motherfucking',
    'piss', 'dammit', 'bullshit', 'bullsh1t'
  ];

  const hasProfanity = profanityWords.some((word) => {
    const cleanWord = word.replace(/\s+/g, '');

    if (word.includes(' ')) {
      return tokens.join(' ').includes(word) || compact.includes(cleanWord);
    }

    if (tokens.includes(cleanWord)) {
      return true;
    }

    if (cleanWord.length <= 4) {
      return false;
    }

    return compact.includes(cleanWord);
  });

  if (hasProfanity) {
    const responses = [
      `Those words are not right. In a place of learning and faith, we speak with care and respect. Please choose kinder words so we can grow wiser together.`,
      `I want to help you, but I cannot accept that kind of language. Let's choose gentle words and continue with kindness.`,
      `That kind of speech is not appropriate here. Please speak respectfully so we can keep learning together.`
    ];
    return responses[Math.floor(Math.random() * responses.length)];
  }
  return null;
}

function trySuggestionReply(lowerMessage) {
  const suggestionPatterns = [
    /\b(suggest|recommend|what can i do|things to do|ideas to do|what should i do|activity|activities)\b/, 
    /\b(learn|practice|hobby|project|reading|writing|drawing|exercise|game|craft|music|sport|dance|nature)\b/
  ];

  if (suggestionPatterns.some((pattern) => pattern.test(lowerMessage))) {
    return `Here are some good ideas for a Grade 6 student: read a fun story, write a short journal entry, draw or color a picture, learn a simple hobby like origami or journaling, practice a little math with a puzzle, try a science experiment, play a family game, or ask a parent to help with a craft or music activity. Keep your ideas kind, curious, and healthy.`;
  }

  return null;
}

function tryGeneralKnowledgeReply(lowerMessage) {
  const planetPattern = /\bwhat planet (are we living on|do we live on|is earth on|is our planet|is this planet)\b|\bwhere do we live\b/i;
  const identityPattern = /\bwho are you\b|\bwhat are you\b|\bwhat is your name\b/i;
  const basicPattern = /\bwhat is the capital of|\bwho is the president|\bwhat is gravity\b/i;

  if (planetPattern.test(lowerMessage)) {
    return `We are living on the planet Earth. It's our home in the solar system.`;
  }

  if (identityPattern.test(lowerMessage)) {
    return `I'm ${String(process.env.COMPANION_NAME || 'Habi Friend')}. I'm here to help you learn, feel supported, and have a friendly conversation.`;
  }

  const timePattern = /\bwhat year is it\b|\bwhat time is it\b|\bwhat day is it\b|\bwhat date is it\b/i;
  if (timePattern.test(lowerMessage)) {
    const now = new Date();
    const year = now.getFullYear();
    const hours = now.getHours();
    const minutes = now.getMinutes().toString().padStart(2, '0');
    const dateString = now.toLocaleDateString('en-US', { weekday: 'long', month: 'long', day: 'numeric', year: 'numeric' });

    if (/\bwhat year is it\b/i.test(lowerMessage)) {
      return `It is ${year}.`;
    }
    if (/\bwhat time is it\b/i.test(lowerMessage)) {
      return `Right now it is ${hours}:${minutes}.`;
    }
    return `Today is ${dateString}.`;
  }

  if (basicPattern.test(lowerMessage)) {
    return `That's a good question. I don't have every answer built in, but I'm here to help you learn and think about it. If you'd like, I can try to explain the idea or we can explore it together.`;
  }

  return null;
}

function tryEducationalReply(lowerMessage) {
  const educationPatterns = [
    /\b(explain|define|teach me|calculate|solve|study|learn|why does|how do|how can|what does|what are|show me|tell me about)\b/
  ];
  if (educationPatterns.some((pattern) => pattern.test(lowerMessage))) {
    return `That's a thoughtful question. Let us approach it with respectful words and an open heart as if we were in a place of prayer and learning.`;
  }
  return null;
}

function tryEmotionReply(lowerMessage) {
  if (/\b(sad|hurt|stress|tired|cry)\b/.test(lowerMessage)) {
    return `I'm really sorry things feel heavy right now. You don't have to go through it alone. If you want, tell me what happened and I'll stay with you through it.`;
  }
  if (/\b(happy|achieve|proud|win|success)\b/.test(lowerMessage)) {
    return `That is amazing, and I am genuinely proud of you. You worked for that moment, and you deserve to feel good about it. What part of it means the most to you?`;
  }
  if (/\b(anxious|afraid|worry|panic|overwhelm)\b/.test(lowerMessage)) {
    return `Thank you for trusting me with that. Let's slow it down together. What feels like the biggest thing on your mind right now?`;
  }
  if (/\b(lonely|alone|nobody)\b/.test(lowerMessage)) {
    return `I'm here with you right now. Feeling alone can hurt a lot, and your feelings matter. Do you want to talk about what has been making you feel this way?`;
  }
  return null;
}

async function synthesizeTextToAudio(text, voiceId) {
  const cleanedText = String(text || '').trim();
  const selectedVoiceId = String(voiceId || '').trim() || process.env.ELEVENLABS_VOICE_ID || PIPER_DEFAULT_VOICE_ID;

  if (!cleanedText) {
    throw new Error('Text is required for TTS');
  }

  const providerName = String(LOCAL_TTS_PROVIDER || '').toLowerCase();

  if (providerName === 'elevenlabs') {
    const apiKey = process.env.ELEVENLABS_API_KEY || '';
    if (apiKey) {
      const voiceKey = String(process.env.ELEVENLABS_VOICE_ID || selectedVoiceId || 'EXAVITQu4vr4xnSDxMaL');
      const response = await fetch(`https://api.elevenlabs.io/v1/text-to-speech/${encodeURIComponent(voiceKey)}`, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'audio/mpeg',
          'xi-api-key': apiKey
        },
        body: JSON.stringify({
          text: cleanedText,
          model_id: process.env.ELEVENLABS_MODEL || 'eleven_multilingual_v2',
          voice_settings: {
            stability: 0.5,
            similarity_boost: 0.8,
            style: 0.2,
            use_speaker_boost: true
          }
        })
      });

      if (!response.ok) {
        const errorText = await response.text();
        throw new Error(`ElevenLabs TTS failed (${response.status}): ${errorText}`);
      }

      const bytes = Buffer.from(await response.arrayBuffer());
      return {
        audioBuffer: bytes,
        contentType: 'audio/mpeg',
        provider: 'elevenlabs'
      };
    }
  }

  if (providerName === 'openai' || process.env.OPENAI_API_KEY) {
    const apiKey = process.env.OPENAI_API_KEY || '';
    if (apiKey) {
      try {
        const response = await fetch('https://api.openai.com/v1/audio/speech', {
          method: 'POST',
          headers: {
            'Content-Type': 'application/json',
            'Authorization': `Bearer ${apiKey}`
          },
          body: JSON.stringify({
            model: process.env.OPENAI_TTS_MODEL || 'gpt-4o-mini-tts',
            voice: process.env.OPENAI_REALTIME_VOICE || 'alloy',
            input: cleanedText
          })
        });

        if (!response.ok) {
          const errorText = await response.text();
          const apiError = new Error(`OpenAI TTS failed (${response.status}): ${errorText}`);
          apiError.status = response.status;
          if (isOpenAiQuotaError(apiError)) {
            disableOpenAiQuotaKey();
            console.warn('[synthesizeTextToAudio] OpenAI TTS quota exhausted; disabling the key and continuing to other providers.');
          } else {
            throw apiError;
          }
        } else {
          const bytes = Buffer.from(await response.arrayBuffer());
          return {
            audioBuffer: bytes,
            contentType: response.headers.get('content-type') || 'audio/mpeg',
            provider: 'openai'
          };
        }
      } catch (error) {
        if (isOpenAiQuotaError(error)) {
          disableOpenAiQuotaKey();
          console.warn('[synthesizeTextToAudio] OpenAI TTS quota exhausted; disabling the key and continuing to fallback providers.');
        } else {
          throw error;
        }
      }
    }
  }

  if (providerName === 'piper') {
    try {
      const upstreamResponse = await fetch(PIPER_TTS_URL, {
        method: 'POST',
        headers: {
          'Accept': 'audio/wav, audio/x-wav, audio/mpeg, application/octet-stream',
          'Content-Type': 'application/json'
        },
        body: JSON.stringify({
          text: cleanedText,
          voice: selectedVoiceId,
          speaker: selectedVoiceId,
          voiceId: selectedVoiceId,
          format: PIPER_OUTPUT_FORMAT
        })
      });

      if (!upstreamResponse.ok) {
        const errorText = await upstreamResponse.text();
        throw new Error(`Piper upstream ${upstreamResponse.status}: ${errorText}`);
      }

      const rawBuf = Buffer.from(await upstreamResponse.arrayBuffer());
      const contentType = upstreamResponse.headers.get('content-type') || (PIPER_OUTPUT_FORMAT === 'mp3' ? 'audio/mpeg' : 'audio/wav');
      const finalBuf = (contentType && contentType.indexOf('wav') !== -1) ? (ensureWavCompatible(rawBuf) || rawBuf) : rawBuf;

      return {
        audioBuffer: finalBuf,
        contentType,
        provider: 'piper'
      };
    } catch (error) {
      console.error('Synthesize audio failed for Piper:', error.message || error);
      if ((LOCAL_TTS_FALLBACK || '').toLowerCase() === 'windows-sapi') {
        return synthesizeWithWindowsSapi(cleanedText, selectedVoiceId);
      }
      throw error;
    }
  }

  if (providerName === 'windows-sapi') {
    return synthesizeWithWindowsSapi(cleanedText, selectedVoiceId);
  }

  throw new Error(`Unsupported LOCAL_TTS_PROVIDER: ${LOCAL_TTS_PROVIDER}`);
}

// ============ MIDDLEWARE ============

// Verify Firebase Auth Token
async function verifyToken(req, res, next) {
  const authHeader = req.headers.authorization;
  
  if (!authHeader) {
    return res.status(401).json({ error: 'Missing authorization header' });
  }
  
  const token = authHeader.split(' ')[1];
  
  if (!token) {
    return res.status(401).json({ error: 'Invalid authorization header format' });
  }

  // Local development fallback token format: Bearer local:<uid>
  if (token.startsWith('local:')) {
    req.user = { uid: token.slice('local:'.length) };
    return next();
  }
  
  try {
    const decodedToken = await admin.auth().verifyIdToken(token);
    req.user = decodedToken;
    next();
  } catch (error) {
    res.status(401).json({ error: 'Invalid or expired token' });
  }
}

function sanitizeUid(value) {
  if (!value) return '';
  let safe = String(value).trim().toLowerCase();
  const forbidden = ['@', '.', '#', '$', '[', ']'];
  forbidden.forEach(ch => {
    safe = safe.replace(new RegExp('\\' + ch, 'g'), '_');
  });
  safe = safe.replace(/ /g, '_');
  return safe;
}

function buildGeneratedDailyTasks(profile = {}) {
  const age = Number(profile.age || profile.studentAge || 11);
  const rawInterests = Array.isArray(profile.interests) ? profile.interests : [];
  const interests = rawInterests.map(item => String(item).trim().toLowerCase());
  const tasks = [
    'Read a short devotional and reflect for 5 minutes.',
    'Write down one thing you are grateful for today.',
    'Share an encouraging message with someone.',
    'Spend 10 minutes in prayer or quiet reflection.',
    'Read a Bible verse and think about how it applies to your day.'
  ];

  if (age >= 8 && age <= 15) {
    tasks.push('Draw or create something that represents your feelings today.');
    tasks.push('Spend 5 minutes doing your favorite hobby.');
  }

  if (age >= 12) {
    tasks.push('Write a short journal entry about your day.');
    tasks.push('Help someone with a task or problem.');
  }

  if (interests.some(value => ['games', 'playing', 'sports', 'music', 'art', 'books', 'reading', 'creative', 'drawing'].includes(value))) {
    if (interests.some(value => ['games', 'playing', 'sports'].includes(value))) {
      tasks.push('Play a game or sport you enjoy for 15 minutes.');
    }
    if (interests.some(value => ['reading', 'books', 'story'].includes(value))) {
      tasks.push('Read a story or article that interests you.');
    }
    if (interests.some(value => ['drawing', 'art', 'creative'].includes(value))) {
      tasks.push('Create something artistic or expressive.');
    }
    if (interests.some(value => ['music', 'singing'].includes(value))) {
      tasks.push('Listen to or play music that makes you happy.');
    }
  }

  const uniqueTasks = [];
  const seen = new Set();
  for (const task of tasks) {
    const normalized = task.trim();
    if (!normalized || seen.has(normalized)) continue;
    seen.add(normalized);
    uniqueTasks.push(normalized);
  }

  return uniqueTasks.slice(0, 5);
}

async function ensureDailyTasksForUser(uid) {
  const sanitizedUid = sanitizeUid(uid);
  if (!sanitizedUid) {
    return [];
  }

  const userHabitsRef = db.ref(`habits/${sanitizedUid}`);
  const habitsSnapshot = await userHabitsRef.once('value');

  if (habitsSnapshot.exists()) {
    const habits = [];
    habitsSnapshot.forEach(child => {
      const habit = child.val() || {};
      habits.push({
        id: child.key,
        ...habit,
        name: habit.name || habit.title || 'Daily task',
      });
    });
    if (habits.length > 0) {
      return habits;
    }
  }

  let profile = {};
  try {
    const profileSnapshot = await db.ref(`users/${sanitizedUid}`).once('value');
    if (profileSnapshot.exists()) {
      profile = profileSnapshot.val() || {};
    }
  } catch (error) {
    console.warn(`ensureDailyTasksForUser: failed to read profile for ${sanitizedUid}:`, error.message);
  }

  const dailyTasks = buildGeneratedDailyTasks(profile);
  if (!dailyTasks.length) {
    return [];
  }

  const createdHabits = [];
  for (let index = 0; index < dailyTasks.length; index++) {
    const taskText = dailyTasks[index];
    const habitId = `generated_${Date.now()}_${index}`;
    const habitRef = userHabitsRef.child(habitId);
    const payload = {
      name: taskText,
      description: 'Automatically generated daily task',
      frequency: 'daily',
      color: ['#4caf50', '#ff9800', '#2196f3', '#9c27b0', '#f44336'][index % 5],
      completed: 0,
      streak: 0,
      createdAt: new Date().toISOString(),
      generated: true,
    };
    await habitRef.set(payload);
    createdHabits.push({ id: habitId, ...payload });
  }

  return createdHabits;
}


async function resolveAuthenticatedIdentity(req, fallbackIdentity, fallbackName) {
  const authHeader = req.headers.authorization;

  if (!authHeader) {
    return {
      identity: fallbackIdentity,
      participantName: fallbackName,
      authenticated: false,
    };
  }

  const authParts = String(authHeader).trim().split(/\s+/);
  const token = authParts.length > 1 ? authParts[1] : authParts[0];

  if (!token) {
    return {
      identity: fallbackIdentity,
      participantName: fallbackName,
      authenticated: false,
      authError: 'Invalid authorization header format',
    };
  }

  if (token.startsWith('local:')) {
    const localUid = token.slice('local:'.length).trim();
    return {
      identity: String(localUid || fallbackIdentity).trim() || fallbackIdentity,
      participantName: fallbackName,
      authenticated: true,
    };
  }

  try {
    const decodedToken = await admin.auth().verifyIdToken(token);
    return {
      identity: String(decodedToken.uid || fallbackIdentity).trim() || fallbackIdentity,
      participantName: String(decodedToken.name || decodedToken.email || fallbackName).trim() || fallbackName,
      authenticated: true,
    };
  } catch (error) {
    return {
      identity: fallbackIdentity,
      participantName: fallbackName,
      authenticated: false,
      authError: error.message || 'Invalid or expired token',
    };
  }
}

// ============ HEALTH CHECK (NO AUTH REQUIRED) ============
app.get('/health', (req, res) => {
  res.json({ status: 'Server is running', timestamp: new Date().toISOString() });
});

// ============ AI COMPANION ENDPOINTS (NO AUTH REQUIRED FOR MVP) ============
app.post('/api/livekit/token', async (req, res) => {
  try {
    const livekitUrl = process.env.LIVEKIT_URL;
    const livekitApiKey = process.env.LIVEKIT_API_KEY;
    const livekitApiSecret = process.env.LIVEKIT_API_SECRET;
    const livekitHost = normalizeLiveKitHostForServerSdk(livekitUrl);

    if (!livekitHost || !livekitApiKey || !livekitApiSecret) {
      return res.status(500).json({ error: 'LiveKit server environment variables are not configured.' });
    }

    const roomName = String(req.body.roomName || DEFAULT_LIVEKIT_ROOM_NAME).trim() || DEFAULT_LIVEKIT_ROOM_NAME;
    const fallbackIdentity = String(req.body.identity || `guest_${Date.now()}`).trim() || `guest_${Date.now()}`;
    const fallbackParticipantName = String(req.body.name || 'Habi User').trim() || 'Habi User';
    const authIdentity = await resolveAuthenticatedIdentity(req, fallbackIdentity, fallbackParticipantName);

    if (authIdentity.authError) {
      return res.status(401).json({ error: authIdentity.authError });
    }

    const identity = authIdentity.identity;
    const participantName = authIdentity.participantName;
    const agentName = String(process.env.LIVEKIT_AGENT_NAME || DEFAULT_LIVEKIT_AGENT_NAME).trim() || DEFAULT_LIVEKIT_AGENT_NAME;

    console.log('[livekit-token] Token requested', {
      roomName,
      identity,
      participantName,
      authenticated: authIdentity.authenticated,
    });

    const token = new AccessToken(livekitApiKey, livekitApiSecret, {
      identity,
      name: participantName,
      ttl: '1h'
    });

    token.addGrant({
      roomJoin: true,
      room: roomName,
      canPublish: true,
      canSubscribe: true
    });

    console.log('[livekit-token] Token issued successfully', {
      roomName,
      identity,
      agentName,
      dispatchMode: 'manual-after-room-join'
    });

    return res.json({
      token: await token.toJwt(),
      url: livekitUrl,
      roomName,
      identity,
      name: participantName,
      agentName,
      dispatchRequired: true,
      dispatchEndpoint: '/api/livekit/dispatch'
    });
  } catch (error) {
    return res.status(500).json({ error: error.message });
  }
});

// ============ AI COMPANION ENDPOINTS (NO AUTH REQUIRED FOR MVP) ============
app.post('/api/livekit/dispatch', async (req, res) => {
  let livekitHost;
  let roomName;
  let identity;
  let agentName;

  try {
    const livekitUrl = process.env.LIVEKIT_URL;
    const livekitApiKey = process.env.LIVEKIT_API_KEY;
    const livekitApiSecret = process.env.LIVEKIT_API_SECRET;
    livekitHost = normalizeLiveKitHostForServerSdk(livekitUrl);

    if (!livekitHost || !livekitApiKey || !livekitApiSecret) {
      return res.status(500).json({ error: 'LiveKit server environment variables are not configured.' });
    }

    roomName = String(req.body.roomName || DEFAULT_LIVEKIT_ROOM_NAME).trim() || DEFAULT_LIVEKIT_ROOM_NAME;
    const fallbackIdentity = String(req.body.identity || '').trim();
    const authIdentity = await resolveAuthenticatedIdentity(req, fallbackIdentity, 'Habi User');

    if (authIdentity.authError) {
      return res.status(401).json({ error: authIdentity.authError });
    }

    identity = authIdentity.identity;
    agentName = String(req.body.agentName || process.env.LIVEKIT_AGENT_NAME || DEFAULT_LIVEKIT_AGENT_NAME).trim() || DEFAULT_LIVEKIT_AGENT_NAME;

    console.log('[livekit-dispatch] Dispatch requested', {
      roomName,
      identity,
      agentName,
      authenticated: authIdentity.authenticated,
    });

    const roomServiceClient = new RoomServiceClient(livekitHost, livekitApiKey, livekitApiSecret);
    const dispatchClient = new AgentDispatchClient(livekitHost, livekitApiKey, livekitApiSecret);

    let roomCreated = false;
    try {
      console.log('[livekit-dispatch] Ensuring room exists', { roomName });
      await roomServiceClient.createRoom({ name: roomName });
      roomCreated = true;
      console.log('[livekit-dispatch] Room created', { roomName });
    } catch (err) {
      if (String(err.message || '').toLowerCase().includes('already exists')) {
        console.log('[livekit-dispatch] Room already exists', { roomName });
      } else {
        console.warn('[livekit-dispatch] createRoom failed, continuing to dispatch path', {
          roomName,
          message: err.message
        });
      }
    }

    let existingDispatches = [];
    try {
      existingDispatches = await dispatchClient.listDispatch(roomName);
    } catch (err) {
      console.warn('[livekit-dispatch] listDispatch failed, retrying after room creation', {
        roomName,
        message: err.message
      });
      if (!roomCreated) {
        try {
          await roomServiceClient.createRoom({ name: roomName });
          roomCreated = true;
          console.log('[livekit-dispatch] Room created before retrying listDispatch', { roomName });
        } catch (createError) {
          console.warn('[livekit-dispatch] createRoom retry failed', {
            roomName,
            message: createError.message
          });
        }
      }
      existingDispatches = await dispatchClient.listDispatch(roomName);
    }
    const matchingDispatches = existingDispatches.filter((dispatch) => String(dispatch.agentName || '').trim() == agentName);
    const staleDispatches = existingDispatches.filter((dispatch) => String(dispatch.id || '').trim() !== '');

    if (matchingDispatches.length > 0 || staleDispatches.length > 0) {
      console.log('[livekit-dispatch] Cleaning up stale dispatch entries before reconnecting agent', {
        roomName,
        identity,
        agentName,
        existingDispatchCount: existingDispatches.length,
        matchingDispatchCount: matchingDispatches.length,
        staleDispatchCount: staleDispatches.length,
      });

      for (const dispatch of staleDispatches) {
        const dispatchId = String(dispatch.id || '').trim();
        if (!dispatchId) continue;

        try {
          await dispatchClient.deleteDispatch(dispatchId, roomName);
          console.log('[livekit-dispatch] Deleted stale dispatch', { roomName, dispatchId, agentName: dispatch.agentName || agentName });
        } catch (deleteErr) {
          console.warn('[livekit-dispatch] Failed to delete stale dispatch', {
            roomName,
            dispatchId,
            agentName: dispatch.agentName || agentName,
            message: deleteErr.message,
          });
        }
      }
    }

    await dispatchClient.createDispatch(roomName, agentName, {
      metadata: JSON.stringify({
        requestedBy: 'api/livekit/dispatch',
        participantIdentity: identity,
        createdAt: new Date().toISOString()
      })
    });
    console.log('[livekit-dispatch] Agent dispatch created', { roomName, identity, agentName });

    return res.json({ ok: true, roomName, identity, agentName });
  } catch (error) {
    console.error('[livekit-dispatch] Dispatch failed', {
      message: error.message,
      stack: error.stack,
      normalizedLivekitHost: livekitHost,
      agentName: agentName || 'unknown',
      roomName: roomName || 'unknown',
      identity: identity || 'unknown'
    });
    return res.status(500).json({ error: 'Failed to dispatch the LiveKit agent.', details: error.message });
  }
});

// ============ AI COMPANION ENDPOINTS (NO AUTH REQUIRED FOR MVP) ============
app.post('/api/companion/chat', async (req, res) => {
  try {
    const { message, companionName } = req.body;
    const cleanedMessage = String(message || '').trim();
    const name = String(companionName || 'Habi Friend').trim() || 'Habi Friend';

    if (!cleanedMessage) {
      return res.status(400).json({ error: 'message is required' });
    }

    const reply = await buildCompanionReply(cleanedMessage, name);

    res.json({
      reply,
      companionName: name,
      mock: true,
      timestamp: new Date().toISOString()
    });
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});

app.post('/api/companion/voice', async (req, res) => {
  try {
    const { audioBase64, contentType, voiceId, companionName } = req.body || {};
    if (!audioBase64) {
      return res.status(400).json({ error: 'audioBase64 is required' });
    }

    const buffer = Buffer.from(audioBase64, 'base64');
    console.log('[companion/voice] received audio bytes:', buffer.length, 'contentType:', contentType);
    const sttResult = await transcribeAudio(buffer, contentType || 'audio/wav');
    const transcript = String(sttResult.transcript || '').trim();
    console.log('[companion/voice] STT result:', { transcript, provider: sttResult.provider });
    const replyText = await buildCompanionReply(transcript, String(companionName || 'Habi Friend').trim() || 'Habi Friend');
    const synthesized = await synthesizeTextToAudio(replyText, String(voiceId || '').trim());

    return res.json({
      transcript,
      reply: replyText,
      audioBase64: synthesized.audioBuffer.toString('base64'),
      audioContentType: synthesized.contentType,
      provider: {
        stt: sttResult.provider,
        tts: synthesized.provider
      },
      raw: sttResult.raw || null
    });
  } catch (error) {
    console.error('[companion/voice] error:', error.message || error);
    return res.status(500).json({ error: error.message || 'Companion voice processing failed' });
  }
});

app.post('/api/companion/tts', async (req, res) => {
  try {
    const { text, voiceId } = req.body || {};
    const cleanedText = String(text || '').trim();
    const selectedVoiceId = String(voiceId || '').trim() || process.env.ELEVENLABS_VOICE_ID || PIPER_DEFAULT_VOICE_ID;

    if (!cleanedText) {
      return res.status(400).json({ error: 'text is required' });
    }

    let synthesized = null;
    const providerName = String(LOCAL_TTS_PROVIDER || '').toLowerCase();

    try {
      if (providerName === 'elevenlabs' || process.env.ELEVENLABS_API_KEY) {
        synthesized = await synthesizeTextToAudio(cleanedText, selectedVoiceId);
      } else if (providerName === 'openai' || process.env.OPENAI_API_KEY) {
        synthesized = await synthesizeTextToAudio(cleanedText, selectedVoiceId);
      } else if (providerName === 'piper') {
        const upstreamResponse = await fetch(PIPER_TTS_URL, {
          method: 'POST',
          headers: {
            'Accept': 'audio/wav, audio/x-wav, audio/mpeg, application/octet-stream',
            'Content-Type': 'application/json'
          },
          body: JSON.stringify({
            text: cleanedText,
            voice: selectedVoiceId,
            speaker: selectedVoiceId,
            voiceId: selectedVoiceId,
            format: PIPER_OUTPUT_FORMAT
          })
        });

        if (!upstreamResponse.ok) {
          const errorText = await upstreamResponse.text();
          throw new Error(`Piper upstream ${upstreamResponse.status}: ${errorText}`);
        }

        const rawBuf = Buffer.from(await upstreamResponse.arrayBuffer());
        const contentType = upstreamResponse.headers.get('content-type') || (PIPER_OUTPUT_FORMAT === 'mp3' ? 'audio/mpeg' : 'audio/wav');
        const finalBuf = (contentType && contentType.indexOf('wav') !== -1) ? (ensureWavCompatible(rawBuf) || rawBuf) : rawBuf;
        synthesized = {
          audioBuffer: finalBuf,
          contentType,
          provider: 'piper'
        };
      } else if (providerName === 'windows-sapi') {
        synthesized = synthesizeWithWindowsSapi(cleanedText, selectedVoiceId);
      } else {
        synthesized = await synthesizeTextToAudio(cleanedText, selectedVoiceId);
      }
    } catch (error) {
      console.error('Companion TTS provider error:', error);
      if (providerName === 'piper' && (LOCAL_TTS_FALLBACK || '').toLowerCase() === 'windows-sapi') {
        synthesized = synthesizeWithWindowsSapi(cleanedText, selectedVoiceId);
      } else if ((LOCAL_TTS_FALLBACK || '').toLowerCase() === 'openai' && process.env.OPENAI_API_KEY) {
        synthesized = await synthesizeTextToAudio(cleanedText, selectedVoiceId);
      } else {
        throw error;
      }
    }

    res.setHeader('Content-Type', synthesized.contentType);
    res.setHeader('Content-Length', synthesized.audioBuffer.length);
    res.setHeader('X-TTS-Provider', synthesized.provider);
    res.send(synthesized.audioBuffer);
  } catch (error) {
    console.error('Companion TTS error:', error);
    res.status(500).json({ error: 'Failed to synthesize speech with local TTS service', details: error.message });
  }
});

// Debug endpoint: synthesize text and return WAV header metadata (and optional base64 audio)
app.post('/api/companion/tts-metadata', async (req, res) => {
  try {
    const { text, voiceId, includeAudio } = req.body || {};
    const cleanedText = String(text || '').trim();
    if (!cleanedText) return res.status(400).json({ error: 'text is required' });

    const synthesized = await synthesizeTextToAudio(cleanedText, String(voiceId || '').trim());
    const buf = synthesized.audioBuffer;
    const contentType = synthesized.contentType || 'audio/wav';
    const header = (contentType.indexOf('wav') !== -1) ? parseWavHeader(buf) : null;

    const result = {
      provider: synthesized.provider,
      contentType,
      byteLength: buf.length,
      header
    };

    if (includeAudio) {
      result.audioBase64 = buf.toString('base64');
    }

    return res.json(result);
  } catch (e) {
    console.error('[tts-metadata] error:', e.message || e);
    return res.status(500).json({ error: e.message || 'tts-metadata failed' });
  }
});

// ============ Companion STT (accepts base64 audio) ============
app.post('/api/companion/stt', async (req, res) => {
  try {
    const { audioBase64, contentType } = req.body || {};
    if (!audioBase64) {
      return res.status(400).json({ error: 'audioBase64 is required' });
    }

    const buffer = Buffer.from(audioBase64, 'base64');
    console.log('[companion/stt] received audio bytes:', buffer.length, 'contentType:', contentType);

    // If Deepgram is configured, forward the raw audio to Deepgram's REST API
    const deepgramKey = process.env.DEEPGRAM_API_KEY;
    const deepgramModel = process.env.DEEPGRAM_MODEL || 'nova-2-general';
    const deepgramLang = process.env.DEEPGRAM_LANGUAGE || '';
    const languageQuery = deepgramLang && deepgramLang.toLowerCase() !== 'auto' ? `&language=${encodeURIComponent(deepgramLang)}` : '';

    if (deepgramKey) {
      const dgUrl = `https://api.deepgram.com/v1/listen?model=${encodeURIComponent(deepgramModel)}${languageQuery}`;

      const dgResp = await fetch(dgUrl, {
        method: 'POST',
        headers: {
          'Content-Type': contentType || 'audio/wav',
          'Authorization': `Token ${deepgramKey}`
        },
        body: buffer
      });

      if (!dgResp.ok) {
        const txt = await dgResp.text();
        console.error('Deepgram STT error', dgResp.status, txt);
        return res.status(502).json({ error: 'Deepgram STT failed', status: dgResp.status, details: txt });
      }

      const dgJson = await dgResp.json();
      // Deepgram response shape: results.channels[0].alternatives[0].transcript
      let transcript = '';
      try {
        transcript = dgJson?.results?.channels?.[0]?.alternatives?.[0]?.transcript || '';
      } catch (e) {
        transcript = '';
      }

      // Provide both `transcript` and `text` for compatibility with clients
      return res.json({ transcript, text: transcript, raw: dgJson, provider: 'deepgram' });
    }

    // No STT provider configured
    return res.status(501).json({ error: 'No STT provider configured on server (set DEEPGRAM_API_KEY)' });
  } catch (error) {
    console.error('Companion STT error:', error);
    res.status(500).json({ error: error.message });
  }
});

// ============ USER ENDPOINTS ============

// Create/Update User (AUTHENTICATED)
app.post('/api/users', verifyToken, async (req, res) => {
  try {
    const { uid, email, displayName, pronouns, age, interests } = req.body;
    const authUid = req.user.uid;
    
    // Verify uid matches authenticated user
    if (uid !== authUid) {
      return res.status(403).json({ error: 'Cannot modify other users profiles' });
    }
    
    if (!uid || !email) {
      return res.status(400).json({ error: 'uid and email are required' });
    }

    const userRef = db.ref(`users/${uid}`);
    await userRef.set({
      email,
      displayName: displayName || '',
      pronouns: pronouns || '',
      age: age || null,
      interests: interests || [],
      createdAt: new Date().toISOString(),
      updatedAt: new Date().toISOString()
    });

    res.status(201).json({ message: 'User created successfully', uid });
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});

// Get User Profile (AUTHENTICATED)
app.get('/api/users/:uid', verifyToken, async (req, res) => {
  try {
    const { uid } = req.params;
    const authUid = req.user.uid;
    
    // Verify uid matches authenticated user
    if (uid !== authUid) {
      return res.status(403).json({ error: 'Cannot access other users profiles' });
    }
    
    const userRef = db.ref(`users/${uid}`);
    const snapshot = await userRef.once('value');
    
    if (!snapshot.exists()) {
      return res.status(404).json({ error: 'User not found' });
    }

    res.json(snapshot.val());
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});

// Update User Profile (AUTHENTICATED)
app.patch('/api/users/:uid', verifyToken, async (req, res) => {
  try {
    const { uid } = req.params;
    const authUid = req.user.uid;
    
    // Verify uid matches authenticated user
    if (uid !== authUid) {
      return res.status(403).json({ error: 'Cannot modify other users profiles' });
    }
    
    const updates = req.body;

    const userRef = db.ref(`users/${uid}`);
    await userRef.update({
      ...updates,
      updatedAt: new Date().toISOString()
    });

    res.json({ message: 'User updated successfully', uid });
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});

// ============ MOOD TRACKING ENDPOINTS ============

// Log Mood Entry (AUTHENTICATED)
app.post('/api/moods', verifyToken, async (req, res) => {
  try {
    const { uid, mood, intensity, notes } = req.body;
    const authUid = req.user.uid;
    
    // Verify uid matches authenticated user
    if (uid !== authUid) {
      return res.status(403).json({ error: 'Cannot log moods for other users' });
    }
    
    if (!uid || !mood) {
      return res.status(400).json({ error: 'uid and mood are required' });
    }

    const timestamp = new Date().toISOString();
    const moodRef = db.ref(`moods/${uid}`).push();
    
    await moodRef.set({
      mood,
      intensity: intensity || 5,
      notes: notes || '',
      timestamp
    });

    res.status(201).json({ message: 'Mood logged successfully', moodId: moodRef.key });
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});

// Get User's Mood History (AUTHENTICATED)
app.get('/api/moods/:uid', verifyToken, async (req, res) => {
  try {
    const { uid } = req.params;
    const authUid = req.user.uid;
    
    // Verify uid matches authenticated user
    if (uid !== authUid) {
      return res.status(403).json({ error: 'Cannot access other users moods' });
    }
    
    const moodRef = db.ref(`moods/${uid}`).orderByChild('timestamp');
    const snapshot = await moodRef.once('value');
    
    if (!snapshot.exists()) {
      return res.json([]);
    }

    const moods = [];
    snapshot.forEach(child => {
      moods.push({ id: child.key, ...child.val() });
    });

    res.json(moods.reverse());
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});

// ============ JOURNAL ENTRY ENDPOINTS ============

// Create Journal Entry (AUTHENTICATED)
app.post('/api/journal', verifyToken, async (req, res) => {
  try {
    const { uid, title, content, mood } = req.body;
    const authUid = req.user.uid;
    
    // Verify uid matches authenticated user
    if (uid !== authUid) {
      return res.status(403).json({ error: 'Cannot create entries for other users' });
    }
    
    if (!uid || !title || !content) {
      return res.status(400).json({ error: 'uid, title, and content are required' });
    }

    const timestamp = new Date().toISOString();
    const entryRef = db.ref(`journal/${uid}`).push();
    
    await entryRef.set({
      title,
      content,
      mood: mood || '',
      timestamp,
      updatedAt: timestamp
    });

    res.status(201).json({ message: 'Journal entry created', entryId: entryRef.key });
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});

// Get User's Journal Entries (AUTHENTICATED)
app.get('/api/journal/:uid', verifyToken, async (req, res) => {
  try {
    const { uid } = req.params;
    const authUid = req.user.uid;
    
    // Verify uid matches authenticated user
    if (uid !== authUid) {
      return res.status(403).json({ error: 'Cannot access other users journal' });
    }
    
    const journalRef = db.ref(`journal/${uid}`);
    const snapshot = await journalRef.once('value');
    
    if (!snapshot.exists()) {
      return res.json([]);
    }

    const entries = [];
    snapshot.forEach(child => {
      entries.push({ id: child.key, ...child.val() });
    });

    res.json(entries.reverse());
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});

// Get Single Journal Entry (AUTHENTICATED)
app.get('/api/journal/:uid/:entryId', verifyToken, async (req, res) => {
  try {
    const { uid, entryId } = req.params;
    const authUid = req.user.uid;
    
    // Verify uid matches authenticated user
    if (uid !== authUid) {
      return res.status(403).json({ error: 'Cannot access other users entries' });
    }
    
    const entryRef = db.ref(`journal/${uid}/${entryId}`);
    const snapshot = await entryRef.once('value');
    
    if (!snapshot.exists()) {
      return res.status(404).json({ error: 'Entry not found' });
    }

    res.json({ id: entryId, ...snapshot.val() });
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});

// Update Journal Entry (AUTHENTICATED)
app.patch('/api/journal/:uid/:entryId', verifyToken, async (req, res) => {
  try {
    const { uid, entryId } = req.params;
    const authUid = req.user.uid;
    
    // Verify uid matches authenticated user
    if (uid !== authUid) {
      return res.status(403).json({ error: 'Cannot modify other users entries' });
    }
    
    const { title, content, mood } = req.body;

    const entryRef = db.ref(`journal/${uid}/${entryId}`);
    await entryRef.update({
      title,
      content,
      mood,
      updatedAt: new Date().toISOString()
    });

    res.json({ message: 'Entry updated successfully' });
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});

// Delete Journal Entry (AUTHENTICATED)
app.delete('/api/journal/:uid/:entryId', verifyToken, async (req, res) => {
  try {
    const { uid, entryId } = req.params;
    const authUid = req.user.uid;
    
    // Verify uid matches authenticated user
    if (uid !== authUid) {
      return res.status(403).json({ error: 'Cannot delete other users entries' });
    }
    
    const entryRef = db.ref(`journal/${uid}/${entryId}`);
    
    await entryRef.remove();
    res.json({ message: 'Entry deleted successfully' });
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});

// ============ HABIT TRACKING ENDPOINTS ============

// Create Habit (AUTHENTICATED)
app.post('/api/habits', verifyToken, async (req, res) => {
  try {
    const { uid, name, description, frequency, color } = req.body;
    const authUid = req.user.uid;
    
    // Sanitize both for comparison
    const sanitizedUid = sanitizeUid(uid);
    const sanitizedAuthUid = sanitizeUid(authUid);
    
    // Verify uid matches authenticated user
    if (sanitizedUid !== sanitizedAuthUid) {
      return res.status(403).json({ error: 'Cannot create habits for other users' });
    }
    
    if (!uid || !name) {
      return res.status(400).json({ error: 'uid and name are required' });
    }

    const timestamp = new Date().toISOString();
    const habitRef = db.ref(`habits/${sanitizedUid}`).push();
    
    await habitRef.set({
      name,
      description: description || '',
      frequency: frequency || 'daily',
      color: color || '#3498db',
      completed: 0,
      streak: 0,
      createdAt: timestamp
    });

    res.status(201).json({ message: 'Habit created', habitId: habitRef.key });
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});

// Get User's Habits (AUTHENTICATED)
app.get('/api/habits/:uid', verifyToken, async (req, res) => {
  try {
    const { uid } = req.params;
    const authUid = req.user.uid;
    
    // Sanitize both for comparison (handles emails with @ and . characters)
    const sanitizedUid = sanitizeUid(uid);
    const sanitizedAuthUid = sanitizeUid(authUid);
    
    console.log(`habits GET: uid=${uid}, authUid=${authUid}, sanitized: uid=${sanitizedUid}, authUid=${sanitizedAuthUid}`);
    
    // Verify uid matches authenticated user
    if (sanitizedUid !== sanitizedAuthUid) {
      return res.status(403).json({ error: 'Cannot access other users habits' });
    }

    const habits = await ensureDailyTasksForUser(sanitizedUid);
    res.json(habits);
  } catch (error) {
    console.error('GET /api/habits error:', error);
    res.status(500).json({ error: error.message });
  }
});

// Mark Habit as Completed (AUTHENTICATED)
app.post('/api/habits/:uid/:habitId/complete', verifyToken, async (req, res) => {
  try {
    const { uid, habitId } = req.params;
    const authUid = req.user.uid;
    
    // Sanitize both for comparison
    const sanitizedUid = sanitizeUid(uid);
    const sanitizedAuthUid = sanitizeUid(authUid);
    
    // Verify uid matches authenticated user
    if (sanitizedUid !== sanitizedAuthUid) {
      return res.status(403).json({ error: 'Cannot complete other users habits' });
    }
    
    const habitRef = db.ref(`habits/${sanitizedUid}/${habitId}`);
    
    const snapshot = await habitRef.once('value');
    if (!snapshot.exists()) {
      return res.status(404).json({ error: 'Habit not found' });
    }

    const habit = snapshot.val();
    await habitRef.update({
      completed: habit.completed + 1,
      streak: habit.streak + 1,
      lastCompleted: new Date().toISOString()
    });

    res.json({ message: 'Habit marked as completed' });
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});

// Delete Habit (AUTHENTICATED)
app.delete('/api/habits/:uid/:habitId', verifyToken, async (req, res) => {
  try {
    const { uid, habitId } = req.params;
    const authUid = req.user.uid;
    
    // Sanitize both for comparison
    const sanitizedUid = sanitizeUid(uid);
    const sanitizedAuthUid = sanitizeUid(authUid);
    
    // Verify uid matches authenticated user
    if (sanitizedUid !== sanitizedAuthUid) {
      return res.status(403).json({ error: 'Cannot delete other users habits' });
    }
    
    const habitRef = db.ref(`habits/${sanitizedUid}/${habitId}`);
    
    await habitRef.remove();
    res.json({ message: 'Habit deleted' });
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});

// ============ PERSONALITY TEST ENDPOINTS ============

// Save Personality Test Results (AUTHENTICATED)
app.post('/api/personality-tests', verifyToken, async (req, res) => {
  try {
    const { uid, answers, personality_type, timestamp } = req.body;
    const authUid = req.user.uid;
    
    // Allow both authenticated users and guests
    if (uid !== authUid && !uid.startsWith('guest_')) {
      return res.status(403).json({ error: 'Cannot save other users test results' });
    }
    
    if (!uid || !answers) {
      return res.status(400).json({ error: 'uid and answers are required' });
    }

    const testsRef = db.ref(`personality_tests/${uid}`);
    const testId = Date.now().toString();
    
    await testsRef.child(testId).set({
      answers,
      personality_type: personality_type || 'unknown',
      timestamp: timestamp || Date.now(),
      createdAt: new Date().toISOString()
    });

    res.status(201).json({ message: 'Test results saved successfully', testId });
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});

// Get Personality Test Results (AUTHENTICATED)
app.get('/api/personality-tests/:uid', verifyToken, async (req, res) => {
  try {
    const { uid } = req.params;
    const authUid = req.user.uid;
    
    // Allow users to view their own results or guests can view guest results
    if (uid !== authUid && !uid.startsWith('guest_')) {
      return res.status(403).json({ error: 'Cannot access other users test results' });
    }
    
    const testsRef = db.ref(`personality_tests/${uid}`);
    const snapshot = await testsRef.once('value');
    
    if (!snapshot.exists()) {
      return res.json({ results: [] });
    }

    const results = [];
    snapshot.forEach(child => {
      results.push({ id: child.key, ...child.val() });
    });

    res.json({ results });
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});

// Start Server
const server = app.listen(PORT, () => {
  console.log(`🚀 Server running on http://localhost:${PORT}`);
  console.log(`📝 Health check: http://localhost:${PORT}/health`);
});

let startupErrorHandled = false;
function handleStartupError(error) {
  if (startupErrorHandled) return;
  startupErrorHandled = true;
  if (error && error.code === 'EADDRINUSE') {
    console.error(`❌ Port ${PORT} is already in use. The Habi backend may already be running; use http://localhost:${PORT}/health to check it.`);
  } else {
    console.error('❌ Server startup error:', error);
  }
  process.exitCode = 1;
  if (server.listening) {
    server.close(() => process.exit(1));
  } else {
    process.exit(1);
  }
}

server.on('error', handleStartupError);

const geminiWss = new WebSocketServer({ server, path: '/ws/gemini' });
geminiWss.on('error', handleStartupError);

geminiWss.on('connection', (client) => {
  console.log('[gemini] Godot client connected');
  const apiKey = String(process.env.GEMINI_API_KEY || '').trim();
  if (!apiKey) {
    client.send(JSON.stringify({ type: 'error', message: 'GEMINI_API_KEY is not configured on the backend.' }));
    client.close(1011, 'Gemini is not configured');
    return;
  }

  const upstreamUrl = `wss://generativelanguage.googleapis.com/ws/google.ai.generativelanguage.v1beta.GenerativeService.BidiGenerateContent?key=${encodeURIComponent(apiKey)}`;
  const upstream = new WebSocket(upstreamUrl);
  let upstreamReady = false;

  upstream.on('open', () => {
    console.log('[gemini] upstream connected; sending session setup');
    upstream.send(JSON.stringify({
      setup: {
        model: GEMINI_LIVE_MODEL,
        generationConfig: {
          responseModalities: ['AUDIO'],
          speechConfig: {
            voiceConfig: {
              prebuiltVoiceConfig: { voiceName: GEMINI_VOICE_NAME }
            }
          },
          thinkingConfig: { thinkingBudget: 0 }
        },
        realtimeInputConfig: {
          automaticActivityDetection: {
            prefixPaddingMs: 120,
            silenceDurationMs: 500
          }
        },
        systemInstruction: { parts: [{ text: GEMINI_SYSTEM_INSTRUCTION }] }
      }
    }));
    upstreamReady = true;
  });

  upstream.on('message', (raw) => {
    try {
      const message = JSON.parse(raw.toString());
      if (message.setupComplete) {
        console.log('[gemini] session setup accepted');
      }
      const parts = message?.serverContent?.modelTurn?.parts || [];
      for (const part of parts) {
        if (part.inlineData?.data) {
          client.send(JSON.stringify({ type: 'audio', data: part.inlineData.data }));
        }
        if (part.text) {
          client.send(JSON.stringify({ type: 'text', text: part.text }));
        }
      }
      if (message.serverContent?.inputTranscription?.text) {
        client.send(JSON.stringify({ type: 'input_text', text: message.serverContent.inputTranscription.text }));
      }
      if (message.serverContent?.outputTranscription?.text) {
        client.send(JSON.stringify({ type: 'text', text: message.serverContent.outputTranscription.text }));
      }
      if (message.error) {
        console.error('[gemini] upstream error:', message.error.message || message.error);
        client.send(JSON.stringify({ type: 'error', message: message.error.message || 'Gemini Live error' }));
      }
    } catch (error) {
      client.send(JSON.stringify({ type: 'error', message: 'Invalid Gemini response' }));
    }
  });

  upstream.on('error', (error) => {
    console.error('[gemini] upstream connection error:', error.message || error);
    client.send(JSON.stringify({ type: 'error', message: error.message || 'Gemini connection failed' }));
  });

  upstream.on('close', (code, reason) => {
    console.log('[gemini] upstream closed:', code, reason.toString());
  });

  client.on('message', (raw, isBinary) => {
    if (!upstreamReady || upstream.readyState !== WebSocket.OPEN) return;
    if (isBinary) {
      upstream.send(JSON.stringify({
        realtimeInput: {
          mediaChunks: [{ mimeType: 'audio/pcm;rate=16000', data: Buffer.from(raw).toString('base64') }]
        }
      }));
      return;
    }
    try {
      const message = JSON.parse(raw.toString());
      if (message.type === 'end_turn') {
        upstream.send(JSON.stringify({ realtimeInput: { audioStreamEnd: true } }));
      }
    } catch (error) {
      client.send(JSON.stringify({ type: 'error', message: 'Invalid voice client message' }));
    }
  });

  client.on('close', () => {
    console.log('[gemini] Godot client disconnected');
    if (upstream.readyState === WebSocket.OPEN || upstream.readyState === WebSocket.CONNECTING) upstream.close();
  });
});

