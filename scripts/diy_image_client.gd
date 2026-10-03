class_name DiyImageClient
extends Node
## Version-bound client for the local cocktail image service. No model API key belongs here.

signal job_changed(info: Dictionary)
signal image_ready(recipe_id: String, revision: int, path: String, texture: Texture2D, info: Dictionary)
signal generation_failed(code: String, message: String)

const JOBS_PATH := "/v1/drink-image-jobs"
const STYLE_ID := "saloon-cocktail-cutout-v1"
const IMAGE_DIRECTORY := "user://diy_cocktails/images"
const MAX_JSON_BYTES := 256 * 1024
const MAX_REQUEST_BYTES := 8 * 1024 * 1024
const MAX_IMAGE_BYTES := 16 * 1024 * 1024
const MAX_IMAGE_SIDE := 2048
const MAX_IMAGE_PIXELS := 4 * 1024 * 1024

@export var service_url := "http://127.0.0.1:8787"
@export var service_token := ""
@export_range(0.25, 30.0) var poll_interval := 2.0
@export_range(1.0, 120.0) var request_timeout := 20.0
@export_range(30.0, 1800.0) var generation_timeout := 600.0

var _generation := 0
var _active := false
var _origin := ""
var _token := ""
var _recipe_id := ""
var _revision := 0
var _request_id := ""
var _task_id := ""
var _recipe_hash := ""
var _poll_path := ""
var _started_msec := 0
var _job: Dictionary = {}
var _http: HTTPRequest
var _completion_handler: Callable
var _poll_timer: Timer

func _ready() -> void:
	_ensure_timer()

func _exit_tree() -> void:
	# Leaving the scene never applies a late result to a recipe or existing image.
	_generation += 1
	_active = false
	_stop_requests()
	if is_instance_valid(_poll_timer) and _poll_timer.timeout.is_connected(poll):
		_poll_timer.timeout.disconnect(poll)

func generate_drink(request: Dictionary) -> Error:
	# The caller must retain recipe revisions; this client does not modify a catalogue.
	var next_generation := _generation + 1
	cancel()
	if _generation != next_generation:
		return ERR_SKIP
	if not is_inside_tree():
		return _reject("CLIENT_NOT_READY", "酒图客户端尚未加入场景。", ERR_UNCONFIGURED)
	var origin := _valid_origin(service_url)
	if origin.is_empty() or service_token.contains("\n") or service_token.contains("\r"):
		return _reject("INVALID_SERVICE", "酒图服务地址或访问凭据格式不正确。", ERR_INVALID_PARAMETER)
	var recipe: Variant = request.get("recipe")
	if not recipe is Dictionary or not _safe_id(recipe.get("id"), 80) \
			or not _whole_number(recipe.get("revision"), 1, 1000000) \
			or not recipe.get("ingredients") is Array:
		return _reject("INVALID_RECIPE", "请提供配方编号、版本和原料列表。", ERR_INVALID_PARAMETER)
	if request.get("schema_version", 1) != 1 or request.get("style_id", STYLE_ID) != STYLE_ID:
		return _reject("INVALID_REQUEST", "酒图请求版本或画风不受支持。", ERR_INVALID_PARAMETER)
	var request_key: Variant = request.get("request_id", _uuid_v4())
	if not request_key is String or not _matches(request_key, "^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$"):
		return _reject("INVALID_REQUEST_ID", "请求编号需要使用 UUID。", ERR_INVALID_PARAMETER)
	var payload := request.duplicate(true)
	payload["schema_version"] = 1
	payload["style_id"] = STYLE_ID
	payload["request_id"] = request_key
	# Godot's JSON parser reads numbers as floats; the service requires an integer revision.
	payload.recipe["revision"] = int(recipe.revision)
	var encoded := JSON.stringify(payload)
	if encoded.to_utf8_buffer().size() > MAX_REQUEST_BYTES:
		return _reject("REQUEST_TOO_LARGE", "配方或预览图片过大。", ERR_INVALID_PARAMETER)
	_origin = origin
	_token = service_token
	_recipe_id = recipe.id
	_revision = int(recipe.revision)
	_request_id = request_key
	_task_id = ""
	_recipe_hash = ""
	_poll_path = ""
	_started_msec = Time.get_ticks_msec()
	_active = true
	_job = {"status": "submitting", "request_id": _request_id,
		"recipe_id": _recipe_id, "recipe_revision": _revision}
	var serial := _generation
	job_changed.emit(_job.duplicate(true))
	if not _active or serial != _generation:
		return ERR_SKIP
	return _send("submit", JOBS_PATH, HTTPClient.METHOD_POST, encoded)

func cancel() -> void:
	var previous := _job.duplicate(true)
	var was_active := _active
	_generation += 1
	_active = false
	_stop_requests()
	if was_active:
		previous["status"] = "cancelled"
		job_changed.emit(previous)
	# Cancellation is local. A job already accepted by the service can finish there.

func poll() -> Error:
	if not _active or _poll_path.is_empty():
		return ERR_UNCONFIGURED
	if is_instance_valid(_http) or _job.get("status", "") not in ["queued", "running"]:
		return ERR_BUSY
	if is_instance_valid(_poll_timer):
		_poll_timer.stop()
	if Time.get_ticks_msec() - _started_msec > int(generation_timeout * 1000.0):
		_fail("GENERATION_TIMEOUT", "酒图生成等待时间过长，请稍后重试。", true)
		return ERR_TIMEOUT
	return _send("poll", _poll_path, HTTPClient.METHOD_GET)

func is_generating() -> bool:
	return _active

func get_job_info() -> Dictionary:
	return _job.duplicate(true)

func _ensure_timer() -> void:
	if not is_instance_valid(_poll_timer):
		_poll_timer = Timer.new()
		_poll_timer.name = "DiyImagePollTimer"
		_poll_timer.one_shot = true
		_poll_timer.process_mode = Node.PROCESS_MODE_ALWAYS
		_poll_timer.timeout.connect(poll)
		add_child(_poll_timer)

func _send(kind: String, path: String, method: HTTPClient.Method, body := "") -> Error:
	if not _active or not _allowed_path(kind, path):
		_fail("INVALID_SERVICE_PATH", "酒图服务返回了无效的资源地址。")
		return ERR_INVALID_PARAMETER
	var http := HTTPRequest.new()
	http.name = "DiyImageRequest"
	http.process_mode = Node.PROCESS_MODE_ALWAYS
	http.max_redirects = 0
	http.accept_gzip = false
	http.timeout = maxf(1.0, request_timeout)
	http.body_size_limit = MAX_IMAGE_BYTES if kind == "image" else MAX_JSON_BYTES
	add_child(http)
	_http = http
	_completion_handler = _on_response.bind(_generation, kind, http)
	http.request_completed.connect(_completion_handler)
	var headers := PackedStringArray(["Accept: image/png" if kind == "image" else "Accept: application/json"])
	if method == HTTPClient.METHOD_POST:
		headers.append("Content-Type: application/json; charset=utf-8")
	if not _token.is_empty():
		headers.append("Authorization: Bearer " + _token)
	var error := http.request(_origin + path, headers, method, body)
	if error != OK:
		_release_http(http)
		_fail("REQUEST_START_FAILED", "暂时无法连接酒图服务。", true)
	return error

func _on_response(result: int, response_code: int, headers: PackedStringArray, body: PackedByteArray,
		serial: int, kind: String, http: HTTPRequest) -> void:
	_release_http(http)
	if serial != _generation or not _active:
		return
	if result != HTTPRequest.RESULT_SUCCESS:
		if result == HTTPRequest.RESULT_REDIRECT_LIMIT_REACHED:
			_fail("REDIRECT_REJECTED", "酒图服务资源不能跳转到其他地址。")
			return
		if result == HTTPRequest.RESULT_TIMEOUT:
			_fail("REQUEST_TIMEOUT", "酒图服务请求超时，请稍后重试。", true)
			return
		var code := "RESPONSE_TOO_LARGE" if result == HTTPRequest.RESULT_BODY_SIZE_LIMIT_EXCEEDED else "NETWORK_ERROR"
		_fail(code, "酒图下载或服务请求未能完成，请重试。", code == "NETWORK_ERROR")
		return
	if response_code >= 300 and response_code < 400:
		_fail("REDIRECT_REJECTED", "酒图服务资源不能跳转到其他地址。")
		return
	if kind == "image":
		_accept_image(response_code, headers, body)
		return
	if body.size() > MAX_JSON_BYTES or _content_type(headers) != "application/json":
		_fail("INVALID_RESPONSE", "酒图服务返回的格式不正确。")
		return
	var parsed: Variant = JSON.parse_string(body.get_string_from_utf8())
	if not parsed is Dictionary:
		_fail("INVALID_RESPONSE", "酒图服务返回的内容无法读取。")
		return
	if response_code != (202 if kind == "submit" else 200):
		_service_failure(parsed, "HTTP_%d" % response_code)
		return
	_accept_job(parsed, kind, serial)

func _accept_job(info: Dictionary, kind: String, serial: int) -> void:
	if info.get("recipe_id") != _recipe_id or not _whole_number(info.get("recipe_revision"), _revision, _revision) \
			or not _safe_id(info.get("task_id"), 100) \
			or not _matches(str(info.get("recipe_hash", "")), "^[0-9a-f]{64}$"):
		_fail("JOB_MISMATCH", "酒图任务与当前配方版本不一致。")
		return
	if kind == "submit":
		_task_id = info.task_id
		_recipe_hash = info.recipe_hash
		_poll_path = str(info.get("poll_url", ""))
		if not _allowed_path("poll", _poll_path):
			_fail("INVALID_SERVICE_PATH", "酒图服务返回了无效的查询地址。")
			return
	elif info.task_id != _task_id or info.recipe_hash != _recipe_hash:
		_fail("JOB_MISMATCH", "酒图任务编号或配方内容发生了变化。")
		return
	var status: String = str(info.get("status", ""))
	if status not in ["queued", "running", "succeeded", "failed"]:
		_fail("INVALID_STATUS", "酒图服务返回了未知的任务状态。")
		return
	_job = info.duplicate(true)
	_job["request_id"] = _request_id
	if status == "failed":
		_service_failure(info, "GENERATION_FAILED")
		return
	if status == "succeeded":
		var output: Variant = info.get("result")
		if not output is Dictionary or output.get("mime_type") != "image/png" \
				or output.get("transparent") != true or output.get("style_id") != STYLE_ID \
				or output.get("recipe_hash") != _recipe_hash \
				or not _whole_number(output.get("width"), 1, MAX_IMAGE_SIDE) \
				or not _whole_number(output.get("height"), 1, MAX_IMAGE_SIDE) \
				or int(output.width) * int(output.height) > MAX_IMAGE_PIXELS \
				or not _allowed_path("image", str(output.get("image_url", ""))):
			_fail("INVALID_IMAGE_RESULT", "生成图片的格式、尺寸或来源不符合约定。")
			return
		_job["status"] = "downloading"
	job_changed.emit(_job.duplicate(true))
	if serial != _generation or not _active:
		return
	if status == "succeeded":
		_send("image", info.result.image_url, HTTPClient.METHOD_GET)
	else:
		_ensure_timer()
		_poll_timer.start(maxf(0.25, poll_interval))

func _accept_image(response_code: int, headers: PackedStringArray, body: PackedByteArray) -> void:
	if response_code != 200 or _content_type(headers) != "image/png" or body.size() > MAX_IMAGE_BYTES:
		_fail("INVALID_IMAGE", "图片下载返回了不正确的格式。")
		return
	# Read the PNG dimensions before decoding, so a tiny compressed body cannot allocate a huge image.
	var signature := PackedByteArray([137, 80, 78, 71, 13, 10, 26, 10])
	if body.size() < 33 or body.slice(0, 8) != signature or body.slice(12, 16).get_string_from_ascii() != "IHDR":
		_fail("INVALID_IMAGE", "酒图不是有效的 PNG 图片。")
		return
	var width := _big_endian_u32(body, 16)
	var height := _big_endian_u32(body, 20)
	var expected: Dictionary = _job.result
	if width != int(expected.width) or height != int(expected.height) \
			or width < 1 or height < 1 or width > MAX_IMAGE_SIDE or height > MAX_IMAGE_SIDE \
			or width * height > MAX_IMAGE_PIXELS:
		_fail("INVALID_IMAGE_SIZE", "酒图尺寸与生成结果不一致。")
		return
	var image := Image.new()
	if image.load_png_from_buffer(body) != OK or image.is_empty() \
			or image.get_width() != width or image.get_height() != height:
		_fail("IMAGE_DECODE_FAILED", "生成图片无法读取。")
		return
	if image.detect_alpha() == Image.ALPHA_NONE or image.get_used_rect().size == Vector2i.ZERO:
		_fail("IMAGE_NOT_TRANSPARENT", "生成酒图需要保留透明背景和可见的酒杯。")
		return
	var directory := ProjectSettings.globalize_path(IMAGE_DIRECTORY)
	if DirAccess.make_dir_recursive_absolute(directory) != OK:
		_fail("IMAGE_SAVE_FAILED", "酒图文件夹无法创建，请检查存储空间。")
		return
	var path := IMAGE_DIRECTORY.path_join("%s-r%d-%s.png" % [_recipe_id, _revision, _task_id])
	# Never replace an existing file, even for an idempotent task replay.
	if FileAccess.file_exists(path):
		var previous := FileAccess.get_file_as_bytes(path)
		if previous != body:
			_fail("IMAGE_FILE_CONFLICT", "这份酒图已经保存，请保留原图后重试。")
			return
	else:
		var temporary := path + ".part"
		var file := FileAccess.open(temporary, FileAccess.WRITE)
		if file == null:
			_fail("IMAGE_SAVE_FAILED", "酒图未能保存，请检查存储空间。")
			return
		file.store_buffer(body)
		file.flush()
		var error := file.get_error()
		file.close()
		if error != OK or DirAccess.rename_absolute(ProjectSettings.globalize_path(temporary), ProjectSettings.globalize_path(path)) != OK:
			DirAccess.remove_absolute(ProjectSettings.globalize_path(temporary))
			_fail("IMAGE_SAVE_FAILED", "酒图未能保存，请重试。")
			return
	var texture := ImageTexture.create_from_image(image)
	_active = false
	_job["status"] = "succeeded"
	_job["local_path"] = path
	var serial := _generation
	var recipe_id := _recipe_id
	var revision := _revision
	var completed := _job.duplicate(true)
	job_changed.emit(completed.duplicate(true))
	if serial == _generation:
		image_ready.emit(recipe_id, revision, path, texture, completed)

func _allowed_path(kind: String, path: String) -> bool:
	if kind == "submit":
		return path == JOBS_PATH
	if not _safe_id(_task_id, 100):
		return false
	var job_path := JOBS_PATH + "/" + _task_id
	return path == (job_path + "/image" if kind == "image" else job_path)

func _valid_origin(value: String) -> String:
	var origin := value.strip_edges().trim_suffix("/")
	return origin if _matches(origin, "^https?://([A-Za-z0-9.-]+|\\[[0-9A-Fa-f:]+\\])(:[0-9]{1,5})?$") else ""

func _safe_id(value: Variant, maximum: int) -> bool:
	return value is String and value.length() >= 1 and value.length() <= maximum \
		and _matches(value, "^[A-Za-z0-9_-]+$")

func _whole_number(value: Variant, minimum: int, maximum: int) -> bool:
	return (value is int or value is float) and is_finite(float(value)) \
		and value == floor(float(value)) and value >= minimum and value <= maximum

func _matches(value: String, pattern: String) -> bool:
	var regex := RegEx.new()
	return regex.compile(pattern) == OK and regex.search(value) != null

func _uuid_v4() -> String:
	var bytes := Crypto.new().generate_random_bytes(16)
	bytes[6] = (bytes[6] & 15) | 64
	bytes[8] = (bytes[8] & 63) | 128
	var hex := bytes.hex_encode()
	return "%s-%s-%s-%s-%s" % [hex.substr(0, 8), hex.substr(8, 4), hex.substr(12, 4), hex.substr(16, 4), hex.substr(20, 12)]

func _big_endian_u32(bytes: PackedByteArray, offset: int) -> int:
	return (int(bytes[offset]) << 24) | (int(bytes[offset + 1]) << 16) \
		| (int(bytes[offset + 2]) << 8) | int(bytes[offset + 3])

func _content_type(headers: PackedStringArray) -> String:
	for header: String in headers:
		if header.to_lower().begins_with("content-type:"):
			return header.substr(header.find(":") + 1).strip_edges().split(";")[0].to_lower()
	return ""

func _service_failure(info: Dictionary, fallback: String) -> void:
	var error: Variant = info.get("error", {})
	if not error is Dictionary:
		error = {}
	_fail(str(error.get("code", fallback)).left(100),
		str(error.get("message", "酒图暂时未能生成，请稍后重试。")).left(500), bool(error.get("retryable", false)))

func _reject(code: String, message: String, error: Error) -> Error:
	generation_failed.emit(code, message)
	return error

func _fail(code: String, message: String, retryable := false) -> void:
	var serial := _generation
	_active = false
	_stop_requests()
	_job["status"] = "failed"
	_job["error"] = {"code": code, "message": message, "retryable": retryable}
	job_changed.emit(_job.duplicate(true))
	if serial == _generation:
		generation_failed.emit(code, message)

func _stop_requests() -> void:
	if is_instance_valid(_poll_timer):
		_poll_timer.stop()
	if is_instance_valid(_http):
		_http.cancel_request()
		_release_http(_http)

func _release_http(http: HTTPRequest) -> void:
	if not is_instance_valid(http):
		return
	if http == _http:
		if _completion_handler.is_valid() and http.request_completed.is_connected(_completion_handler):
			http.request_completed.disconnect(_completion_handler)
		_http = null
		_completion_handler = Callable()
	http.queue_free()
