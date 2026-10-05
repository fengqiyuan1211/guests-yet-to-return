extends Node
## Durable sale intent -> idempotent wallet credit -> review -> short feedback.
signal changed
const Evaluation := preload("res://scripts/customer_evaluation.gd")
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

func _ready() -> void:
	rules = JSON.parse_string(FileAccess.get_file_as_string("res://data/guest_mechanics/settlement_rules.json"))
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/guest_mechanics/guest_profiles.json"))
	for profile in data.profiles: profiles[profile.guest_id] = profile
	events = JSON.parse_string(FileAccess.get_file_as_string("res://data/guest_mechanics/visit_events.json")).events
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
	for id in state.deliveries:
		if state.deliveries[id].status == "prepared": _commit_delivery(str(id))

func _number(value: Variant, minimum: float, maximum: float) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and float(value) >= minimum and float(value) <= maximum

func _valid_saved_state(data: Variant) -> bool:
	if not data is Dictionary or data.get("version") != 1 or not data.get("active") is Dictionary or not data.get("deliveries") is Dictionary or not data.get("last_drinks") is Dictionary: return false
	var active: Dictionary = data.active
	if not active.is_empty():
		for key in ["id", "guest_id", "delivery_id"]:
			if not active.get(key) is String: return false
		for key in ["profile", "demand", "order"]:
			if not active.get(key) is Dictionary: return false
		if not profiles.has(active.guest_id) or active.profile.get("id") != active.guest_id: return false
		if not _number(active.get("day"), 1, 1000000000) or not _number(active.get("visit"), 1, 1000000000): return false
		if not active.delivery_id.is_empty() and not data.deliveries.has(active.delivery_id): return false
	for id in data.deliveries:
		var record: Variant = data.deliveries[id]
		if not id is String or not record is Dictionary or record.get("id") != id or record.get("status") not in ["prepared", "settled"]: return false
		if not profiles.has(record.get("guest_id")) or not _number(record.get("amount"), 1, 1000000000) or float(record.amount) != floor(float(record.amount)): return false
		for key in ["actual", "review", "feedback", "previous_drink", "demand"]:
			if not record.get(key) is Dictionary: return false
		var feedback: Dictionary = record.feedback
		if not _number(feedback.get("round"), 0, 3) or float(feedback.round) != floor(float(feedback.round)): return false
		if not feedback.get("pending") is bool or not feedback.get("done") is bool or not feedback.get("messages") is Array or feedback.messages.size() > 6 or not feedback.get("pending_reply") is String: return false
		if not feedback.get("turn") is Dictionary: return false
		if int(feedback.round) > 0 and not _valid_turn(feedback.turn, int(feedback.round)): return false
		for message in feedback.messages:
			if not message is Dictionary or message.get("speaker") not in ["guest", "player"] or not message.get("text") is String: return false
		if record.review.get("status") not in ["scored", "rejected", "data_incomplete"]: return false
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
	if is_instance_valid(request):
		request.cancel_request()
		request.queue_free()
	request = null

func begin_guest(profile: Dictionary, visit: int, restoring: bool) -> bool:
	if not writable: return false
	if restoring and state.active.get("guest_id") == profile.id and int(state.active.get("day", -1)) == TimeManager.day and int(state.active.get("visit", -1)) == visit:
		call_deferred("_resume_feedback")
		return true
	_cancel_request()
	var number := int(StoryDialogue.progress.get(str(profile.id), {}).get("completed", 0)) + 1
	var episode_id := "%s_%02d" % [profile.id, number]
	var p: Dictionary = profiles[str(profile.id)].duplicate(true)
	var demand: Dictionary = {"target": p.base_preferences.duplicate(true), "weights": p.weights.duplicate(true),
		"tolerances": p.tolerances.duplicate(true), "constraints": p.get("constraints", []).duplicate(true),
		"soft_state_penalties": p.get("soft_state_penalties", []).duplicate(true), "episode_id": episode_id,
		"mood_note": "", "requested_recipe_id": "", "profile_version": p.profile_version}
	for key in Evaluation.ATTRS: demand.target[key] = clampf(float(demand.target[key]) + float(p.get("permanent_delta", {}).get(key, 0)), 0, 100)
	for event in events:
		if event.guest_id == profile.id and event.story_episode_id == episode_id:
			for key in Evaluation.ATTRS: demand.target[key] = clampf(float(demand.target[key]) + float(event.preference_delta.get(key, 0)), 0, 100)
			demand.soft_state_penalties.append_array(event.get("soft_state_penalty_additions", []))
			demand.mood_note = event.get("mood_note", "")
			demand.requested_recipe_id = event.get("requested_recipe_id", "")
	var previous: Dictionary = state.active.duplicate(true)
	state.active = {"id": Crypto.new().generate_random_bytes(16).hex_encode(), "guest_id": profile.id,
		"day": TimeManager.day, "visit": visit, "demand": demand, "order": {}, "delivery_id": "",
		"profile": profile.duplicate(true)}
	if not _write():
		state.active = previous
		return false
	changed.emit()
	return true

func prepare_order(recipe_id: String) -> Dictionary:
	if not writable or state.active.is_empty() or not TimeManager.is_open or has_delivery(): return {}
	var price := -1
	for entry in MenuCatalog.entries:
		if entry.id == recipe_id: price = int(entry.price)
	if price < 1: return {}
	var old: Dictionary = state.active.order.duplicate(true)
	var started := int(old.get("started_minute", TimeManager.minutes_since_midnight))
	state.active.order = {"recipe_id": recipe_id, "price": price, "started_minute": started,
		"time_limit_minutes": int(rules.order_time_limit_minutes), "demand": state.active.demand.duplicate(true)}
	if not _write():
		state.active.order = old
		return {}
	return {"visit_id": state.active.id, "recipe_id": recipe_id, "price": price}

func has_delivery() -> bool:
	return not str(state.active.get("delivery_id", "")).is_empty()

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
		return _commit_delivery(id)
	if has_delivery() or state.active.order.is_empty() or result.get("recipe", {}).get("id") != state.active.order.recipe_id:
		last_error = "这一桌已经结过账，或者酒款已变更。"
		return false
	var definitions := WorkbenchSession.MATERIALS.duplicate(true)
	definitions.merge(WorkbenchSession.SOLIDS)
	definitions.merge(WorkbenchSession.GARNISHES)
	var actual := Evaluation.sensory(result, definitions, rules)
	var waited := posmod(TimeManager.minutes_since_midnight - int(state.active.order.started_minute), 1440)
	var review := Evaluation.evaluate(state.active.order.demand, actual, waited > int(state.active.order.time_limit_minutes), rules)
	var record := {"id": id, "status": "prepared", "guest_id": state.active.guest_id,
		"day": TimeManager.day, "drink_id": drink_id, "recipe_id": state.active.order.recipe_id,
		"recipe_name": result.get("recipe", {}).get("name", "这一杯"), "amount": int(state.active.order.price),
		"demand": state.active.order.demand.duplicate(true), "actual": actual, "review": review,
		"craft": result.get("evaluation", {}).duplicate(true), "waited_minutes": waited,
		"previous_drink": state.last_drinks.get(str(state.active.guest_id), {}).duplicate(true),
		"story": StoryDialogue.history.duplicate(true), "known": StoryDialogue.is_known(str(state.active.guest_id)),
		"feedback": {"round": 0, "pending": false, "pending_reply": "", "messages": [], "turn": {}, "done": false}}
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
		_resume_feedback()
		return true
	if not SlotWallet.credit_sale(id, int(record.amount)):
		last_error = SlotWallet.last_error
		return false
	record.status = "settled"
	var previous: Dictionary = state.last_drinks.get(str(record.guest_id), {}).duplicate(true)
	state.last_drinks[record.guest_id] = {"recipe_id": record.recipe_id, "actual": record.actual.duplicate(true), "day": record.day}
	if not _write():
		record.status = "prepared"
		state.last_drinks[record.guest_id] = previous
		return false # Durable wallet receipt makes retry/recovery safe.
	changed.emit()
	if state.active.get("delivery_id") == id: call_deferred("_resume_feedback")
	return true

func _resume_feedback() -> void:
	var record := current_record()
	if record.is_empty() or record.status != "settled" or record.feedback.done or is_instance_valid(request): return
	if record.feedback.pending or int(record.feedback.round) == 0:
		_request_feedback(str(record.feedback.get("pending_reply", "")))

func choose_feedback(index: int, expected_round: int) -> void:
	var record := current_record()
	if record.is_empty() or record.feedback.done or record.feedback.pending or int(record.feedback.round) != expected_round: return
	var replies: Array = record.feedback.turn.get("replies", [])
	if index < 0 or index >= replies.size(): return
	_request_feedback(str(replies[index]))

func _request_feedback(reply: String) -> void:
	var record := current_record()
	if record.is_empty() or record.feedback.done or int(record.feedback.round) >= 3: return
	var feedback: Dictionary = record.feedback
	feedback.pending = true
	feedback.pending_reply = reply
	if not _write():
		feedback.pending = false
		return
	changed.emit()
	var round_number := int(feedback.round) + 1
	var context := {"request_id": record.id + ":%d" % round_number, "round": round_number,
		"guest": {"id": record.guest_id, "name": state.active.profile.name if record.known else "来客",
			"bio": state.active.profile.bio if record.known else "身份尚未介绍，不要自报名字或泄露身份"},
		"story": record.story, "demand": record.demand, "drink": {"name": record.recipe_name, "actual": record.actual},
		"previous_drink": record.previous_drink, "review": record.review,
		"history": feedback.messages, "player_reply": reply, "draft_sensory_model": true}
	request = HTTPRequest.new()
	request.timeout = 12.0
	request.body_size_limit = 65536
	add_child(request)
	var epoch := generation
	var delivery_id := str(record.id)
	var current_request := request
	current_request.request_completed.connect(func(status: int, code: int, _headers: PackedStringArray, body: PackedByteArray):
		if generation != epoch or state.active.get("delivery_id") != delivery_id: return
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
		for attribute in Evaluation.ATTRS:
			if absf(float(difference[attribute])) > absf(float(difference[key])): key = attribute
		var high: Dictionary = {"alcohol_intensity": "酒味有点重了，我今天想喝得轻些。", "sweetness": "这杯有点甜了，我今天不太想喝这么甜的。", "sourness": "酸味比我想要的重一些。", "bitterness": "这杯苦味有点重，我想要柔和些的。"}
		var low: Dictionary = {"alcohol_intensity": "酒味有点轻了，我今天想喝得更有劲些。", "sweetness": "要是再甜一点就好了。", "sourness": "我想要的酸味还差一点。", "bitterness": "再有一点苦味就更对了。"}
		var tolerance := float(record.demand.tolerances.get(key, 5))
		if absf(float(difference[key])) > tolerance:
			text = high[key] if float(difference[key]) > 0 else low[key]
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
		text = "今晚先到这里吧。我该走了，下次见。"
		emotion = "pleased" if record.review.get("satisfied", false) else "neutral"
	if record.guest_id == "yellow_creature": return {"text": "我是奶龙", "emotion": "neutral", "replies": [], "end": true}
	return {"text": text, "emotion": emotion, "replies": ["这个味道你喜欢吗？", "下次我记着你的口味。"] if round_number < 3 else [], "end": round_number >= 3}

func average_stars() -> float:
	var total := 0.0
	var count := 0
	for record in state.deliveries.values():
		if record.status == "settled" and record.review.get("stars") != null:
			total += float(record.review.stars)
			count += 1
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
