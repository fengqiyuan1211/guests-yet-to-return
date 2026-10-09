extends Node
## Authored story -> small talk -> departure. Order/mixing remains independent.
signal changed
signal story_finished(guest_id: String, episode_id: String)
signal smalltalk_requested(guest_id: String, context: Dictionary)
const DATA_ROOT := "res://data/story_dialogues/"
var catalog: Dictionary = {}
var introductions: Dictionary = {}
var smalltalk: Dictionary = {}
var progress: Dictionary = {}
var guest_id := ""
var episode: Dictionary = {}
var node_id := ""
var phase := "none"
var speech := ""
var idle_index := -1
var taste_event_id := ""
var history: Array = []
var save_path := "user://story_progress.json"
var last_error := ""
var writable := true
var revision := 0

func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--dialogue-save="):
			save_path = arg.trim_prefix("--dialogue-save=")
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(DATA_ROOT + "manifest.json"))
	introductions = JSON.parse_string(FileAccess.get_file_as_string("res://data/guest_introductions.json"))
	for character in manifest.characters:
		var chapters: Array = []
		for item in character.episodes:
			var path: String = DATA_ROOT + String(item.file)
			var chapter: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(path))
			if int(chapter.episode) == 1 and introductions.has(character.guest_id):
				var intro: Dictionary = introductions[character.guest_id]
				chapter.story_entry = chapter.entry
				chapter.nodes["_greeting"] = {"text": intro.greeting, "choices": [{"id": str(chapter.id) + ".ask_name", "text": intro.question, "next": "_introduction"}]}
				chapter.nodes["_introduction"] = {"text": intro.introduction, "next": chapter.entry, "reveals_identity": true}
				chapter.entry = "_greeting"
			elif character.guest_id == "yellow_creature":
				chapter.nodes.handoff.reveals_identity = true
			var taste_cfg: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://data/guest_service.json"))
			if taste_cfg.events.has(chapter.id):
				for closing_id in chapter.nodes.keys():
					var closing: Dictionary=chapter.nodes[closing_id]
					if closing.has("transition"):
						chapter.nodes["_taste"]={"speaker":"guest","text":taste_cfg.events[chapter.id].request_text,"taste_event":chapter.id,"transition":closing.transition}
						closing.erase("transition")
						closing.next="_taste"
			chapters.append(chapter)
		catalog[character.guest_id] = chapters
	smalltalk = JSON.parse_string(FileAccess.get_file_as_string("res://data/guest_smalltalk.json"))
	load_progress()

func load_progress() -> void:
	progress = {}
	writable = true
	last_error = ""
	if not FileAccess.file_exists(save_path):
		return
	var data = JSON.parse_string(FileAccess.get_file_as_string(save_path))
	if not _valid_save(data):
		writable = false
		last_error = "对话存档无法读取，本次进度暂不保存。"
		return
	progress = data.guests

func _valid_save(data: Variant) -> bool:
	if not data is Dictionary or data.get("version") != 1 or not data.get("guests") is Dictionary:
		return false
	for key in data.guests:
		if not catalog.has(key):
			return false
		var state = data.guests[key]
		if not state is Dictionary or not state.get("completed") is float and not state.get("completed") is int:
			return false
		var done: float = state.completed
		if done < 0 or done > catalog[key].size() or done != floor(done) or not state.get("heard", {}) is Dictionary:
			return false
		if state.has("known") and not state.known is bool:
			return false
		if not state.get("archive", []) is Array or not state.get("activity_unlocks", {}) is Dictionary:
			return false
		for line in state.get("archive", []):
			if not line is Dictionary or not line.get("key") is String or not line.get("text") is String or line.get("speaker") not in ["guest", "player"]:
				return false
		for activity in state.get("activity_unlocks", {}):
			if not activity is String or not state.activity_unlocks[activity] is String: return false
		var pending = state.get("pending", {})
		if not pending is Dictionary:
			return false
		if not pending.is_empty():
			if int(done) >= catalog[key].size():
				return false
			var chapter: Dictionary = catalog[key][int(done)]
			if pending.get("episode_id") != chapter.id or not chapter.nodes.has(pending.get("node", "")) or not pending.get("history") is Array:
				return false
	return true

func _save() -> void:
	if not writable:
		return
	var file := FileAccess.open(save_path + ".tmp", FileAccess.WRITE)
	if file == null:
		last_error = "对话进度保存失败，请检查存储空间。"
		return
	file.store_string(JSON.stringify({"version": 1, "guests": progress}, "\t"))
	file.flush()
	var error := file.get_error()
	file.close()
	if error != OK or DirAccess.rename_absolute(ProjectSettings.globalize_path(save_path + ".tmp"), ProjectSettings.globalize_path(save_path)) != OK:
		last_error = "对话进度保存失败，请检查存储空间。"
	else:
		last_error = ""

func _state() -> Dictionary:
	if not progress.has(guest_id):
		progress[guest_id] = {"completed": 0, "pending": {}, "heard": {}, "known": false}
	return progress[guest_id]

func is_known(id: String) -> bool:
	var state: Dictionary = progress.get(id, {})
	# Existing saves from before introductions keep the people already met.
	return state.get("known", int(state.get("completed", 0)) > 0 or not state.get("pending", {}).is_empty() or not state.get("heard", {}).is_empty())

func start_guest(id: String) -> void:
	end_guest()
	guest_id = id
	idle_index = -1
	history = []
	if not catalog.has(id):
		phase = "idle"
		_chat()
		return
	var state := _state()
	var done := int(state.completed)
	if id == "yellow_creature":
		done = 0
	if done >= catalog[id].size():
		phase = "idle"
		episode = {}
		_chat()
		return
	episode = catalog[id][done]
	phase = "story"
	var pending: Dictionary = state.get("pending", {})
	if not pending.is_empty() and pending.get("episode_id") == episode.id:
		history = pending.get("history", []).duplicate(true)
		_show_node(pending.node, false)
	else:
		_show_node(episode.get("story_entry", episode.entry) if is_known(id) else episode.entry)

func _show_node(id: String, record := true) -> void:
	node_id = id
	var node: Dictionary = episode.nodes[id]
	if node.get("reveals_identity", false):
		_state().known = true
	if not node.has("text"):
		_finish_story()
		return
	speech = node.text
	if node.has("taste_event"):
		taste_event_id=str(node.taste_event)
		var locked: Dictionary=GuestService.ledger().demands.get(GuestService.current_visit(),{})
		if not locked.is_empty(): speech=str(locked.get("request_text",speech))+" 这一杯就按刚才说的来。"
	if record:
		history.append({"speaker": "guest", "node": id, "text": speech})
		_archive_line(episode.id, history.back())
	_state().pending = {"episode_id": episode.id, "node": id, "history": history.duplicate(true)}
	_save()
	revision += 1
	changed.emit()

func choose(choice_id: String, expected_revision: int) -> bool:
	if phase != "story" or expected_revision != revision:
		return false
	var node: Dictionary = episode.nodes[node_id]
	for choice in node.get("choices", []):
		if choice.id == choice_id:
			history.append({"speaker": "player", "choice_id": choice.id, "text": choice.text})
			_archive_line(episode.id, history.back())
			_show_node(choice.next)
			return true
	return false

func continue_talking() -> void:
	if phase == "idle":
		if guest_id == "yellow_creature":
			phase = "story"
			episode = catalog[guest_id][0]
			history = []
			_show_node(episode.entry)
		else:
			_chat()
	elif phase == "story":
		var node: Dictionary = episode.nodes[node_id]
		if node.has("next"):
			_show_node(node.next)
		elif node.has("transition"):
			_finish_story()

func _finish_story() -> void:
	var state := _state()
	if guest_id != "yellow_creature":
		state.completed = maxi(int(state.completed), int(episode.episode))
	state.pending = {}
	state.heard[episode.id] = history.duplicate(true)
	_save()
	phase = "idle"
	idle_index = -1
	# Keep the closing line until the player asks to chat; no automatic departure.
	revision += 1
	story_finished.emit(guest_id, episode.id)
	changed.emit()

func _chat() -> void:
	var lines: Array = smalltalk.get(guest_id, ["我在这儿坐会儿。"])
	idle_index = (idle_index + 1) % lines.size()
	speech = lines[idle_index]
	if idle_index==0 and guest_id in ["milo","ada","hank"]:
		var cfg: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://data/guest_service.json"))
		var request: String=cfg.events.get(taste_event_id,cfg.profiles.get(guest_id,{})).get("request_text","")
		var locked: Dictionary=GuestService.ledger().demands.get(GuestService.current_visit(),{})
		if not locked.is_empty(): request=locked.get("request_text",request)
		if not request.is_empty(): speech=request
	_archive_line("smalltalk", {"speaker":"guest", "node":str(idle_index), "text":speech})
	_save()
	revision += 1
	changed.emit()
	# Local lines work now; a future AI provider can respond using this stable context.
	smalltalk_requested.emit(guest_id, {"revision": revision, "history": _state().heard.duplicate(true)})

func end_guest() -> void:
	taste_event_id = ""
	guest_id = ""
	phase = "none"
	episode = {}
	node_id = ""
	speech = ""
	history = []
	revision += 1

func current_choices() -> Array:
	if phase != "story":
		return []
	return episode.nodes[node_id].get("choices", []).duplicate(true)

func session_snapshot() -> Dictionary:
	return {"guest_id": guest_id, "episode_id": episode.get("id", ""), "node_id": node_id,
		"phase": phase, "taste_event_id":taste_event_id, "speech": speech, "idle_index": idle_index, "history": history.duplicate(true)}

func valid_session(data: Variant) -> bool:
	if not data is Dictionary:
		return false
	if data.get("phase") == "none":
		return data.get("guest_id", "") is String and data.get("guest_id", "").is_empty()
	if not catalog.has(data.get("guest_id", "")) or not data.get("phase") in ["story", "idle"]:
		return false
	if not data.get("taste_event_id","") is String: return false
	if not data.get("speech") is String or not data.get("history") is Array:
		return false
	var found: Dictionary = {}
	for chapter in catalog[data.guest_id]:
		if chapter.id == data.get("episode_id"):
			found = chapter
	if data.phase == "story" and (found.is_empty() or not found.nodes.has(data.get("node_id", ""))):
		return false
	return data.get("idle_index") is float or data.get("idle_index") is int

func restore_session(data: Dictionary) -> void:
	end_guest()
	guest_id = data.get("guest_id", "")
	taste_event_id = data.get("taste_event_id", "")
	phase = data.get("phase", "none")
	speech = data.get("speech", "")
	node_id = data.get("node_id", "")
	idle_index = int(data.get("idle_index", -1))
	history = data.get("history", []).duplicate(true)
	for chapter in catalog.get(guest_id, []):
		if chapter.id == data.get("episode_id"):
			episode = chapter

func progress_label() -> String:
	# Story bookkeeping stays internal; only an actionable save failure needs a notice.
	return last_error

## Only observed lines are archived. Stable node/choice IDs preserve different branches.
func _archive_line(chapter_id: String, line: Dictionary) -> void:
	var state := _state()
	if not state.has("archive"): state.archive = []
	var key := chapter_id + ":" + str(line.speaker) + ":" + str(line.get("choice_id", line.get("node", line.text)))
	for existing in state.archive:
		if existing.key == key: return
	var entry := line.duplicate(true)
	entry.key = key
	entry.chapter_id = chapter_id
	entry.day = TimeManager.day
	state.archive.append(entry)

## Called by an authored story reward, never by opening the journal.
func unlock_activity(id: String, activity_id: String, source_event: String) -> bool:
	if not writable or not catalog.has(id) or source_event.is_empty(): return false
	var config: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/guest_activities.json"))
	if not config.get(id, {}).has(activity_id): return false
	var previous := progress.duplicate(true)
	if not progress.has(id): progress[id] = {"completed":0, "pending":{}, "heard":{}, "known":false}
	if not progress[id].has("activity_unlocks"): progress[id].activity_unlocks = {}
	if progress[id].activity_unlocks.has(activity_id): return true
	progress[id].activity_unlocks[activity_id] = source_event
	_save()
	if not last_error.is_empty():
		progress = previous
		return false
	changed.emit()
	return true
