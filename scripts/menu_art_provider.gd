extends Node
## A provider adapter can be attached later without putting provider secrets in the game.
signal availability_changed
signal generation_started(request_id: int)
signal generation_finished(request_id: int, image_path: String)
signal generation_failed(request_id: int, message: String)

var adapter: Callable
var request_id := 0
var busy := false
var last_payload: Dictionary = {}

func configure_provider(callback: Callable) -> void:
	adapter = callback
	availability_changed.emit()

func is_available() -> bool:
	return adapter.is_valid()

func build_request(prompt: String, drinks: Array, title: String, subtitle: String) -> Dictionary:
	return {"schema_version": 1, "style_prompt": prompt.strip_edges().left(600),
		"title": title, "subtitle": subtitle, "selected_drinks": drinks.duplicate(true),
		"canvas": {"width": 1024, "height": 1536}, "render_mode": "background_only",
		"text_safe_area": {"x": 0.12, "y": 0.16, "w": 0.76, "h": 0.68}}

func generate(payload: Dictionary) -> int:
	if busy or not is_available():
		return -1
	request_id += 1
	busy = true
	last_payload = payload.duplicate(true)
	last_payload["request_id"] = request_id
	generation_started.emit(request_id)
	adapter.call_deferred(request_id, last_payload.duplicate(true))
	return request_id

func complete(id: int, result: Image) -> void:
	if id != request_id or not busy:
		return
	if result == null or result.is_empty() or result.get_width() > 4096 or result.get_height() > 4096:
		fail(id, "画稿没能展开，再请画师画一张吧。")
		return
	var path := MenuCatalog.save_path + ".art-%d.png" % Time.get_ticks_usec()
	if result.save_png(path) != OK:
		fail(id, "画稿未能保存，请检查存储空间。")
		return
	busy = false
	generation_finished.emit(id, path)

func fail(id: int, message: String) -> void:
	if id != request_id or not busy:
		return
	busy = false
	generation_failed.emit(id, message.left(160))

func cancel() -> void:
	request_id += 1
	busy = false
