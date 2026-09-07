import os
import time
import base64
import hashlib
import hmac
import json

import aiohttp
from dotenv import load_dotenv
from fastapi import FastAPI, WebSocket
from pipecat.audio.vad.silero import SileroVADAnalyzer
from pipecat.audio.vad.vad_analyzer import VADParams
from pipecat.frames.frames import Frame, InputAudioRawFrame, LLMMessagesUpdateFrame, OutputAudioRawFrame, TextFrame
from pipecat.pipeline.pipeline import Pipeline
from pipecat.pipeline.runner import PipelineRunner
from pipecat.pipeline.task import PipelineParams, PipelineTask
from pipecat.processors.aggregators.llm_context import LLMContext
from pipecat.processors.aggregators.llm_response_universal import LLMContextAggregatorPair, LLMUserAggregatorParams
from pipecat.processors.frame_processor import FrameDirection, FrameProcessor
from pipecat.services.deepgram.stt import DeepgramSTTService
from pipecat.services.elevenlabs.tts import ElevenLabsHttpTTSService
from pipecat.services.tts_service import TextAggregationMode
from pipecat.services.openai.llm import OpenAILLMService
from pipecat.serializers.base_serializer import FrameSerializer
from pipecat.turns.user_stop import SpeechTimeoutUserTurnStopStrategy
from pipecat.turns.user_turn_strategies import UserTurnStrategies
from pipecat.transports.websocket.fastapi import FastAPIWebsocketParams, FastAPIWebsocketTransport

load_dotenv()

app = FastAPI()

SYSTEM_PROMPT = (
    "You are Habi Friend, a kind, concise AI companion for a habit-building app. "
    "Give supportive, age-appropriate replies and help the user take one practical next step."
)


class ReplyTextSender(FrameProcessor):
    def __init__(self, websocket: WebSocket) -> None:
        super().__init__()
        self._websocket = websocket
        self._response_started_at: float | None = None

    async def process_frame(self, frame: Frame, direction: FrameDirection) -> None:
        if isinstance(frame, TextFrame) and frame.text.strip():
            if self._response_started_at is None:
                self._response_started_at = time.perf_counter()
                print("[Pipecat] First LLM text chunk ready")
            await self._websocket.send_json({"type": "assistant_text", "text": frame.text})
        elif isinstance(frame, OutputAudioRawFrame) and self._response_started_at is not None:
            print("[Pipecat] First audio chunk ready")
            self._response_started_at = None
        await self.push_frame(frame, direction)


class PcmFrameSerializer(FrameSerializer):
    async def serialize(self, frame: Frame) -> bytes | None:
        if isinstance(frame, OutputAudioRawFrame):
            return frame.audio
        return None

    async def deserialize(self, data: str | bytes) -> Frame | None:
        if isinstance(data, bytes) and data:
            return InputAudioRawFrame(audio=data, sample_rate=16000, num_channels=1)
        return None


def required_env(name: str) -> str:
    value = os.getenv(name, "").strip()
    if not value:
        raise RuntimeError(f"Missing required environment variable: {name}")
    return value


def verify_session_token(token: str) -> bool:
    try:
        encoded_payload, supplied_signature = token.split(".", 1)
        secret = required_env("PIPECAT_SESSION_SECRET")
        expected_signature = hmac.new(
            secret.encode("utf-8"), encoded_payload.encode("ascii"), hashlib.sha256
        ).digest()
        if not hmac.compare_digest(
            base64.urlsafe_b64decode(supplied_signature + "=" * (-len(supplied_signature) % 4)),
            expected_signature,
        ):
            return False
        payload = json.loads(
            base64.urlsafe_b64decode(encoded_payload + "=" * (-len(encoded_payload) % 4))
        )
        return bool(payload.get("uid")) and int(payload.get("exp", 0)) > int(time.time())
    except (ValueError, TypeError, KeyError, json.JSONDecodeError, base64.binascii.Error):
        return False


@app.get("/health")
async def health() -> dict[str, str]:
    return {"status": "ok", "service": "pipecat"}


@app.websocket("/ws/voice")
async def voice_session(websocket: WebSocket) -> None:
    session_token = websocket.query_params.get("token", "")
    if not verify_session_token(session_token):
        await websocket.close(code=1008, reason="Valid Pipecat session token required")
        return
    await websocket.accept()

    transport = FastAPIWebsocketTransport(
        websocket,
        params=FastAPIWebsocketParams(
            audio_in_enabled=True,
            audio_in_sample_rate=16000,
            audio_in_channels=1,
            audio_out_enabled=True,
            audio_out_sample_rate=24000,
            audio_out_channels=1,
            audio_out_10ms_chunks=2,
            serializer=PcmFrameSerializer(),
            vad_analyzer=SileroVADAnalyzer(params=VADParams(stop_secs=0.15)),
        ),
    )

    stt = DeepgramSTTService(
        api_key=required_env("DEEPGRAM_API_KEY"),
        sample_rate=16000,
        encoding="linear16",
        channels=1,
    )
    llm_provider = os.getenv("PIPECAT_LLM_PROVIDER", os.getenv("LLM_PROVIDER", "openai")).strip().lower()
    if llm_provider == "groq":
        llm = OpenAILLMService(
            api_key=required_env("GROQ_API_KEY"),
            base_url="https://api.groq.com/openai/v1",
            settings=OpenAILLMService.Settings(
                model=os.getenv("GROQ_MODEL", "llama-3.1-8b-instant"),
                max_tokens=96,
            ),
        )
    elif llm_provider == "openrouter":
        llm = OpenAILLMService(
            api_key=required_env("OPENROUTER_API_KEY"),
            base_url="https://openrouter.ai/api/v1",
            settings=OpenAILLMService.Settings(
                model=os.getenv("OPENROUTER_MODEL", "openai/gpt-4o-mini"),
                max_tokens=96,
            ),
        )
    else:
        llm = OpenAILLMService(
            api_key=required_env("OPENAI_API_KEY"),
            settings=OpenAILLMService.Settings(
                model=os.getenv("OPENAI_CHAT_MODEL", "gpt-4.1-mini"),
                max_tokens=96,
            ),
        )
    tts_session = aiohttp.ClientSession()
    tts = ElevenLabsHttpTTSService(
        api_key=required_env("ELEVENLABS_API_KEY"),
        aiohttp_session=tts_session,
        settings=ElevenLabsHttpTTSService.Settings(
            voice=os.getenv("ELEVENLABS_VOICE_ID", ""),
            model=os.getenv("ELEVENLABS_MODEL", "eleven_flash_v2_5"),
            speed=1.1,
            optimize_streaming_latency=4,
        ),
        text_aggregation_mode=TextAggregationMode.TOKEN,
        sample_rate=24000,
    )

    messages = [{"role": "system", "content": SYSTEM_PROMPT}]
    context = LLMContext(messages)
    context_aggregator = LLMContextAggregatorPair(
        context,
        user_params=LLMUserAggregatorParams(
            user_turn_strategies=UserTurnStrategies(
                stop=[SpeechTimeoutUserTurnStopStrategy(user_speech_timeout=0.35)]
            )
        ),
    )
    pipeline = Pipeline(
        [
            transport.input(),
            stt,
            context_aggregator.user(),
            llm,
            ReplyTextSender(websocket),
            tts,
            transport.output(),
            context_aggregator.assistant(),
        ]
    )
    task = PipelineTask(
        pipeline,
        params=PipelineParams(
            allow_interruptions=True,
            enable_metrics=True,
            enable_usage_metrics=True,
        ),
    )

    @transport.event_handler("on_client_connected")
    async def on_client_connected(_transport: FastAPIWebsocketTransport, _client: object) -> None:
        await task.queue_frames([LLMMessagesUpdateFrame(messages, run_llm=False)])

    try:
        await PipelineRunner().run(task)
    finally:
        await tts_session.close()
