extends RefCounted
const GAME_ID := "stick_memory_badminton"
const ITEM_ID := "item_recipe_after_school"
const TARGET := 5

static func whole(v: Variant, limit: int) -> bool:
	return (v is int or v is float) and is_finite(float(v)) and v == floor(v) and v >= 0 and v <= limit

static func valid_result(result: Variant) -> bool:
	if not result is Dictionary or result.get("minigame_id") != GAME_ID or result.get("guest_id") != "stick": return false
	if not result.get("match_id") is String or not result.match_id.begins_with("memory-") or result.match_id.length() > 80: return false
	for key in ["player_score", "stick_score"]:
		if not whole(result.get(key), TARGET): return false
	for key in ["longest_rally", "player_legal_actions"]:
		if not whole(result.get(key), 100000): return false
	if not result.get("assist_used") is bool or result.get("finish_reason") != "target_score_reached": return false
	if result.has("mode"):
		if result.mode not in ["story", "practice"] or not result.get("visit_id") is String: return false
		if result.mode == "story" and result.visit_id.is_empty(): return false
	var p := int(result.player_score)
	var ai := int(result.stick_score)
	if p == TARGET and ai < TARGET: return result.get("outcome") == "win" and int(result.player_legal_actions) > 0
	if ai == TARGET and p < TARGET: return result.get("outcome") == "lose"
	return false
