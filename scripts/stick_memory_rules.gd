extends RefCounted
const GAME_ID := "stick_memory_badminton"
const ITEM_ID := "item_recipe_after_school"
const TARGET := 3

static func whole(v: Variant, limit: int) -> bool:
	return (v is int or v is float) and is_finite(float(v)) and v == floor(v) and v >= 0 and v <= limit

static func valid_result(result: Variant, allow_legacy := false) -> bool:
	if not result is Dictionary or result.get("minigame_id") != GAME_ID or result.get("guest_id") != "stick": return false
	if result.has("target_score") and not whole(result.target_score, 5): return false
	var target: int = int(result.get("target_score", 5 if allow_legacy else TARGET))
	if target != TARGET and not (allow_legacy and target == 5): return false
	if not result.get("match_id") is String or not result.match_id.begins_with("memory-") or result.match_id.length() > 80: return false
	for key in ["player_score", "stick_score"]:
		if not whole(result.get(key), target): return false
	for key in ["longest_rally", "player_legal_actions"]:
		if not whole(result.get(key), 100000): return false
	if not result.get("assist_used") is bool or result.get("finish_reason") != "target_score_reached": return false
	if result.has("mode"):
		if result.mode not in ["story", "practice"] or not result.get("visit_id") is String: return false
		if result.mode == "story" and result.visit_id.is_empty(): return false
	var p := int(result.player_score)
	var ai := int(result.stick_score)
	if p == target and ai < target: return result.get("outcome") == "win" and int(result.player_legal_actions) > 0
	if ai == target and p < target: return result.get("outcome") == "lose"
	return false
