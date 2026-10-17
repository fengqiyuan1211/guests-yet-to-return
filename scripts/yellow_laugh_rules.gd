extends RefCounted
## Uses the settled cup's locked visit demand, never today's mutable profile or AI text.
const MIN_CRAFT_SCORE := 90.0
const RECEIPT_KEY := "yellow_laugh_played"

static func eligible(record: Dictionary) -> bool:
	if record.get("guest_id") != "yellow_creature" or record.get("status") != "settled": return false
	if str(record.get("id", "")).is_empty() or record.get(RECEIPT_KEY, false): return false
	var craft: Variant = record.get("craft", {}).get("score")
	if not (craft is int or craft is float) or not is_finite(float(craft)): return false
	if float(craft) < MIN_CRAFT_SCORE or float(craft) > 100.0: return false
	if record.get("play_mode") == "mixing":
		return record.get("free_settlement", {}).get("matched", false) == true
	var review: Dictionary = record.get("review", {})
	return review.get("status") == "scored" and review.get("satisfied", false) == true
