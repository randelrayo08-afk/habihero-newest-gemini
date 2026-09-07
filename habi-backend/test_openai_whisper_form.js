import test from 'node:test';
import assert from 'node:assert/strict';
import { createOpenAIWhisperTranscriptionRequest } from './stt_utils.js';

test('creates an OpenAI Whisper multipart request for audio uploads', async () => {
  const buffer = Buffer.from('RIFF....WAVE', 'utf8');
  const request = await createOpenAIWhisperTranscriptionRequest(buffer, 'audio/wav', 'test-key');

  assert.equal(request.url, 'https://api.openai.com/v1/audio/transcriptions');
  assert.equal(request.headers.Authorization, 'Bearer test-key');
  assert.equal(typeof request.body.append, 'function');
  assert.ok(request.body);
});
