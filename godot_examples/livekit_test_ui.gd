extends Control

@export var backend_url: String = "http://127.0.0.1:5000"
@export var room_name: String = "habi-voice-room"

var room = null

@onready var status_label = $VBoxContainer/StatusLabel
@onready var token_label = $VBoxContainer/TokenLabel
@onready var connect_button = $VBoxContainer/ConnectButton
@onready var backend_edit = $VBoxContainer/BackendEdit
@onready var room_edit = $VBoxContainer/RoomEdit

func _ready():
    backend_edit.text = backend_url
    room_edit.text = room_name
    connect_button.connect("pressed", Callable(self, "_on_connect_pressed"))

func _on_connect_pressed() -> void:
    status_label.text = "Requesting token..."
    var http = HTTPRequest.new()
    add_child(http)
    http.connect("request_completed", Callable(self, "_on_request_completed"))

    var body := {"roomName": room_edit.text, "identity": "godot-test", "name": "Godot Test"}
    var json = JSON.stringify(body)
    var url = backend_edit.text.rstrip("/") + "/api/livekit/token"
    var err = http.request(url, [], HTTPClient.METHOD_POST, json)
    if err != OK:
        status_label.text = "HTTPRequest failed to start: %s" % str(err)

func _on_request_completed(_result, response_code, _headers, body_arr: PackedByteArray) -> void:
    var body_text = ""
    if body_arr.size() > 0:
        body_text = body_arr.get_string_from_utf8()

    if response_code != 200:
        status_label.text = "Token request failed: %s" % str(response_code)
        token_label.text = body_text
        return

    var parsed = JSON.parse_string(body_text)
    if parsed["error"] != OK:
        status_label.text = "Failed parsing token response JSON"
        return

    var token = parsed["result"]["token"]
    var url = parsed["result"]["url"]
    token_label.text = token
    status_label.text = "Connecting to LiveKit..."

    if not ClassDB.class_exists("LiveKitRoom"):
        status_label.text = "LiveKitRoom class unavailable. Enable the LiveKit plugin."
        return

    var room_obj = ClassDB.instantiate("LiveKitRoom")
    if room_obj == null:
        status_label.text = "Unable to instantiate LiveKitRoom from the extension"
        return

    room = room_obj
    if room is Node:
        add_child(room)
    room.connected.connect(Callable(self, "_on_connected"))
    room.disconnected.connect(Callable(self, "_on_disconnected"))
    room.participant_connected.connect(Callable(self, "_on_participant_connected"))
    room.track_subscribed.connect(Callable(self, "_on_track_subscribed"))
    room.connect_to_room(url, token, {})

func _on_connected() -> void:
    status_label.text = "LiveKit room connected"

func _on_disconnected() -> void:
    status_label.text = "LiveKit room disconnected"

func _on_participant_connected(participant) -> void:
    status_label.text = "Participant connected: %s" % participant.get_identity()

func _on_track_subscribed(_track, _publication, participant) -> void:
    status_label.text = "Track subscribed from: %s" % participant.get_identity()
