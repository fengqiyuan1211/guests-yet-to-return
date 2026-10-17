extends Node2D
## Independent guest art, profiles and shuffle bag. Background always stays empty.
signal guest_spawned(profile: Dictionary)
signal guest_cleared
signal yellow_laugh_finished
const DATA_PATH := "res://data/guests.json"
# The rear edge of the foreground counter in the 1600 × 900 home layout.
# Guests stand behind it; lower bodies must never render onto the tabletop.
const COUNTER_EDGE_Y := 600.0
const GUEST_TOP_Y := 135.0
var profiles: Array = []
var rng := RandomNumberGenerator.new()
var spawned_profile: Dictionary = {}
var _bag: Array[int] = []
var _last_id := ""
var _window: Control
var _art: TextureRect
var _arrival: Tween
var _elapsed := 0.0
var _laugh: Node2D
var _textures: Dictionary = {}

func _ready() -> void:
	rng.randomize()
	var data = JSON.parse_string(FileAccess.get_file_as_string(DATA_PATH))
	if data is Array:
		profiles = data
	for profile in profiles:
		_textures[profile.id] = load(profile.texture)

func _can_arrive(index: int) -> bool:
	if index < 0 or index >= profiles.size(): return false
	if PlayModes.mode=="mixing" and not StoryDialogue.is_known(str(profiles[index].id)): return false
	if profiles[index].id != "stick": return true
	return not WorkbenchSession.research_state().get("story_items", {}).get("item_recipe_after_school", {}).get("owned", false)

func spawn_random_guest() -> Dictionary:
	if profiles.is_empty():
		return {}
	# Filter restored/partly consumed bags too: the reward may have been won mid-group.
	_bag.assign(_bag.filter(func(index: int): return _can_arrive(index)))
	if _bag.is_empty():
		for i in range(profiles.size()):
			if _can_arrive(i): _bag.append(i)
		if _bag.is_empty(): return {}
		for i in range(_bag.size() - 1, 0, -1):
			var j := rng.randi_range(0, i)
			var temp := _bag[i]
			_bag[i] = _bag[j]
			_bag[j] = temp
		# Each group contains eligible guests once, with no repeat at the boundary.
		if _bag.size() > 1 and profiles[_bag.back()].id == _last_id:
			var temp := _bag[0]
			_bag[0] = _bag[-1]
			_bag[-1] = temp
	return show_guest(int(_bag.pop_back()))

func show_guest(index: int) -> Dictionary:
	# Explicit restoration keeps the current farewell/reward scene until the guest leaves.
	# Retirement only prevents future random arrivals.
	if index < 0 or index >= profiles.size():
		return {}
	_clear_art()
	spawned_profile = profiles[index].duplicate(true)
	_last_id = spawned_profile.id
	_window = Control.new()
	_window.name = "GuestWindow"
	_window.position = Vector2(350, GUEST_TOP_Y)
	_window.size = Vector2(790, COUNTER_EDGE_Y - GUEST_TOP_Y)
	_window.clip_contents = true
	_window.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_window)
	_art = TextureRect.new()
	_art.name = "GuestArt"
	_art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_art.texture = _textures[spawned_profile.id]
	_art.size = Vector2(400, 600)
	_art.position = Vector2(195, 0)
	_art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_window.add_child(_art)
	_elapsed = 0.0
	_window.modulate.a = 0.0
	_window.position.x += 32
	_arrival = create_tween().set_parallel(true)
	_arrival.tween_property(_window, "modulate:a", 1.0, 0.32)
	_arrival.tween_property(_window, "position:x", 350.0, 0.4).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	guest_spawned.emit(spawned_profile.duplicate(true))
	return spawned_profile.duplicate(true)

func portrait_texture(profile: Dictionary) -> Texture2D:
	var portrait := AtlasTexture.new()
	portrait.atlas = _textures[profile.id]
	var r: Array = profile.portrait
	portrait.region = Rect2(r[0], r[1], r[2], r[3])
	portrait.filter_clip = true
	return portrait

func _process(delta: float) -> void:
	if is_instance_valid(_art) and visible:
		_elapsed += delta
		_art.position.y = sin(_elapsed * 1.4) * 1.5

func _clear_art() -> void:
	stop_yellow_laugh()
	if _arrival and _arrival.is_valid():
		_arrival.kill()
	if is_instance_valid(_window):
		remove_child(_window)
		_window.queue_free()
	_window = null
	_art = null

func clear_guest() -> void:
	_clear_art()
	spawned_profile = {}
	guest_cleared.emit()

func yellow_laugh_active() -> bool:
	return is_instance_valid(_laugh) and _laugh.active

func play_yellow_laugh() -> bool:
	if spawned_profile.get("id") != "yellow_creature" or not is_instance_valid(_art) or yellow_laugh_active(): return false
	_laugh = preload("res://scripts/yellow_laugh.gd").new()
	_laugh.position = Vector2(195, 0)
	_laugh.finished.connect(_finish_yellow_laugh)
	_art.hide()
	_window.add_child(_laugh)
	return true

func stop_yellow_laugh() -> void:
	if is_instance_valid(_laugh): _laugh.stop()

func _finish_yellow_laugh() -> void:
	_laugh = null
	if is_instance_valid(_art): _art.show()
	yellow_laugh_finished.emit()
