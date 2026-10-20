extends Node
## Durable sale intent -> idempotent wallet credit -> review -> short feedback.
signal changed
const Evaluation := preload("res://scripts/customer_evaluation.gd")
const MemoryProgress := preload("res://scripts/stick_memory_progress.gd")
const LEGACY_RULES := "res://data/guest_mechanics/settlement_rules_legacy_v1.json"
const Buffs := preload("res://scripts/cocktail_buffs.gd")
const FreeOrder := preload("res://scripts/free_drink_order.gd")
var rules: Dictionary
var profiles: Dictionary = {}
var events: Array = []
var state: Dictionary = {"version": 1, "active": {}, "deliveries": {}, "last_drinks": {}}
var save_path := "user://customer_service.json"
var endpoint := "http://127.0.0.1:8788/feedback"
var writable := true
var last_error := ""
var request: HTTPRequest
var generation := 0
var waiting_for_service := false

func _ready() -> void:
	StoryDialogue.story_finished.connect(_on_story_finished)
	rules = JSON.parse_string(FileAccess.get_file_as_string("res://data/guest_mechanics/settlement_rules.json"))
	if rules.get("sensory", {}) is Dictionary:
		rules.sensory = Evaluation.resolved_sensory(rules)
	if not Evaluation.rules_valid(rules):
		writable = false
		last_error = "评分配置 settlement_rules.json 不完整，请保留存档。"
		return
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://data/guest_mechanics/guest_profiles.json"))
	if not data is Dictionary or data.get("schema_version") != 1 or not data.get("profiles") is Array:
		writable = false
		last_error = "客人偏好 guest_profiles.json 的格式或版本无法读取。"
		return
	for profile: Variant in data.profiles:
		if not profile is Dictionary or not profile.get("guest_id") is String or profiles.has(profile.guest_id) or not _profile_valid(profile):
			writable = false
			last_error = "guest_profiles.json 包含缺失、无效或重复的客人偏好。"
			return
		profiles[profile.guest_id] = profile
	var event_data: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://data/guest_mechanics/visit_events.json"))
	if not event_data is Dictionary or event_data.get("schema_version") != 1 or not event_data.get("events") is Array:
		writable = false
		last_error = "来访事件 visit_events.json 的格式或版本无法读取。"
		return
	var event_ids: Dictionary = {}
	var episode_events: Dictionary = {}
	for event: Variant in event_data.events:
		if not event is Dictionary or not event.get("event_id") is String or event_ids.has(event.event_id) or not profiles.has(event.get("guest_id")) or not event.get("story_episode_id") is String or not _delta_valid(event.get("preference_delta", {})) or not event.get("buff_affinity_overrides", {}) is Dictionary or not event.get("soft_state_penalty_additions", []) is Array:
			writable = false
			last_error = "visit_events.json 包含无效或重复事件。"
			return
		var chapter_exists := false
		for chapter: Dictionary in StoryDialogue.catalog.get(event.guest_id, []): chapter_exists = chapter_exists or chapter.id == event.story_episode_id
		var key := str(event.guest_id) + ":" + str(event.story_episode_id)
		if not chapter_exists or episode_events.has(key):
			writable = false
			last_error = "visit_events.json 的故事引用不存在，或一章配置了多个主要事件。"
			return
		for points: Variant in event.get("buff_affinity_overrides", {}).values():
			if not Evaluation.number(points):
				writable = false
				last_error = "visit_events.json 的 Buff 亲和度必须是非负有限数值。"
				return
		event_ids[event.event_id] = true
		episode_events[key] = true
	events = event_data.events
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--slot-wallet="): save_path = arg.trim_prefix("--slot-wallet=") + ".customers"
		if arg.begins_with("--feedback-url="): endpoint = arg.trim_prefix("--feedback-url=")
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--customer-save="): save_path = arg.trim_prefix("--customer-save=")
	if FileAccess.file_exists(save_path):
		var loaded: Variant = JSON.parse_string(FileAccess.get_file_as_string(save_path))
		if not _valid_saved_state(loaded):
			writable = false
			last_error = "客人的记录未能读取，请保留存档。"
			return
		state = loaded
		for id in state.deliveries:
			if not state.deliveries[id] is Dictionary or state.deliveries[id].get("status") not in ["prepared", "settled"]:
				writable = false
				last_error = "客人的结算记录不完整，请保留存档。"
				return
	if not _cap_saved_scores(): return
	for id in state.deliveries:
		if state.deliveries[id].status == "prepared": _commit_delivery(str(id))

# The 100-point ceiling also applies to reviews made before this display rule.
# Keep receipts, cup signatures, preferences and individual modifiers unchanged.
func _cap_saved_scores() -> bool:
	var changed_score := false
	for record: Dictionary in state.deliveries.values():
		var review: Dictionary = record.review
		if review.get("satisfaction") != null and float(review.satisfaction) > 100:
			review.satisfaction = 100.0
			changed_score = true
	if changed_score and not _write():
		writable = false
		return false
	return true

func _number(value: Variant, minimum: float, maximum: float) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and float(value) >= minimum and float(value) <= maximum

func _delta_valid(value: Variant) -> bool:
	if not value is Dictionary: return false
	for key: Variant in value:
		if key not in Evaluation.ATTRS or not Evaluation.number(value[key], -INF): return false
	return true

func _profile_valid(profile: Dictionary) -> bool:
	if not StoryDialogue.catalog.has(profile.guest_id) or not profile.get("profile_version") is String or not _delta_valid(profile.get("permanent_delta", {})): return false
	return Evaluation.demand_valid({"target":profile.get("base_preferences"), "weights":profile.get("weights"), "tolerances":profile.get("tolerances"), "constraints":profile.get("constraints", []), "soft_state_penalties":profile.get("soft_state_penalties", []), "buff_affinities":profile.get("buff_affinities", {})})

func _valid_saved_state(data: Variant) -> bool:
	if not data is Dictionary or data.get("version") != 1 or not data.get("active") is Dictionary or not data.get("deliveries") is Dictionary or not data.get("last_drinks") is Dictionary: return false
	var memory: Variant = data.get("memory_dialogue", {})
	if not memory is Dictionary: return false
	for key in ["intro_step", "reward_step"]:
		if not _number(memory.get(key, 0), 0, 2) or float(memory.get(key, 0)) != floor(float(memory.get(key, 0))): return false
	if not memory.get("reward_seen", false) is bool or not memory.get("reward_visit_id", "") is String: return false
	var active: Dictionary = data.active
	if not active.is_empty():
		for key in ["id", "guest_id", "delivery_id"]:
			if not active.get(key) is String: return false
		for key in ["profile", "demand", "order"]:
			if not active.get(key) is Dictionary: return false
		if not profiles.has(active.guest_id) or active.profile.get("id") != active.guest_id: return false
		if not _number(active.get("day"), 1, 1000000000) or not _number(active.get("visit"), 1, 1000000000): return false
		if active.has("story_completed") and not active.story_completed is bool: return false
		if active.has("story_episode_id") and not active.story_episode_id is String: return false
		if active.has("rules_snapshot") and (not active.rules_snapshot is Dictionary or not Evaluation.rules_valid(active.rules_snapshot)): return false
		if not active.delivery_id.is_empty() and not data.deliveries.has(active.delivery_id): return false
	for id in data.deliveries:
		var record: Variant = data.deliveries[id]
		if not id is String or not record is Dictionary or record.get("id") != id or record.get("status") not in ["prepared", "settled"]: return false
		if not profiles.has(record.get("guest_id")) or not _number(record.get("amount"), 0, 1000000000) or float(record.amount) != floor(float(record.amount)): return false
		if record.has("story_completed") and not record.story_completed is bool: return false
		if record.has("story_episode_id") and not record.story_episode_id is String: return false
		if record.has("visit_serial") and (not _number(record.visit_serial, 1, 1000000000) or record.visit_serial != floor(record.visit_serial)): return false
		if record.has("visit_id") and (not record.visit_id is String or record.visit_id.is_empty() or not str(id).begins_with(record.visit_id + ":")): return false
		if record.has("cup_signature") and (not record.cup_signature is String or record.cup_signature.length() != 64): return false
		if record.has("cup_signature_format") and record.cup_signature_format != "json-roundtrip-v2": return false
		for key in ["actual", "review", "feedback", "previous_drink", "demand"]:
			if not record.get(key) is Dictionary: return false
		var feedback: Dictionary = record.feedback
		if not _number(feedback.get("round"), 0, 3) or float(feedback.round) != floor(float(feedback.round)): return false
		if not feedback.get("pending") is bool or not feedback.get("done") is bool or not feedback.get("messages") is Array or feedback.messages.size() > 6 or not feedback.get("pending_reply") is String: return false
		if feedback.has("story_resumed") and (not feedback.story_resumed is bool or (feedback.story_resumed and (not feedback.done or feedback.pending))): return false
		if not feedback.get("turn") is Dictionary: return false
		if int(feedback.round) > 0 and not _valid_turn(feedback.turn, int(feedback.round)): return false
		for message in feedback.messages:
			if not message is Dictionary or message.get("speaker") not in ["guest", "player"] or not message.get("text") is String: return false
		if record.review.get("status") not in ["scored", "rejected", "data_incomplete"]: return false
		if record.review.get("satisfaction") != null and not _number(record.review.satisfaction, 0, INF): return false
		if record.has("craft") and not record.craft is Dictionary: return false
		if record.get("craft", {}).get("score") != null and not _number(record.craft.score, 0, 100): return false
		if record.review.get("stars") != null and (not _number(record.review.stars, 1, 5) or float(record.review.stars) != floor(float(record.review.stars))): return false
	return true

func _write() -> bool:
	if not writable: return false
	var file := FileAccess.open(save_path + ".tmp", FileAccess.WRITE)
	if file == null:
		last_error = "客人的记录未能保存，请重试。"
		return false
	file.store_string(JSON.stringify(state))
	file.flush()
	var error := file.get_error()
	file.close()
	if error != OK or DirAccess.rename_absolute(ProjectSettings.globalize_path(save_path + ".tmp"), ProjectSettings.globalize_path(save_path)) != OK:
		last_error = "客人的记录未能保存，请重试。"
		return false
	last_error = ""
	return true

func _cancel_request() -> void:
	generation += 1
	waiting_for_service = false
	if is_instance_valid(request):
		request.cancel_request()
		request.queue_free()
	request = null

func _rules_snapshot(source: Dictionary) -> Dictionary:
	var snapshot := source.duplicate(true)
	snapshot.sensory = Evaluation.resolved_sensory(source)
	snapshot.sensory["ingredient_facts"] = {}
	for item: Dictionary in Supplies.catalog.list_items():
		if item.get("kind") == "ingredient": snapshot.sensory.ingredient_facts[item.id] = {"contains_alcohol":item.get("contains_alcohol")}
	if Evaluation.scoring(snapshot).version != "guest-match-playtest-1" and FileAccess.file_exists("res://data/guest_mechanics/buffs.json"):
		snapshot["buff_rules"] = JSON.parse_string(FileAccess.get_file_as_string("res://data/guest_mechanics/buffs.json"))
		if snapshot.buff_rules is Dictionary and snapshot.buff_rules.get("recipes") is Dictionary:
			for recipe_id in snapshot.buff_rules.recipes:
				var reference := MenuCatalog.get_recipe(str(recipe_id))
				if not reference.is_empty():
					reference["unlocked"] = true
					snapshot.buff_rules.recipes[recipe_id]["allowed_versions"] = [WorkbenchSession.recipe_snapshot(reference).version]
	return snapshot

func _ensure_rules_snapshot() -> bool:
	if state.active.has("rules_snapshot"):
		if state.active.rules_snapshot is Dictionary and Evaluation.rules_valid(state.active.rules_snapshot): return true
		last_error = "本次订单的评分规则不完整，请保留酒杯和记录。"
		return false
	var locked: bool = not state.active.get("order", {}).is_empty()
	var source: Variant = JSON.parse_string(FileAccess.get_file_as_string(LEGACY_RULES)) if locked else rules
	if not source is Dictionary or not Evaluation.rules_valid(source):
		last_error = "旧订单的评分规则无法恢复，请保留酒杯和记录。"
		return false
	var previous: Dictionary = state.active.duplicate(true)
	state.active["rules_snapshot"] = _rules_snapshot(source)
	state.active["rules_migration"] = {"source":LEGACY_RULES if locked else "current_rules_before_order", "satisfaction_version":Evaluation.scoring(source).version, "kind":"baseline_v1_locked_order" if locked else "unlocked_visit"}
	if not _write():
		state.active = previous
		return false
	return true

func _effective_demand(source: Dictionary, guest: String, snapshot: Dictionary) -> Dictionary:
	var demand := source.duplicate(true)
	if Evaluation.scoring(snapshot).version == "guest-match-playtest-1": return demand
	# Adapt the old explicit no-alcohol intent without editing the authored profile or its targets.
	if guest == "yellow_creature":
		var constraints: Array = []
		for item: Dictionary in demand.get("constraints", []):
			if item.get("kind") == "max_attribute" and item.get("attribute") == "alcohol_intensity" and item.get("maximum") == 0:
				constraints.append({"id":"yellow_no_alcohol", "kind":"forbid_fact", "scope":"served_contents", "fact":"contains_alcohol", "operator":"eq", "value":true, "on_violation":"reject", "label":item.get("label", "不喝含酒精的饮品"), "legacy_source":item.duplicate(true)})
			else: constraints.append(item)
		demand.constraints = constraints
	return demand

func begin_guest(profile: Dictionary, visit: int, restoring: bool) -> bool:
	if not writable: return false
	if restoring and state.active.get("guest_id") == profile.id and int(state.active.get("day", -1)) == TimeManager.day and int(state.active.get("visit", -1)) == visit:
		if not _ensure_rules_snapshot(): return false
		call_deferred("_resume_feedback")
		return true
	_cancel_request()
	var number := int(StoryDialogue.progress.get(str(profile.id), {}).get("completed", 0)) + 1
	if restoring and StoryDialogue.guest_id == str(profile.id) and not StoryDialogue.episode.is_empty(): number = int(StoryDialogue.episode.get("episode", number))
	var story_number:=number
	var episode_id := "%s_%02d" % [profile.id, number]
	if profile.id == "yellow_creature":
		number = mini(number, StoryDialogue.catalog["yellow_creature"].size())
		episode_id = str(StoryDialogue.catalog["yellow_creature"][number - 1].id)
	var p: Dictionary = profiles[str(profile.id)].duplicate(true)
	var demand: Dictionary = {"target": p.base_preferences.duplicate(true), "weights": p.weights.duplicate(true),
		"tolerances": p.tolerances.duplicate(true), "constraints": p.get("constraints", []).duplicate(true),
		"buff_affinities":p.get("buff_affinities", {}).duplicate(true),
		"soft_state_penalties": p.get("soft_state_penalties", []).duplicate(true), "episode_id": episode_id,
		"mood_note": "", "requested_recipe_id": "", "profile_version": p.profile_version}
	for key in Evaluation.ATTRS: demand.target[key] = clampf(float(demand.target[key]) + float(p.get("permanent_delta", {}).get(key, 0)), 0, 100)
	for event in events:
		if event.guest_id == profile.id and event.story_episode_id == episode_id:
			for key in Evaluation.ATTRS: demand.target[key] = clampf(float(demand.target[key]) + float(event.preference_delta.get(key, 0)), 0, 100)
			demand.soft_state_penalties.append_array(event.get("soft_state_penalty_additions", []))
			demand.mood_note = event.get("mood_note", "")
			demand.requested_recipe_id = event.get("requested_recipe_id", "")
			demand.buff_affinities.merge(event.get("buff_affinity_overrides", {}), true)
	if not Evaluation.demand_valid(demand):
		last_error = "这位客人的口味数据不完整，暂不能创建订单。"
		return false
	demand = _effective_demand(demand, str(profile.id), rules)
	demand["ruleset_manifest"] = {"profile_version":p.profile_version, "sensory_version":rules.sensory.version, "satisfaction_version":Evaluation.scoring(rules).version}
	var previous: Dictionary = state.active.duplicate(true)
	state.active = {"id": Crypto.new().generate_random_bytes(16).hex_encode(), "guest_id": profile.id,
		"day": TimeManager.day, "visit": visit, "demand": demand, "order": {}, "delivery_id": "",
		"profile": profile.duplicate(true), "story_episode_id": episode_id if story_number <= StoryDialogue.catalog.get(str(profile.id), []).size() else "",
		"story_completed": story_number > StoryDialogue.catalog.get(str(profile.id), []).size(), "rules_snapshot":_rules_snapshot(rules)}
	state.active["play_mode"]=PlayModes.mode
	if PlayModes.mode=="mixing":
		state.active.story_episode_id=""
		state.active.story_completed=true
		var menu: Array=[]
		for entry: Dictionary in MenuCatalog.entries:
			var recipe:=MenuCatalog.get_recipe(entry.id)
			if not recipe.is_empty(): menu.append({"id":entry.id,"name":recipe.name,"price":int(entry.price),"tags":recipe.get("tags",[]).duplicate()})
		var rng:=RandomNumberGenerator.new()
		rng.randomize()
		state.active["free_order"]=FreeOrder.create(menu,rng)
	if not _write():
		state.active = previous
		return false
	changed.emit()
	return true

func prepare_order(recipe_id: String) -> Dictionary:
	if not writable or state.active.is_empty() or not TimeManager.is_open or has_delivery(): return {}
	if not _ensure_rules_snapshot(): return {}
	var price := -1
	for entry in MenuCatalog.entries:
		if entry.id == recipe_id: price = int(entry.price)
	if state.active.get("play_mode")=="mixing":
		price=-1
		for entry: Dictionary in state.active.get("free_order",{}).get("menu",[]):
			if entry.id==recipe_id: price=int(entry.price)
	if price < 1: return {}
	var old: Dictionary = state.active.order.duplicate(true)
	var started := int(old.get("started_minute", TimeManager.minutes_since_midnight))
	state.active.order = {"recipe_id": recipe_id, "price": price, "started_minute": started,
		"time_limit_minutes": int(state.active.rules_snapshot.order_time_limit_minutes), "demand": state.active.demand.duplicate(true)}
	if not _write():
		state.active.order = old
		return {}
	var quote := {"visit_id": state.active.id, "recipe_id": recipe_id, "price": price}
	if state.active.rules_snapshot.sensory.version == "sensory-calibrated-1":
		quote["sensory_model"] = state.active.rules_snapshot.sensory.duplicate(true)
	else:
		quote["sensory_legacy"] = true
	return quote

func _on_story_finished(guest: String, chapter_id: String) -> void:
	if state.active.get("guest_id") != guest or state.active.get("story_episode_id", state.active.get("demand", {}).get("episode_id", "")) != chapter_id: return
	var previous := state.duplicate(true)
	state.active.story_completed = true
	state.active.story_episode_id = chapter_id
	var record := current_record()
	if not record.is_empty():
		record.story_completed = true
		record.story_episode_id = chapter_id
		record.story = StoryDialogue.history.duplicate(true)
		record.known = StoryDialogue.is_known(guest)
	if not _write():
		state = previous
		return
	changed.emit()
	call_deferred("_resume_feedback")

func _visit_story_completed() -> bool:
	if state.active.get("story_completed", false): return true
	var chapter_id := str(state.active.get("story_episode_id", state.active.get("demand", {}).get("episode_id", "")))
	var profile: Dictionary = StoryDialogue.progress.get(str(state.active.get("guest_id", "")), {})
	for chapter: Dictionary in StoryDialogue.catalog.get(str(state.active.get("guest_id", "")), []):
		if chapter.id == chapter_id: return int(profile.get("completed", 0)) >= int(chapter.episode) and StoryDialogue.phase != "story"
	return StoryDialogue.phase != "story"

func memory_summary() -> Dictionary:
	return MemoryProgress.summarize(StoryDialogue.progress.get("stick", {}), state.deliveries, {}, GuestService.ledger().deliveries)

func _memory_reception_ready() -> bool:
	if state.active.get("play_mode")=="mixing": return false
	if not writable or state.active.get("guest_id") != "stick" or str(state.active.get("id", "")).is_empty(): return false
	if StoryDialogue.guest_id != "stick" or StoryDialogue.phase != "idle": return false
	var record := current_record()
	# Eligibility belongs to the authored story cups. A later reunion needs no extra purchase.
	if record.is_empty(): return state.active.get("order", {}).is_empty()
	return record.status == "settled" and record.feedback.done and not record.feedback.pending

func can_award_memory(visit_id: String) -> bool:
	return (_memory_reception_ready() and not visit_id.is_empty()
		and state.active.get("id") == visit_id and memory_summary().eligible)

func memory_dialogue_kind() -> String:
	if not _memory_reception_ready() or not memory_summary().eligible: return ""
	var owned: bool = WorkbenchSession.research_state().get("story_items", {}).has("item_recipe_after_school")
	if owned: return "" if state.get("memory_dialogue", {}).get("reward_seen", false) else "reward"
	return "invitation"

func memory_dialogue_step(kind: String) -> int:
	return int(state.get("memory_dialogue", {}).get("reward_step" if kind == "reward" else "intro_step", 0))

func advance_memory_dialogue(kind: String, expected_step: int) -> bool:
	if kind not in ["invitation", "reward"] or memory_dialogue_kind() != kind: return false
	if expected_step != memory_dialogue_step(kind) or expected_step >= 2: return false
	var previous := state.duplicate(true)
	if not state.has("memory_dialogue"): state.memory_dialogue = {}
	state.memory_dialogue["reward_step" if kind == "reward" else "intro_step"] = expected_step + 1
	if not _write():
		state = previous
		return false
	return true

func finish_memory_reward() -> bool:
	if memory_dialogue_kind() != "reward" or memory_dialogue_step("reward") != 2: return false
	var previous := state.duplicate(true)
	state.memory_dialogue.reward_seen = true
	state.memory_dialogue.reward_visit_id = str(state.active.id)
	if not _write():
		state = previous
		return false
	return true

func memory_farewell_active() -> bool:
	var memory: Dictionary = state.get("memory_dialogue", {})
	return (memory.get("reward_seen", false) and not str(state.active.get("id", "")).is_empty()
		and memory.get("reward_visit_id", "") == state.active.get("id"))

func memory_match_context() -> Dictionary:
	var visit_id := str(state.active.get("id", ""))
	return {"mode":"story" if can_award_memory(visit_id) else "practice", "visit_id":visit_id}

func _cup_signature(result: Dictionary) -> String:
	# Godot reads JSON numbers back as floats. Normalize that representation
	# before signing, so an unchanged persisted cup keeps the same fingerprint.
	var normalized: Variant = JSON.parse_string(JSON.stringify(_cup_signature_payload(result)))
	return JSON.stringify(normalized).sha256_text()

func _cup_signature_payload(result: Dictionary) -> Array:
	return [result.get("drink_id"), result.get("guest"), result.get("recipe"), result.get("contents"), result.get("cup"), result.get("actions"), result.get("evaluation")]

func _legacy_cup_signature(result: Dictionary) -> String:
	return JSON.stringify(_cup_signature_payload(result)).sha256_text()

func has_delivery() -> bool:
	return not str(state.active.get("delivery_id", "")).is_empty()

func claim_yellow_laugh(expected_id: String) -> bool:
	# Persist before playback so reloads, duplicate feedback and mode switches cannot repeat it.
	var record := current_record()
	var rules := preload("res://scripts/yellow_laugh_rules.gd")
	if str(record.get("id", "")) != expected_id or not rules.eligible(record): return false
	record[rules.RECEIPT_KEY] = true
	if not _write():
		record.erase(rules.RECEIPT_KEY)
		return false
	return true

func current_record() -> Dictionary:
	return state.deliveries.get(str(state.active.get("delivery_id", "")), {})

func deliver(result: Dictionary) -> bool:
	if not writable or state.active.is_empty() or not TimeManager.is_open:
		last_error = "客人已经离店，这一杯尚未售出。"
		return false
	var drink_id := str(result.get("drink_id", ""))
	var guest: Dictionary = result.get("guest", {})
	if drink_id.is_empty() or guest.get("visit_id") != state.active.id or guest.get("id") != state.active.guest_id:
		last_error = "这一杯不属于当前客人，尚未售出。"
		return false
	var id := "%s:%s" % [state.active.id, drink_id]
	if state.deliveries.has(id):
		if state.deliveries[id].has("cup_signature") and state.deliveries[id].cup_signature not in [_cup_signature(result), _legacy_cup_signature(result)]:
			last_error = "这一杯的记录已经变化，请保留原来的酒。"
			return false
		return _commit_delivery(id)
	if has_delivery() or state.active.order.is_empty() or result.get("recipe", {}).get("id") != state.active.order.recipe_id:
		last_error = "这一桌已经结过账，或者酒款已变更。"
		return false
	if not _ensure_rules_snapshot(): return false
	var session: Dictionary = WorkbenchSession.snapshot().session
	if session.has("order"):
		last_error="这杯使用旧版已锁定订单，请在原交付窗口结算。"
		return false
	var finished: Dictionary = session.get("result", {})
	if session.get("status") != "finished" or finished.get("drink_id") != drink_id or _cup_signature(finished) != _cup_signature(result):
		last_error = "请先完成当前这杯酒，再送给客人。"
		return false
	# Use the durable real workbench cup, including its computed craft score.
	result = finished.duplicate(true)
	var definitions := WorkbenchSession.MATERIALS.duplicate(true)
	definitions.merge(WorkbenchSession.SOLIDS)
	definitions.merge(WorkbenchSession.GARNISHES)
	var snapshot: Dictionary = state.active.rules_snapshot
	var actual := Evaluation.sensory(result, definitions, snapshot)
	if actual.status != "complete":
		last_error = "这一杯缺少必要的感官数据，尚未售出。" if actual.get("reason") != "empty_cup" else "空杯不能送给客人，尚未售出。"
		return false
	var waited := posmod(TimeManager.minutes_since_midnight - int(state.active.order.started_minute), 1440)
	var demand := _effective_demand(state.active.order.demand, str(state.active.guest_id), snapshot)
	var buffs := Buffs.resolve(result, actual, snapshot.get("buff_rules", {}))
	actual["reference_items"]=preload("res://scripts/workbench_evaluation.gd").canonical(session.recipe.ingredients,definitions)
	var review := Evaluation.evaluate(demand, actual, waited > int(state.active.order.time_limit_minutes), snapshot, buffs)
	if review.status == "data_incomplete":
		last_error = "这杯酒的评价缺少必要数据，尚未售出。"
		return false
	if review.status == "rejected":
		for buff: Dictionary in buffs.active: buffs.inactive.append({"id":buff.id, "reason":"hard_constraint_rejected"})
		buffs.active = []
	var serial := 0
	for saved: Dictionary in state.deliveries.values(): serial = maxi(serial, MemoryProgress.sequence(saved))
	var record := {"id": id, "status": "prepared", "guest_id": state.active.guest_id,
		"visit_id":state.active.id, "visit_serial":serial + 1, "cup_signature":_cup_signature(result), "cup_signature_format":"json-roundtrip-v2",
		"story_episode_id":state.active.get("story_episode_id", state.active.demand.episode_id), "story_completed":_visit_story_completed(),
		"day": TimeManager.day, "drink_id": drink_id, "recipe_id": state.active.order.recipe_id,
		"recipe_name": result.get("recipe", {}).get("name", "这一杯"), "amount": int(state.active.order.price),
		"demand": demand, "actual": actual, "review": review, "buffs":buffs, "rules_snapshot":snapshot.duplicate(true),
		"cup": result.duplicate(true),
		"craft": result.get("evaluation", {}).duplicate(true), "waited_minutes": waited,
		"previous_drink": state.last_drinks.get(str(state.active.guest_id), {}).duplicate(true),
		"story": StoryDialogue.history.duplicate(true), "known": StoryDialogue.is_known(str(state.active.guest_id)),
		"feedback": {"round": 0, "pending": false, "pending_reply": "", "messages": [], "turn": {}, "done": false, "story_resumed": false}}
	if state.active.get("play_mode")=="mixing":
		var settlement:=FreeOrder.settle(state.active.free_order,str(result.recipe.id),float(result.get("evaluation",{}).get("score",0)))
		record["play_mode"]="mixing"
		record["free_order"]=state.active.free_order.duplicate(true)
		record["free_settlement"]=settlement
		record.amount=settlement.amount
		record.story_episode_id=""
		record.story_completed=true
		record.story=[]
		record.previous_drink={}
		record.review={"status":"scored" if settlement.matched else "rejected","satisfaction":settlement.craft_score if settlement.matched else 0.0,"stars":clampi(ceili(settlement.craft_score/20.0),1,5) if settlement.matched else 1}
		record.buffs={"active":[],"inactive":[]}
		var text: String={"full":"对，就是我点的这杯。谢谢你！","half":"是我点的酒，不过做得还有些欠缺。这杯我只付一半。","wrong":"这不是我点的酒，这杯我就不付钱了。"}[settlement.tier]
		record.feedback={"round":1,"pending":false,"pending_reply":"","messages":[{"speaker":"guest","text":text}],"turn":{"text":text,"emotion":"pleased" if settlement.tier=="full" else "disappointed","replies":[],"end":true},"done":true,"story_resumed":false}
	if record.get("play_mode")!="mixing":
		record["base_paid"]=int(state.active.order.price) if review.status!="rejected" else 0
		record["tip"]=0
		if review.status=="scored":
			for tier in snapshot.get("tip_tiers",[]):
				if float(review.satisfaction)>=float(tier.min):
					record.tip=roundi(record.base_paid*float(tier.rate)); break
		record.amount=record.base_paid+record.tip
	state.deliveries[id] = record
	state.active.delivery_id = id
	if not _write():
		state.deliveries.erase(id)
		state.active.delivery_id = ""
		return false
	return _commit_delivery(id)

func _commit_delivery(id: String) -> bool:
	var record: Dictionary = state.deliveries[id]
	if record.status == "settled":
		last_error = ""
		_resume_feedback()
		return true
	if int(record.amount)>0 and not SlotWallet.credit_sale(id, int(record.amount)):
		last_error = SlotWallet.last_error
		return false
	record.status = "settled"
	var previous: Dictionary = state.last_drinks.get(str(record.guest_id), {}).duplicate(true)
	if record.get("play_mode")!="mixing": state.last_drinks[record.guest_id] = {"recipe_id": record.recipe_id, "actual": record.actual.duplicate(true), "day": record.day}
	if not _write():
		record.status = "prepared"
		if record.get("play_mode")!="mixing": state.last_drinks[record.guest_id] = previous
		return false # Durable wallet receipt makes retry/recovery safe.
	changed.emit()
	if state.active.get("delivery_id") == id: call_deferred("_resume_feedback")
	return true

func _resume_feedback() -> void:
	var record := current_record()
	if record.is_empty() or record.status != "settled" or is_instance_valid(request): return
	if not record.get("story_completed", false) and _visit_story_completed() and StoryDialogue.episode.get("id") == record.get("story_episode_id", record.demand.episode_id):
		_on_story_finished(str(record.guest_id), str(StoryDialogue.episode.id))
		return
	if record.feedback.done: return
	if record.feedback.pending or int(record.feedback.round) == 0:
		_request_feedback(str(record.feedback.get("pending_reply", "")))

func choose_feedback(index: int, expected_round: int) -> void:
	var record := current_record()
	if record.is_empty() or record.feedback.done or record.feedback.pending or int(record.feedback.round) != expected_round: return
	var replies: Array = record.feedback.turn.get("replies", [])
	if index < 0 or index >= replies.size(): return
	_request_feedback(str(replies[index]))

func resume_served_story(expected_delivery_id: String) -> bool:
	# Resume the existing story cursor only after this cup's feedback is complete.
	# The acknowledgement survives page changes and process restart; it does not
	# complete a chapter, start another one, or create another sale.
	var record := current_record()
	if record.is_empty() or record.id != expected_delivery_id or record.status != "settled" or not record.feedback.done or record.feedback.pending: return false
	if StoryDialogue.guest_id != record.guest_id or StoryDialogue.phase != "story": return false
	if record.feedback.get("story_resumed", false): return true
	record.feedback.story_resumed = true
	if not _write():
		record.feedback.story_resumed = false
		return false
	changed.emit()
	return true

func _request_feedback(reply: String) -> void:
	var record := current_record()
	if record.is_empty() or record.feedback.done or int(record.feedback.round) >= 3 or is_instance_valid(request) or waiting_for_service: return
	var feedback: Dictionary = record.feedback
	feedback.pending = true
	feedback.pending_reply = reply
	if not _write():
		feedback.pending = false
		return
	changed.emit()
	var round_number := int(feedback.round) + 1
	var services:=get_node_or_null("/root/LocalServices")
	if services!=null and not endpoint.is_empty():
		waiting_for_service=true
		var waiting_epoch:=generation
		var ready: bool=await services.ensure_ready("feedback")
		if generation!=waiting_epoch: return
		waiting_for_service=false
		if state.active.get("delivery_id")!=record.id: return
		if not ready:
			_accept_turn(str(record.id),round_number,reply,_fallback(record,round_number))
			return
	var context := {"request_id": record.id + ":%d" % round_number, "round": round_number,
		"guest": {"id": record.guest_id, "name": state.active.profile.name if record.known else "来客",
			"bio": state.active.profile.bio if record.known else "身份尚未介绍，不要自报名字或泄露身份"},
		"story": record.story, "story_completed": record.get("story_completed", StoryDialogue.phase != "story"),
		"demand": record.demand, "drink": {"name": record.recipe_name, "actual": record.actual},
		"previous_drink": record.previous_drink, "craft": record.get("craft", {}), "buffs":record.get("buffs", {}), "review": record.review,
		"history": feedback.messages, "player_reply": reply, "draft_sensory_model": true}
	request = HTTPRequest.new()
	request.timeout = 12.0
	request.body_size_limit = 65536
	add_child(request)
	var epoch := generation
	var delivery_id := str(record.id)
	var current_request := request
	current_request.request_completed.connect(func(status: int, code: int, _headers: PackedStringArray, body: PackedByteArray):
		if generation != epoch or state.active.get("delivery_id") != delivery_id or request != current_request: return
		request = null
		current_request.queue_free()
		var response: Variant = JSON.parse_string(body.get_string_from_utf8()) if status == HTTPRequest.RESULT_SUCCESS and code == 200 else null
		var turn: Dictionary = response.turn if response is Dictionary and response.get("turn") is Dictionary and _valid_turn(response.turn, round_number) else _fallback(record, round_number)
		_accept_turn(delivery_id, round_number, reply, turn)
	, CONNECT_ONE_SHOT)
	if endpoint.is_empty() or current_request.request(endpoint, PackedStringArray(["Content-Type: application/json"]), HTTPClient.METHOD_POST, JSON.stringify(context)) != OK:
		request = null
		current_request.queue_free()
		_accept_turn(delivery_id, round_number, reply, _fallback(record, round_number))

func _valid_turn(turn: Dictionary, round_number: int) -> bool:
	if not turn.get("text") is String or turn.text.strip_edges().is_empty() or turn.text.length() > 220: return false
	if turn.get("emotion") not in ["pleased", "disappointed", "thoughtful", "neutral"] or not turn.get("end") is bool or not turn.get("replies") is Array: return false
	if turn.end or round_number == 3: return turn.replies.is_empty()
	if turn.replies.size() < 2 or turn.replies.size() > 3: return false
	for option in turn.replies:
		if not option is String or option.strip_edges().is_empty() or option.length() > 50: return false
	return true

func _accept_turn(id: String, round_number: int, reply: String, turn: Dictionary) -> void:
	if state.active.get("delivery_id") != id: return
	var record: Dictionary = state.deliveries[id]
	# A failed request can also schedule its completed callback. Commit a round
	# once, and ignore stale responses from a previous round or restored request.
	if record.feedback.done or not record.feedback.pending or int(record.feedback.round) + 1 != round_number: return
	var old: Dictionary = record.feedback.duplicate(true)
	if not reply.is_empty(): record.feedback.messages.append({"speaker": "player", "text": reply})
	record.feedback.messages.append({"speaker": "guest", "text": turn.text, "emotion": turn.emotion})
	record.feedback.round = round_number
	record.feedback.pending = false
	record.feedback.pending_reply = ""
	record.feedback.turn = turn
	record.feedback.done = turn.end or round_number >= 3
	if not _write():
		record.feedback = old
		record.feedback.pending = false
	changed.emit()

func retry_feedback() -> void:
	if is_instance_valid(request): return
	var record := current_record()
	if not record.is_empty() and record.status == "settled" and not record.feedback.done:
		if not record.get("story_completed", false) and _visit_story_completed():
			_resume_feedback()
			return
		_request_feedback(str(record.feedback.get("pending_reply", "")))

func _fallback(record: Dictionary, round_number: int) -> Dictionary:
	var text := "我尝过了。今天先坐一会儿，剩下的事下次再聊。"
	var emotion := "neutral"
	if round_number == 1 and record.review.status == "rejected":
		text = "这一杯有我不想碰的东西。我之前说过的，下次记得替我避开。"
		emotion = "disappointed"
	elif round_number == 1 and record.review.status == "scored":
		var difference: Dictionary = record.review.differences
		var key := "alcohol_intensity"
		var breakdown: Dictionary = record.review.get("attribute_breakdown", {})
		for attribute in Evaluation.ATTRS:
			var impact := float(breakdown.get(attribute, {}).get("deduction", absf(float(difference[attribute]))))
			var current := float(breakdown.get(key, {}).get("deduction", absf(float(difference[key]))))
			if impact > current: key = attribute
		var high: Dictionary = {"alcohol_intensity": "酒味有点重了，我今天想喝得轻些。", "sweetness": "这杯有点甜了，我今天不太想喝这么甜的。", "sourness": "酸味比我想要的重一些。", "bitterness": "这杯苦味有点重，我想要柔和些的。"}
		var low: Dictionary = {"alcohol_intensity": "酒味有点轻了，我今天想喝得更有劲些。", "sweetness": "要是再甜一点就好了。", "sourness": "我想要的酸味还差一点。", "bitterness": "再有一点苦味就更对了。"}
		var tolerance := float(record.demand.tolerances.get(key, 5))
		if absf(float(difference[key])) > tolerance:
			text = high[key] if float(difference[key]) > 0 else low[key]
			if record.review.satisfied:
				text = "今天这杯整体挺合我心意。" + text
			emotion = "thoughtful" if record.review.satisfied else "disappointed"
		else:
			text = "对，就是这个味道。今天这杯挺合我心意。"
			emotion = "pleased"
		if record.review.late: text += "只是等得久了点。"
	elif round_number == 2:
		var previous: Dictionary = record.previous_drink.get("actual", {}).get("attributes", {})
		var current: Dictionary = record.actual.get("attributes", {})
		if previous.has("sweetness") and current.has("sweetness") and absf(float(current.sweetness) - float(previous.sweetness)) > 5:
			text = "比上次甜些。我尝得出来。" if float(current.sweetness) > float(previous.sweetness) else "比上次淡了些，没那么甜了。"
		else: text = "能有人记得我想喝什么，感觉挺好的。" if record.review.get("satisfied", false) else "我口味可能挑了点。下次我们再试试。"
		emotion = "thoughtful"
	elif round_number == 3:
		text = "刚才的事还没说完。我接着讲，你再听一会儿？" if StoryDialogue.guest_id == record.guest_id and StoryDialogue.phase == "story" else "今晚先到这里吧。我该走了，下次见。"
		emotion = "pleased" if record.review.get("satisfied", false) else "neutral"
	if record.guest_id == "yellow_creature": return {"text": "我是奶蛙", "emotion": "neutral", "replies": [], "end": true}
	return {"text": text, "emotion": emotion, "replies": ["这个味道你喜欢吗？", "下次我记着你的口味。"] if round_number < 3 else [], "end": round_number >= 3}

func average_stars() -> float:
	var total := 0.0
	var count := 0
	for record in state.deliveries.values():
		if record.status == "settled" and record.review.get("stars") != null:
			total += float(record.review.stars)
			count += 1
	var seen: Dictionary={}
	for record: Dictionary in state.deliveries.values(): seen[str(record.get("drink_id",""))]=true
	for drink_id in GuestService.ledger().deliveries:
		var tx: Dictionary=GuestService.ledger().deliveries[drink_id]
		if not seen.has(drink_id) and tx.phase=="complete" and tx.receipt.score!=null:
			total+=clampf(float(tx.receipt.score)/20.0,0,5)
			count+=1
	return total / count if count else -1.0

func end_guest() -> bool:
	_cancel_request()
	var previous: Dictionary = state.active.duplicate(true)
	state.active = {}
	if not _write():
		state.active = previous
		return false
	changed.emit()
	return true

func reset_game() -> bool:
	_cancel_request()
	var previous := state.duplicate(true)
	state = {"version": 1, "active": {}, "deliveries": {}, "last_drinks": {}}
	writable = true
	if not _write():
		state = previous
		return false
	changed.emit()
	return true
