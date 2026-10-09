extends RefCounted
## Story invitation uses the final customer total of the five fixed, settled story cups.
const PATH := "res://data/minigames/stick_badminton.json"

static func config() -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string(PATH))

static func score_ok(value: Variant) -> bool:
	return (value is float or value is int) and is_finite(float(value)) and value >= 0

static func total_score(record: Dictionary) -> Variant:
	var review: Variant = record.get("review")
	if not review is Dictionary: return null
	var value: Variant = review.get("satisfaction")
	# A refused real cup still belongs to that chapter and contributes zero.
	if review.get("status") == "rejected" and value == null: return 0.0
	if review.get("status") not in ["scored", "rejected"] or not score_ok(value): return null
	# The final score already includes taste, soft penalties, waiting and any real Buff.
	return float(value)

static func sequence(record: Dictionary) -> int:
	var serial: Variant = record.get("visit_serial")
	if (serial is float or serial is int) and is_finite(float(serial)) and serial > 0 and serial == floor(serial): return int(serial)
	# Older real workbench drink IDs carry their monotonic session serial.
	var drink := str(record.get("drink_id", ""))
	if drink.begins_with("practice-") and drink.ends_with("-drink"):
		var number := drink.trim_prefix("practice-").trim_suffix("-drink")
		if number.is_valid_int() and int(number) > 0: return int(number)
	return -1

static func visit_key(record: Dictionary) -> String:
	return str(record.get("visit_id", str(record.get("id", "")).get_slice(":", 0)))

static func chapter(record: Dictionary) -> String:
	return str(record.get("story_episode_id", record.get("demand", {}).get("episode_id", "")))

static func completed_visit(record: Dictionary, story: Dictionary) -> bool:
	if record.has("story_completed"): return record.story_completed == true
	# Old saves can prove a closing only when that chapter is also confirmed in progress.
	var id := chapter(record)
	var heard: Variant = story.get("heard", {}).get(id)
	var lines: Variant = record.get("story", [])
	return heard is Array and not heard.is_empty() and lines is Array and lines == heard

static func summarize(story: Dictionary, deliveries: Dictionary, settings: Dictionary = {}) -> Dictionary:
	var rule := config() if settings.is_empty() else settings
	var count := 5
	var threshold := float(rule.get("minimum_average_total_score", 60))
	var candidates: Array = []
	for record: Variant in deliveries.values():
		if record is Dictionary and record.get("play_mode")=="mixing": continue
		if not record is Dictionary or record.get("guest_id") != "stick" or record.get("status") != "settled": continue
		if total_score(record) == null or not completed_visit(record, story) or sequence(record) < 0: continue
		candidates.append(record)
	candidates.sort_custom(func(a,b): return sequence(a) < sequence(b))
	var visits: Dictionary = {}
	var chapters: Dictionary = {}
	for record: Dictionary in candidates:
		var key := visit_key(record)
		var id := chapter(record)
		if key.is_empty() or visits.has(key) or id not in ["stick_01", "stick_02", "stick_03", "stick_04", "stick_05"] or chapters.has(id): continue
		visits[key] = true
		chapters[id] = record
	var total := 0.0
	var ids: Array = []
	for i in range(1, 6):
		var id := "stick_%02d" % i
		if chapters.has(id):
			var record: Dictionary = chapters[id]
			total += float(total_score(record))
			ids.append(str(record.id))
	var ready := ids.size() == count
	return {"eligible": int(story.get("completed", 0)) >= count and ready and total >= threshold * count,
		"story_completed": int(story.get("completed", 0)), "score_count": ids.size(), "required_scores": count,
		"average": total / count if ready else null, "minimum_average": threshold,
		"score_window": "story_five", "score_source": "review.satisfaction", "delivery_ids": ids}
