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

static func summarize(story: Dictionary, deliveries: Dictionary, settings: Dictionary = {}, legacy: Dictionary = {}) -> Dictionary:
	var gate=preload("res://scripts/story_activity_gate.gd")
	return gate.summarize("stick",story,gate.episodes("stick"),deliveries,legacy,settings)
