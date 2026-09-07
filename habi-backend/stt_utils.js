import OpenAI from 'openai';

export async function createOpenAIWhisperTranscriptionRequest(buffer, contentType, apiKey) {
  const form = new FormData();
  const mimeType = contentType || 'audio/wav';
  const blob = new Blob([buffer], { type: mimeType });

  form.append('file', blob, 'audio.wav');
  form.append('model', 'whisper-1');

  return {
    url: 'https://api.openai.com/v1/audio/transcriptions',
    method: 'POST',
    headers: {
      Authorization: `Bearer ${apiKey}`
    },
    body: form
  };
}

export async function transcribeWithOpenAIWhisper(buffer, contentType, apiKey, language = '') {
  if (!apiKey) {
    throw new Error('OPENAI_API_KEY is not configured');
  }

  const client = new OpenAI({ apiKey });
  const file = new File([buffer], 'audio.wav', { type: contentType || 'audio/wav' });

  const request = {
    file,
    model: 'whisper-1',
    response_format: 'json'
  };

  if (language && language.trim() !== '') {
    request.language = String(language).trim();
  }

  const transcription = await client.audio.transcriptions.create(request);
  return String(transcription?.text || '').trim();
}
