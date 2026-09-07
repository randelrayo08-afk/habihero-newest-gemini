import dotenv from 'dotenv';
import { fileURLToPath } from 'node:url';
import path from 'node:path';
import { ServerOptions, cli, defineAgent, metrics, voice, initializeLogger } from '@livekit/agents';
import * as deepgram from '@livekit/agents-plugin-deepgram';
import * as elevenlabs from '@livekit/agents-plugin-elevenlabs';
import * as openai from '@livekit/agents-plugin-openai';
import * as silero from '@livekit/agents-plugin-silero';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);
initializeLogger({ pretty: true, level: 'debug' });
dotenv.config({ path: path.join(__dirname, '.env') });

const AGENT_INSTRUCTIONS = `
You are Habi Friend, a warm, emotionally supportive AI voice companion inside the Habi app.

Your role:
- speak like a kind, calm, emotionally intelligent friend
- help users talk through stress, sadness, anxiety, loneliness, burnout, habits, goals, and daily wins
- encourage small healthy next steps
- keep responses natural, spoken, and concise
- avoid sounding robotic or overly clinical
- never use markdown, bullet points, or special formatting in spoken replies
- if the user sounds overwhelmed, respond gently and slow things down
- if the user speaks in a language other than English, reply naturally in that same language
- if the user shares something positive, celebrate with them sincerely
- do not claim to be a licensed therapist
- if the user mentions immediate danger or self-harm, encourage contacting local emergency services or a trusted person right away

Style:
- short voice-friendly sentences
- empathetic and supportive
- language-appropriate and conversational
- gentle encouragement
- ignore room echo, microphone feedback, and your own spoken audio; only answer when a real user is speaking
- if the system hears your own voice, treat it as noise and stay silent until the user speaks again
`.trim();

function readEnv(name, fallback = '') {
	return String(process.env[name] || fallback).trim();
}

function requireEnv(name, helpText = '') {
	const value = readEnv(name);
	if (!value) {
		const suffix = helpText ? ` ${helpText}` : '';
		throw new Error(`Missing required environment variable ${name}.${suffix}`);
	}
	return value;
}

const agentName = readEnv('LIVEKIT_AGENT_NAME', 'habi-friend') || 'habi-friend';
const realtimeModel = readEnv('OPENAI_REALTIME_MODEL', 'gpt-realtime');
const chatProvider = readEnv('LLM_PROVIDER', 'groq').toLowerCase();
const chatModel = readEnv(
	'LLM_MODEL',
	readEnv(
		'OPENROUTER_MODEL',
		readEnv(
			'DEEPSEEK_MODEL',
			readEnv('GROQ_MODEL', readEnv('OPENAI_MODEL', readEnv('OPENAI_CHAT_MODEL', 'openai/gpt-4o-mini')))
		)
	)
);
const ttsModel = readEnv('OPENAI_TTS_MODEL', 'gpt-4o-mini-tts');
const voiceName = readEnv('OPENAI_REALTIME_VOICE', readEnv('OPENAI_VOICE', 'alloy'));
const elevenLabsApiKey = readEnv('ELEVENLABS_API_KEY', readEnv('ELEVEN_API_KEY'));
const elevenLabsVoiceId = readEnv('ELEVENLABS_VOICE_ID', 'EXAVITQu4vr4xnSDxMaL');
const elevenLabsModel = readEnv('ELEVENLABS_MODEL', 'eleven_flash_v2_5');
const deepgramApiKey = readEnv('DEEPGRAM_API_KEY');
const deepgramModel = readEnv('DEEPGRAM_MODEL', 'nova-2-general');
const deepgramLanguage = readEnv('DEEPGRAM_LANGUAGE', 'auto');
// Use the Deepgram/OpenRouter/ElevenLabs voice pipeline instead of OpenAI realtime voice.
const usePipelineFallback = true;
const sendInitialGreetingOnJoin = readEnv('LIVEKIT_SEND_INITIAL_GREETING', 'false').toLowerCase() === 'true';
const disableAdaptiveInterruption = readEnv('LIVEKIT_DISABLE_ADAPTIVE_INTERRUPTION', 'true').toLowerCase() === 'true';

function maskSecret(value) {
	if (!value) {
		return '(missing)';
	}

	if (value.length <= 4) {
		return '*'.repeat(value.length);
	}

	return `${value.slice(0, 2)}***${value.slice(-2)}`;
}

function ensureRequiredConfig() {
	const livekitUrl = requireEnv('LIVEKIT_URL', 'Set it to your LiveKit server URL, for example ws://127.0.0.1:7880 or wss://your-livekit-host.');
	const livekitApiKey = requireEnv('LIVEKIT_API_KEY', 'Set it to the same API key used by your token endpoint.');
	const livekitApiSecret = requireEnv('LIVEKIT_API_SECRET', 'Set it to the same API secret used by your token endpoint.');

	const openaiApiKey = readEnv('OPENAI_API_KEY');
	const elevenLabsConfigured = Boolean(elevenLabsApiKey);
	const openaiVoiceRequired = !usePipelineFallback && !elevenLabsConfigured;
	const openaiTtsRequired = !elevenLabsConfigured;

	if (openaiVoiceRequired || openaiTtsRequired) {
		requireEnv('OPENAI_API_KEY', 'Set OPENAI_API_KEY so the LiveKit agent can run TTS and optional realtime voice.');
	}

	const deepgramApiKeyValue = usePipelineFallback ? requireEnv('DEEPGRAM_API_KEY', 'Set DEEPGRAM_API_KEY so the LiveKit agent can run Deepgram STT.') : readEnv('DEEPGRAM_API_KEY');
	const groqApiKey = chatProvider === 'groq' ? requireEnv('GROQ_API_KEY', 'Set GROQ_API_KEY so the LiveKit agent can run the Groq LLM.') : readEnv('GROQ_API_KEY');
	const deepseekApiKey =
		chatProvider === 'deepseek'
			? requireEnv('DEEPSEEK_API_KEY', 'Set DEEPSEEK_API_KEY so the LiveKit agent can run the DeepSeek LLM.')
			: readEnv('DEEPSEEK_API_KEY');
	const openRouterApiKey =
		chatProvider === 'openrouter'
			? requireEnv('OPENROUTER_API_KEY', 'Set OPENROUTER_API_KEY so the LiveKit agent can run the OpenRouter LLM.')
			: readEnv('OPENROUTER_API_KEY');

	return {
		livekitUrl,
		livekitApiKey,
		livekitApiSecret,
		openaiApiKey,
		elevenLabsApiKey,
		deepgramApiKey: deepgramApiKeyValue,
		groqApiKey,
		deepseekApiKey,
		openRouterApiKey,
	};
}

function logStartup(config) {
	console.log('[livekit-agent] Starting Habi Friend LiveKit voice agent');
	console.log(`[livekit-agent] Agent name: ${agentName}`);
	console.log(`[livekit-agent] LiveKit URL: ${config.livekitUrl}`);
	console.log(`[livekit-agent] LiveKit API key: ${maskSecret(config.livekitApiKey)}`);
	console.log(`[livekit-agent] LiveKit API secret: ${maskSecret(config.livekitApiSecret)}`);
	console.log(`[livekit-agent] OpenAI API key: ${maskSecret(config.openaiApiKey)}`);
	console.log(`[livekit-agent] ElevenLabs API key: ${maskSecret(config.elevenLabsApiKey)}`);
	console.log(`[livekit-agent] Deepgram API key: ${maskSecret(config.deepgramApiKey)}`);
	console.log(`[livekit-agent] Groq API key: ${maskSecret(config.groqApiKey)}`);
	console.log(`[livekit-agent] DeepSeek API key: ${maskSecret(config.deepseekApiKey)}`);
	console.log(`[livekit-agent] OpenRouter API key: ${maskSecret(config.openRouterApiKey)}`);
	console.log(
		`[livekit-agent] Mode: ${usePipelineFallback ? 'Deepgram STT + configurable LLM + ElevenLabs/OpenAI TTS voice pipeline' : 'OpenAI realtime multimodal voice'}`
	);
	console.log(`[livekit-agent] Realtime model: ${realtimeModel}`);
	console.log(`[livekit-agent] Chat provider: ${chatProvider}`);
	console.log(`[livekit-agent] Chat model: ${chatModel}`);
	console.log(`[livekit-agent] TTS provider: ${elevenLabsApiKey ? 'elevenlabs' : 'openai'}`);
	console.log(`[livekit-agent] TTS model: ${elevenLabsApiKey ? elevenLabsModel : ttsModel}`);
	console.log(`[livekit-agent] Voice: ${elevenLabsApiKey ? elevenLabsVoiceId : voiceName}`);
	console.log(`[livekit-agent] Initial greeting on join: ${sendInitialGreetingOnJoin ? 'enabled' : 'disabled'}`);
	console.log(`[livekit-agent] Adaptive interruption disabled: ${disableAdaptiveInterruption ? 'enabled' : 'disabled'}`);
}

function attachSessionLogging(session) {
	const metricsEventName = metrics?.AgentMetricsEvent || 'metrics_collected';
	session.on(metricsEventName, (event) => {
		console.log('[livekit-agent] Metrics event received', event);
	});

	session.on('speech_created', (event) => {
		console.log('[livekit-agent] Speech created', event);
	});

	session.on('user_input_transcribed', (event) => {
		console.log('[livekit-agent] User input transcribed', event);
	});

	session.on('agent_state_changed', (event) => {
		console.log('[livekit-agent] Agent state changed', event);
	});

	session.on('user_state_changed', (event) => {
		console.log('[livekit-agent] User state changed', event);
	});

	// Additional transcription-level debug events if emitted by the session
	try {
		session.on('speech_transcribed', (event) => {
			console.log('[livekit-agent] Speech transcribed', event);
		});
	} catch (e) {}

	try {
		session.on('stt_result', (event) => {
			console.log('[livekit-agent] STT result event', event);
		});
	} catch (e) {}

	session.on('conversation_item_added', (event) => {
		console.log('[livekit-agent] Conversation item added', event);
	});

	session.on('session_usage_updated', (event) => {
		console.log('[livekit-agent] Session usage updated', event);
	});

	session.on('error', (event) => {
		const message = event?.error?.message || event?.message || String(event);
		const lowered = String(message).toLowerCase();

		if (lowered.includes('request was aborted') || lowered.includes('cancelled') || lowered.includes('interruption')) {
			console.warn('[livekit-agent] Non-fatal session interruption/error observed:', message);
			return;
		}

		console.error('[livekit-agent] Session error', event);
	});
}

function attachPipelineComponentLogging(stt, llm, tts) {
	if (stt && typeof stt.on === 'function') {
		stt.on('metrics_collected', (event) => {
			console.log('[livekit-agent] STT metrics', event);
		});
		stt.on('error', (event) => {
			console.error('[livekit-agent] STT error', event);
		});

		// Attach a broad set of STT event listeners for debugging (some plugins emit different event names)
		['transcript', 'result', 'transcription', 'data', 'final', 'message'].forEach((ev) => {
			try {
				stt.on(ev, (payload) => {
					console.log(`[livekit-agent] STT event '${ev}':`, payload);
				});
			} catch (e) {
				// ignore if the event name is not supported by the plugin
			}
		});

		try {
			console.log('[livekit-agent] STT prototype methods', Object.getOwnPropertyNames(Object.getPrototypeOf(stt)));
		} catch (e) {}
	}

	if (llm && typeof llm.on === 'function') {
		llm.on('metrics_collected', (event) => {
			console.log('[livekit-agent] LLM metrics', event);
		});
		llm.on('error', (event) => {
			console.error('[livekit-agent] LLM error', event);
		});
	}

	if (tts && typeof tts.on === 'function') {
		tts.on('metrics_collected', (event) => {
			console.log('[livekit-agent] TTS metrics', event);
		});
		tts.on('error', (event) => {
			console.error('[livekit-agent] TTS error', event);
		});
	}
}

function createRealtimeModel(config) {
	return new openai.realtime.RealtimeModel({
		apiKey: config.openaiApiKey,
		model: realtimeModel,
		voice: voiceName,
	});
}

function createRealtimeAgent() {
	return new voice.Agent({
		instructions: AGENT_INSTRUCTIONS,
	});
}

function createChatLlm(config) {
	if (chatProvider === 'groq') {
		return openai.LLM.withGroq({
			apiKey: config.groqApiKey,
			model: chatModel,
		});
	}

	if (chatProvider === 'deepseek') {
		return openai.LLM.withDeepSeek({
			apiKey: config.deepseekApiKey,
			model: chatModel,
		});
	}

	if (chatProvider === 'openrouter') {
		return new openai.LLM({
			apiKey: config.openRouterApiKey,
			baseURL: 'https://openrouter.ai/api/v1',
			model: chatModel,
		});
	}

	return new openai.LLM({
		apiKey: config.openaiApiKey,
		model: chatModel,
	});
}

function createTts(config) {
	if (elevenLabsApiKey) {
		return new elevenlabs.TTS({
			apiKey: config.elevenLabsApiKey,
			voice: { id: elevenLabsVoiceId },
			model: elevenLabsModel,
		});
	}

	return new openai.TTS({
		apiKey: config.openaiApiKey,
		model: ttsModel,
		voice: voiceName,
	});
}

async function createPipelineSession(config) {
	const vad = await silero.VAD.load();
	const stt = new deepgram.STT({
		apiKey: config.deepgramApiKey,
		model: deepgramModel,
		language: deepgramLanguage,
		interimResults: false,
		punctuate: true,
		smartFormat: true,
	});

	// Debug: inspect the STT instance and available methods to help diagnose empty transcripts
	try {
		console.log('[livekit-agent] STT instance created', { stt_type: stt?.constructor?.name || 'unknown' });
		if (stt && typeof Object.getPrototypeOf === 'function') {
			console.log('[livekit-agent] STT prototype methods', Object.getOwnPropertyNames(Object.getPrototypeOf(stt)));
		}
	} catch (e) {
		console.warn('[livekit-agent] Failed to inspect STT instance for debugging', e);
	}
	const llm = createChatLlm(config);
	const tts = createTts(config);
	const session = new voice.AgentSession({
		vad,
		stt,
		llm,
		tts,
		turnHandling: disableAdaptiveInterruption
			? {
					interruption: {
						enabled: false,
						discardAudioIfUninterruptible: true,
						minDuration: 1000,
					},
					endpointing: {
						minDelay: 500,
						maxDelay: 3000,
					},
				}
			: undefined,
	});

	attachPipelineComponentLogging(stt, llm, tts);
	return session;
}

function createPipelineAgent() {
	return new voice.Agent({
		instructions: AGENT_INSTRUCTIONS,
	});
}

async function sendInitialGreeting(session, modeLabel) {
	console.log('[livekit-agent] Sending initial greeting...');

	try {
		await session.generateReply(
			'Give the user a short warm spoken greeting. Briefly introduce yourself as Habi Friend and invite them to talk.'
		);
		console.log(`[livekit-agent] ${modeLabel} initial greeting sent`);
	} catch (error) {
		const message = error instanceof Error ? error.message : String(error);
		console.error(`[livekit-agent] Failed to generate initial greeting in ${modeLabel}: ${message}`);

		if (message.includes('insufficient_quota') || message.includes('429') || message.toLowerCase().includes('quota')) {
			console.error(
				'[livekit-agent] OpenAI quota is exhausted. The agent session can connect to LiveKit, but it cannot generate LLM replies until the OpenAI billing/quota issue is fixed.'
			);
		}
	}
}

async function wait(ms) {
	return new Promise((resolve) => setTimeout(resolve, ms));
}

export default defineAgent({
	entry: async (ctx) => {
		const config = ensureRequiredConfig();
		logStartup(config);

		console.log('[livekit-agent] Connecting to LiveKit room...');
		await ctx.connect();
		const roomName = ctx.room?.name || 'unknown-room';
		console.log(`[livekit-agent] Connected to room: ${roomName}`);

		console.log('[livekit-agent] Waiting for remote participant...');
		const participant = await ctx.waitForParticipant();
		console.log(`[livekit-agent] Participant joined: ${participant.identity}`);

		if (usePipelineFallback) {
			console.log(
				`[livekit-agent] Initializing voice pipeline with Deepgram STT, ${elevenLabsApiKey ? 'ElevenLabs' : 'OpenAI'} TTS, and ${chatProvider} LLM...`
			);
			const session = await createPipelineSession(config);
			const agent = createPipelineAgent();
			attachSessionLogging(session);
			await session.start({
				agent,
				room: ctx.room,
			});

			console.log('[livekit-agent] Voice pipeline session started');

			if (sendInitialGreetingOnJoin) {
				await sendInitialGreeting(session, 'voice pipeline');
				await wait(400);
			}

			console.log('[livekit-agent] Voice pipeline is ready for the user input');
			return;
		}

		console.log('[livekit-agent] Initializing OpenAI realtime multimodal voice agent...');
		const session = new voice.AgentSession({
			llm: createRealtimeModel(config),
		});
		const agent = createRealtimeAgent();
		attachSessionLogging(session);
		await session.start({
			agent,
			room: ctx.room,
		});

		console.log('[livekit-agent] Realtime voice session started');

		if (sendInitialGreetingOnJoin) {
			await sendInitialGreeting(session, 'realtime voice');
			await wait(400);
		}

		console.log('[livekit-agent] Realtime voice session is ready for the user input');
	},
});

cli.runApp(
	new ServerOptions({
		agent: fileURLToPath(import.meta.url),
		agentName,
	})
);
