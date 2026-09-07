extends Node

var _music_player: AudioStreamPlayer
var _fx_players: Array[AudioStreamPlayer] = []

const MUSIC_PATH: String = "res://Valley of Dreams - Beautiful Medieval Fantasy Music & Ambience.mp3"
const FALLBACK_MUSIC_PATHS: Array[String] = [
	"res://audio/adventure_background.wav",
	"res://audio/valley_of_dreams.ogg",
	"res://audio/valley_of_dreams.mp3"
]
const BUTTON_PATH: String = "res://audio/button_click.wav"
const EXP_PATH: String = "res://audio/exp_gain.wav"
const COIN_PATH: String = "res://audio/coin_gain.wav"
const POTION_PATH: String = "res://audio/potion_buy.wav"
const MUSIC_BUS_NAME: String = "Music"
const SFX_BUS_NAME: String = "SFX"

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_ensure_audio_buses()
	_create_music_player()
	call_deferred("_bind_scene_buttons")
	get_tree().node_added.connect(_on_node_added)
	play_background_music()

func _ensure_audio_buses() -> void:
	var music_index: int = AudioServer.get_bus_index(MUSIC_BUS_NAME)
	if music_index == -1:
		AudioServer.add_bus()
		music_index = AudioServer.get_bus_count() - 1
		AudioServer.set_bus_name(music_index, MUSIC_BUS_NAME)
	AudioServer.set_bus_mute(music_index, false)

	var sfx_index: int = AudioServer.get_bus_index(SFX_BUS_NAME)
	if sfx_index == -1:
		AudioServer.add_bus()
		sfx_index = AudioServer.get_bus_count() - 1
		AudioServer.set_bus_name(sfx_index, SFX_BUS_NAME)
	AudioServer.set_bus_mute(sfx_index, false)

func _on_node_added(node: Node) -> void:
	if node == null:
		return
	if node is Button:
		_connect_button_audio(node)
	for child in node.get_children():
		if child is Button:
			_connect_button_audio(child)

func _bind_scene_buttons() -> void:
	if get_tree() == null or get_tree().root == null:
		return
	_bind_scene_buttons_to_node(get_tree().root)

func _bind_scene_buttons_to_node(node: Node) -> void:
	if node == null:
		return
	if node is Button:
		_connect_button_audio(node)
	for child in node.get_children():
		_bind_scene_buttons_to_node(child)

func _connect_button_audio(button: Button) -> void:
	if button == null:
		return
	if not button.pressed.is_connected(_on_button_pressed):
		button.pressed.connect(_on_button_pressed)

func _on_button_pressed() -> void:
	play_button_click()

func _create_music_player() -> void:
	if _music_player != null and is_instance_valid(_music_player):
		return
	_music_player = AudioStreamPlayer.new()
	_music_player.name = "AdventureMusicPlayer"
	_music_player.volume_db = -18.0
	_music_player.autoplay = false
	_music_player.bus = MUSIC_BUS_NAME
	_music_player.process_mode = Node.PROCESS_MODE_ALWAYS
	_music_player.finished.connect(_restart_background_music)
	var stream: AudioStream = _load_audio_stream(MUSIC_PATH)
	if stream == null:
		stream = _build_adventure_music_loop()
	_music_player.stream = stream
	add_child(_music_player)

func _restart_background_music() -> void:
	if _music_player != null and _music_player.stream != null:
		_music_player.play()

func play_background_music() -> void:
	_create_music_player()
	if _music_player != null and not _music_player.playing:
		_music_player.play()

func play_button_click() -> void:
	_play_audio_file(BUTTON_PATH, -10.0)

func play_exp_gain() -> void:
	_play_audio_file(EXP_PATH, -8.0)

func play_coin_gain() -> void:
	_play_audio_file(COIN_PATH, -7.0)

func play_potion_buy() -> void:
	_play_audio_file(POTION_PATH, -6.0)

func _play_audio_file(path: String, volume_db: float) -> void:
	var player := AudioStreamPlayer.new()
	var stream: AudioStream = _load_audio_stream(path)
	if stream == null:
		stream = _build_tone_stream([660.0], 0.1, 0.18)
	player.stream = stream
	player.volume_db = volume_db
	player.bus = SFX_BUS_NAME
	player.finished.connect(player.queue_free)
	_fx_players.append(player)
	add_child(player)
	player.play()

func set_sound_effects_enabled(enabled: bool) -> void:
	_ensure_audio_buses()
	var bus_index: int = AudioServer.get_bus_index(SFX_BUS_NAME)
	if bus_index >= 0:
		AudioServer.set_bus_mute(bus_index, not enabled)

func set_music_enabled(enabled: bool) -> void:
	_ensure_audio_buses()
	var bus_index: int = AudioServer.get_bus_index(MUSIC_BUS_NAME)
	if bus_index >= 0:
		AudioServer.set_bus_mute(bus_index, not enabled)
	if _music_player != null:
		if enabled and not _music_player.playing:
			_music_player.play()
		elif not enabled and _music_player.playing:
			_music_player.stop()

func set_notifications_enabled(enabled: bool) -> void:
	ProjectSettings.set_setting("game/notifications_enabled", enabled)

func _load_audio_stream(path: String) -> AudioStream:
	if path == "":
		return null
	var candidates: Array[String] = [path]
	for fallback_path in FALLBACK_MUSIC_PATHS:
		if fallback_path != path and not candidates.has(fallback_path):
			candidates.append(fallback_path)
	for candidate in candidates:
		var resource = load(candidate)
		if resource == null:
			continue
		if resource is AudioStream:
			return resource as AudioStream
	return null

func _build_tone_stream(frequencies: Array, duration_sec: float, amplitude: float) -> AudioStreamWAV:
	var sample_rate: int = 44100
	var total_samples: int = int(sample_rate * duration_sec)
	var data := PackedByteArray()
	for i in range(total_samples):
		var t: float = float(i) / float(sample_rate)
		var value: float = 0.0
		for freq in frequencies:
			value += sin(PI * 2.0 * float(freq) * t)
		value /= max(1.0, float(frequencies.size()))
		var envelope: float = 1.0
		if t < 0.04:
			envelope = t / 0.04
		if t > duration_sec - 0.04:
			envelope = (duration_sec - t) / 0.04
		var sample: float = clamp(value * envelope * amplitude, -1.0, 1.0)
		var pcm: int = int(sample * 32767.0)
		data.append(pcm & 0xFF)
		data.append((pcm >> 8) & 0xFF)
	var stream := AudioStreamWAV.new()
	stream.mix_rate = sample_rate
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.stereo = false
	stream.data = data
	return stream

func _build_adventure_music_loop() -> AudioStreamWAV:
	var sample_rate: int = 44100
	var total_seconds: float = 8.0
	var total_samples: int = int(sample_rate * total_seconds)
	var notes: Array = [220.0, 277.0, 329.0, 392.0, 329.0, 277.0, 349.0, 392.0]
	var data := PackedByteArray()
	for i in range(total_samples):
		var t: float = float(i) / float(sample_rate)
		var phase: float = PI * 2.0 * t
		var step_index: int = int(floor(t / 0.5)) % notes.size()
		var base_freq: float = float(notes[step_index])
		var melody: float = sin(phase * base_freq * 0.0001) * 0.65
		var harmony: float = sin(phase * (base_freq * 0.5) * 0.0001) * 0.25
		var accent: float = 0.12 * sin(phase * 2.0)
		var sample: float = clamp((melody + harmony + accent) * 0.12, -1.0, 1.0)
		var pcm: int = int(sample * 32767.0)
		data.append(pcm & 0xFF)
		data.append((pcm >> 8) & 0xFF)
	var stream := AudioStreamWAV.new()
	stream.mix_rate = sample_rate
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.stereo = false
	stream.data = data
	return stream
