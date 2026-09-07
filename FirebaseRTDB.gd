extends Node

const DEFAULT_DATABASE_URL: String = "https://adv-habi-default-rtdb.firebaseio.com"
const GOOGLE_SERVICES_PATH: String = "res://google-services.json"

@export var database_url: String = DEFAULT_DATABASE_URL
@export var auth_token: String = ""

var _http: HTTPRequest
var _pending_requests: Array[Dictionary] = []
var _current_callback: Callable = Callable()
var _current_callback_object_id: int = 0
var _request_in_flight: bool = false
var _config_loaded: bool = false


func _ready() -> void:
	_http = HTTPRequest.new()
	_http.name = "FirebaseRealtimeDatabaseHttp"
	add_child(_http)
	_http.request_completed.connect(_on_request_completed)
	_load_database_config()

func _load_database_config() -> void:
	if _config_loaded:
		return
	var file: FileAccess = FileAccess.open(GOOGLE_SERVICES_PATH, FileAccess.READ)
	if file == null:
		_config_loaded = true
		return
	var text: String = file.get_as_text()
	file.close()
	var parsed: Variant = JSON.parse_string(text)
	if parsed is Dictionary:
		var project_info: Dictionary = parsed.get("project_info", {})
		if project_info is Dictionary and project_info.has("firebase_url"):
			var configured_url: String = str(project_info.get("firebase_url", "")).strip_edges()
			if not configured_url.is_empty():
				database_url = configured_url
	_config_loaded = true


func write_json(path: String, data: Variant, callback: Callable = Callable()) -> void:
	_queue_request(path, HTTPClient.METHOD_PUT, JSON.stringify(data), callback)


func set_auth_token(token: String) -> void:
	auth_token = token.strip_edges()


func update_json(path: String, data: Variant, callback: Callable = Callable()) -> void:
	_queue_request(path, HTTPClient.METHOD_PATCH, JSON.stringify(data), callback)


func read_json(path: String, callback: Callable = Callable()) -> void:
	_queue_request(path, HTTPClient.METHOD_GET, "", callback)


func delete_json(path: String, callback: Callable = Callable()) -> void:
	_queue_request(path, HTTPClient.METHOD_DELETE, "", callback)


func _queue_request(path: String, method: int, payload: String, callback: Callable) -> void:
	if callback == null or not callback.is_valid():
		return
	var callback_object_id: int = callback.get_object_id()
	if callback_object_id != 0 and not is_instance_id_valid(callback_object_id):
		return
	var request_data: Dictionary = {
		"path": path,
		"method": method,
		"payload": payload,
		"callback": callback,
		"callback_object_id": callback_object_id
	}
	_pending_requests.append(request_data)
	if not _request_in_flight:
		_request_in_flight = true
		_send_next_request()


func _send_next_request() -> void:
	while not _pending_requests.is_empty():
		var next_request: Dictionary = _pending_requests.pop_front()
		var next_callback: Callable = next_request.get("callback", Callable())
		var next_callback_object_id: int = int(next_request.get("callback_object_id", 0))
		if _is_callback_alive(next_callback, next_callback_object_id):
			var request_data: Dictionary = next_request
			var path: String = request_data["path"]
			var method: int = request_data["method"]
			var payload: String = request_data["payload"]
			var callback: Callable = request_data["callback"]
			var callback_object_id: int = int(request_data.get("callback_object_id", 0))
			var url: String = _build_url(path)
			var headers: PackedStringArray = ["Content-Type: application/json"]

			if auth_token != "":
				url = url + "?auth=" + auth_token.uri_encode()

			_current_callback = callback
			_current_callback_object_id = callback_object_id
			_request_in_flight = true
			var error: Error = _http.request(url, headers, method, payload)
			if error != OK:
				_current_callback = Callable()
				_current_callback_object_id = 0
				_dispatch_callback(error, 0, null, callback, callback_object_id)
				_send_next_request()
			return

	_request_in_flight = false
	_current_callback = Callable()
	_current_callback_object_id = 0


func _dispatch_callback(result: int, response_code: int, body_data: Variant, callback: Callable, callback_object_id: int = 0) -> void:
	if not _is_callback_alive(callback, callback_object_id):
		return
	callback.call(result, response_code, body_data)


func _is_callback_alive(callback: Callable, callback_object_id: int = 0) -> bool:
	if callback == null or not callback.is_valid():
		return false
	if callback_object_id != 0 and not is_instance_id_valid(callback_object_id):
		return false
	return true


func _on_request_completed(result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	var parsed_body: Variant = _parse_response(body)
	var callback: Callable = _current_callback
	var callback_object_id: int = _current_callback_object_id
	_current_callback = Callable()
	_current_callback_object_id = 0
	if _is_callback_alive(callback, callback_object_id):
		_dispatch_callback(result, response_code, parsed_body, callback, callback_object_id)
	_send_next_request()


func _parse_response(body: PackedByteArray) -> Variant:
	if body.is_empty():
		return null

	var text: String = body.get_string_from_utf8()
	if text.strip_edges() == "":
		return null

	var parsed = JSON.parse_string(text)
	# JSON.parse_string returns a JSONParseResult in Godot 4 with `error` and `result`.
	# If parsing failed or returned no result, return null to signal no data.
	if parsed == null:
		return null
	# If the parse result is a JSONParseResult object, inspect its fields.
	if typeof(parsed) == TYPE_OBJECT and parsed.has("error"):
		if parsed.error == OK:
			var res = parsed.result
			return res if res != null else null
		return null
	# If parsing returned a raw Dictionary (fallback), return it directly
	if parsed is Dictionary:
		return parsed
	return null


func _build_url(path: String) -> String:
	var clean_path: String = path.strip_edges()
	if clean_path.is_empty():
		return database_url.rstrip("/") + ".json"

	var base_url: String = database_url.rstrip("/")
	if clean_path.ends_with(".json"):
		return base_url + "/" + clean_path.lstrip("/")
	return base_url + "/" + clean_path.lstrip("/") + ".json"
