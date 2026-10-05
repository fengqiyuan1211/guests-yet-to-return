extends RefCounted
## Only authenticated classic recipe snapshots can earn ordinary recipe tags.
const CLASSICS := ["last_word", "mojito", "gin_and_tonic", "long_island_iced_tea", "manhattan"]
const CARBONATED := ["sku_soda_water", "sku_tonic_water", "sku_cola"]

static func _number(value: Variant) -> bool:
	return (value is float or value is int) and is_finite(float(value)) and value >= 0

static func resolve(result: Dictionary, actual: Dictionary, config: Dictionary) -> Dictionary:
	var answer := {"status":"complete", "version":config.get("version", "not_enabled"), "active":[], "inactive":[]}
	if config.is_empty(): return answer
	if config.get("schema_version") != 1 or not config.get("buffs") is Array or not config.get("recipes") is Dictionary or config.get("required_quality_tier") != "perfect":
		answer.status = "data_incomplete"
		answer.inactive.append({"id":"", "reason":"invalid_buff_rules"})
		return answer
	var registry: Dictionary = {}
	for item: Variant in config.buffs:
		if not item is Dictionary or not item.get("id") is String or item.get("kind") != "ordinary" or item.get("namespace") not in ["mouthfeel", "flavor"] or not item.get("tag") is String or registry.has(item.id):
			answer.status = "data_incomplete"
			answer.inactive.append({"id":"", "reason":"invalid_buff_definition"})
			return answer
		registry[item.id] = item
	var recipe: Dictionary = result.get("recipe", {})
	var recipe_id := str(recipe.get("id", ""))
	if recipe_id not in CLASSICS or not config.recipes.has(recipe_id):
		answer.inactive.append({"id":"", "reason":"recipe_not_authorized"})
		return answer
	var authorization: Variant = config.recipes[recipe_id]
	if not authorization is Dictionary or not authorization.get("buff_ids") is Array or not authorization.get("allowed_versions") is Array:
		answer.status = "data_incomplete"
		answer.inactive.append({"id":"", "reason":"missing_recipe_authorization"})
		return answer
	var quality: Dictionary = result.get("evaluation", {})
	var reason := ""
	if actual.get("status") != "complete": reason = "data_incomplete"
	elif recipe.get("source_kind") != "menu_catalog": reason = "recipe_source_not_authorized"
	elif recipe.get("version") not in authorization.allowed_versions or quality.get("recipe_version") != recipe.get("version"): reason = "recipe_version_not_authorized"
	elif quality.get("tier") != "perfect" or not _number(quality.get("score")) or float(quality.score) < 95 or float(quality.score) > 100: reason = "quality_not_perfect"
	var seen: Dictionary = {}
	for id: Variant in authorization.buff_ids:
		if not id is String or not registry.has(id):
			answer.status = "data_incomplete"
			answer.inactive.append({"id":str(id), "reason":"unknown_buff"})
			continue
		if seen.has(id): continue
		seen[id] = true
		var definition: Dictionary = registry[id]
		var failure := reason
		var tags: Variant = recipe.get(str(definition.namespace) + "_tags", [])
		if failure.is_empty():
			var present: bool = tags is Array and definition.tag in tags
			for alias: Variant in definition.get("tag_aliases", []): present = present or (tags is Array and alias in tags)
			if not present: failure = "recipe_tag_mismatch"
		if failure.is_empty() and id == "buff.bubbles":
			var carbonated := 0.0
			for sku in CARBONATED: carbonated += float(actual.get("items", {}).get(sku, 0))
			var trace: Dictionary = quality.get("trace", {})
			if not _number(trace.get("carbonated")) or not _number(trace.get("flat")): failure = "missing_state"
			elif carbonated <= 0 or float(trace.carbonated) <= 0 or float(trace.flat) > 0: failure = "bubbles_absent"
		if failure.is_empty(): answer.active.append({"id":id, "kind":"ordinary", "name":definition.get("name", definition.tag), "recipe_id":recipe_id, "recipe_version":recipe.version})
		else: answer.inactive.append({"id":id, "reason":failure})
	return answer
