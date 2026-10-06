extends RefCounted
## Actual cup facts and floating point customer scores; no inventory or story effects.
const ATTRS := ["alcohol_intensity", "sweetness", "sourness", "bitterness"]
const Craft := preload("res://scripts/workbench_evaluation.gd")
const Sensory := preload("res://scripts/sensory_model.gd")

static func number(value: Variant, minimum: float = 0, maximum: float = INF) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and value >= minimum and value <= maximum

static func scoring(rules: Dictionary) -> Dictionary:
	# v1 is an archived ruleset, retained for already locked legacy orders only.
	return rules.get("scoring", {"version":"guest-match-playtest-1", "penalty_scale":2.0, "satisfied_min":70.0, "soft_penalty_limit":20.0})

static func resolved_sensory(rules: Dictionary) -> Dictionary:
	var model: Variant = rules.get("sensory", {})
	if not model is Dictionary: return {}
	# A configuration pointer is resolved only before freezing. Full saved snapshots
	# are returned unchanged, so ingredient/model changes never rewrite old visits.
	if model.get("version") == "sensory-calibrated-1" and model.get("source") == "res://data/sensory/model.json" and not model.has("profiles"):
		return Sensory.snapshot()
	return model.duplicate(true)

static func rules_valid(rules: Dictionary) -> bool:
	if rules.get("schema_version") != 1 or not rules.get("sensory") is Dictionary: return false
	if rules.has("scoring") and not rules.scoring is Dictionary: return false
	var values := scoring(rules)
	if values.get("version") not in ["guest-match-playtest-1", "guest-match-playtest-2"]: return false
	for key in ["penalty_scale", "satisfied_min", "soft_penalty_limit"]:
		if not number(values.get(key)): return false
	if rules.has("scoring") and (not number(values.get("ordinary_bonus_limit")) or not values.get("buffs_enabled") is bool): return false
	if not number(rules.get("timeout_penalty"), -INF, 0) or not number(rules.get("order_time_limit_minutes")): return false
	if not rules.get("star_thresholds") is Array or rules.star_thresholds.is_empty(): return false
	var minima: Dictionary = {}
	for threshold: Variant in rules.star_thresholds:
		if not threshold is Dictionary or not number(threshold.get("minimum")) or not number(threshold.get("stars"), 1, 5): return false
		if threshold.stars != floor(threshold.stars) or minima.has(threshold.minimum): return false
		minima[threshold.minimum] = true
	if not minima.has(0) and not minima.has(0.0): return false
	var model := resolved_sensory(rules)
	if model.has("ingredient_facts") and not model.ingredient_facts is Dictionary: return false
	if model.get("version") == "sensory-calibrated-1":
		if not Sensory.valid_model(model): return false
		for key in ["known_solids", "pulp_solids", "fruit_liquids"]:
			if not model.get(key, []) is Array: return false
		return number(model.get("fruit_heavy_fraction", 0.25), 0, 1)
	if model.get("version") not in ["cup-sensory-playtest-1", "cup-sensory-playtest-2"] or model.get("attribute_order", ATTRS) != ATTRS or not model.get("profiles") is Dictionary: return false
	if not model.get("gains") is Array or model.gains.size() != ATTRS.size(): return false
	for gain: Variant in model.gains:
		if not number(gain): return false
	for profile: Variant in model.profiles.values():
		if not profile is Array or profile.size() != ATTRS.size(): return false
		for value: Variant in profile:
			if not number(value, 0, 100): return false
	for key in ["known_solids", "pulp_solids", "fruit_liquids"]:
		if not model.get(key) is Array: return false
	return number(model.get("sugar_contribution_per_gram", 100)) and number(model.get("fruit_heavy_fraction", 0.25), 0, 1)

static func demand_valid(demand: Dictionary) -> bool:
	for field in ["target", "weights", "tolerances"]:
		if not demand.get(field) is Dictionary: return false
	var weight_sum := 0.0
	for key in ATTRS:
		if not number(demand.target.get(key), 0, 100) or not number(demand.tolerances.get(key), 0, 100) or not number(demand.weights.get(key)): return false
		weight_sum += float(demand.weights[key])
	if not is_finite(weight_sum) or weight_sum <= 0 or not demand.get("constraints", []) is Array or not demand.get("soft_state_penalties", []) is Array or not demand.get("buff_affinities", {}) is Dictionary: return false
	for value: Variant in demand.get("buff_affinities", {}).values():
		if not number(value): return false
	return true

static func _amounts(value: Variant, definitions: Dictionary, aliases: Dictionary = {}, accept_string_names: bool = false) -> Dictionary:
	if not value is Dictionary: return {"valid":false, "items":{}}
	var items: Dictionary = {}
	for id: Variant in value:
		if (not id is String and not (accept_string_names and id is StringName)) or not number(value[id]): return {"valid":false, "items":{}}
		if float(value[id]) == 0: continue
		var key := Craft.sku(str(id), definitions)
		key = str(aliases.get(key, key))
		items[key] = float(items.get(key, 0)) + float(value[id])
	return {"valid":true, "items":items}

static func _sensory_error(reason: String, items: Dictionary = {}, facts: Dictionary = {}, missing: Array = []) -> Dictionary:
	return {"status":"data_incomplete", "deliverable":false, "reason":reason, "attributes":{}, "items":items, "states":{}, "facts":facts, "missing":missing}

static func sensory(result: Dictionary, definitions: Dictionary, rules: Dictionary) -> Dictionary:
	if not rules_valid(rules): return _sensory_error("invalid_scoring_rules")
	var model := resolved_sensory(rules)
	var aliases: Dictionary = model.get("aliases", {}) if model.get("version") == "sensory-calibrated-1" else {}
	var vessel: Variant = result.get("contents")
	if not vessel is Dictionary: return _sensory_error("missing_served_contents")
	var modern: bool = model.get("version") == "sensory-calibrated-1"
	var liquid := _amounts(vessel.get("contents"), definitions, aliases, modern)
	var solid := _amounts(vessel.get("solids", {}), definitions, aliases, modern)
	if not liquid.valid or not solid.valid: return _sensory_error("invalid_actual_amount")
	var actual: Dictionary = liquid.items
	var solids: Dictionary = solid.items
	if modern:
		for excluded in model.get("excluded_ids", []):
			actual.erase(excluded)
			solids.erase(excluded)
	var all_items := actual.duplicate(true)
	for id in solids: all_items[id] = float(all_items.get(id, 0)) + float(solids[id])
	if vessel.has("garnishes") and not vessel.garnishes is Array: return _sensory_error("invalid_garnishes", all_items)
	var decorations: Array = Craft.decoration_ids(vessel)
	for id: Variant in decorations:
		if not id is String and not (modern and id is StringName): return _sensory_error("invalid_garnishes", all_items)
		var sku := Craft.sku(str(id), definitions)
		sku = str(aliases.get(sku, sku))
		all_items[sku] = float(all_items.get(sku, 0)) + 1
	# SKU facts are frozen by the visit service. ABV and sensory intensity are not proxies for alcohol.
	var metadata: Dictionary = model.get("ingredient_facts", {}).duplicate(true)
	if not model.has("ingredient_facts"):
		for id: Variant in definitions:
			if definitions[id] is Dictionary and definitions[id].has("contains_alcohol"):
				metadata[Craft.sku(str(id), definitions)] = {"contains_alcohol":definitions[id].contains_alcohol}
	var contains_alcohol: Variant = false
	var unknown_alcohol := false
	for id in all_items:
		var item: Variant = metadata.get(id, {})
		var fact: Variant = item.get("contains_alcohol") if item is Dictionary else null
		if fact is bool and fact: contains_alcohol = true
		elif not fact is bool: unknown_alcohol = true
	if contains_alcohol != true and unknown_alcohol: contains_alcohol = null
	var facts := {"contains_alcohol":contains_alcohol}
	var attributes: Dictionary = {}
	var volume := Craft.total(actual)
	if model.get("version") == "sensory-calibrated-1":
		var measured := Sensory.evaluate(actual, solids, definitions, model)
		if not measured.data_complete:
			return _sensory_error("empty_cup" if volume <= 0 else "missing_sensory_data", all_items, facts, measured.missing)
		attributes = measured.attributes.duplicate(true)
		volume = float(measured.volume_ml)
	else:
		# Preserve v1/v2 arithmetic exactly for previously frozen orders.
		var unknown: Array = []
		for id in actual:
			if not model.profiles.has(id): unknown.append(id)
		for id in solids:
			if id not in model.known_solids: unknown.append(id)
		if not is_finite(volume) or volume <= 0 or not unknown.is_empty():
			return _sensory_error("empty_cup" if volume <= 0 else "missing_sensory_data", all_items, facts, unknown)
		var average: Array = [0.0, 0.0, 0.0, 0.0]
		for id in actual:
			for i in range(ATTRS.size()): average[i] += float(model.profiles[id][i]) * float(actual[id]) / volume
		if model.get("version") == "cup-sensory-playtest-1": average = Craft.average(actual, model.profiles)
		for i in range(ATTRS.size()): attributes[ATTRS[i]] = clampf(float(average[i]) * float(model.gains[i]), 0, 100)
		var denominator := maxf(20, volume) if model.get("version") == "cup-sensory-playtest-1" else volume
		attributes.sweetness = clampf(float(attributes.sweetness) + float(model.get("sugar_contribution_per_gram", 100)) * float(solids.get("sku_white_cane_sugar", 0)) / denominator, 0, 100)
	var fruit := 0.0
	for id in model.get("fruit_liquids", []): fruit += float(actual.get(id, 0))
	var pulp := false
	for id in model.get("pulp_solids", []): pulp = pulp or float(solids.get(id, 0)) > 0
	return {"status":"complete", "deliverable":true, "version":model.version, "draft":true,
		"attributes":attributes, "items":all_items, "facts":facts,
		"states":{"mouthfeel.pulp":pulp, "flavor.fruit_intensity":"heavy" if fruit / volume >= float(model.get("fruit_heavy_fraction", 0.25)) else "light"}}

static func _compare(left: Variant, operator: String, right: Variant) -> Variant:
	if left == null or right == null: return null
	if operator == "eq":
		if left is bool or right is bool: return left == right if left is bool and right is bool else null
		if left is String or right is String: return left == right if left is String and right is String else null
		return float(left) == float(right) if number(left, -INF) and number(right, -INF) else null
	if not number(left, -INF) or not number(right, -INF): return null
	if operator == "gte": return float(left) >= float(right)
	if operator == "lte": return float(left) <= float(right)
	return null

static func _incomplete(reason: String) -> Dictionary:
	return {"status":"data_incomplete", "data_status":"incomplete", "satisfaction":null, "stars":null, "satisfied":false, "reason":reason, "reason_codes":[reason]}

static func evaluate(demand: Dictionary, actual: Dictionary, late: bool, rules: Dictionary, buff_result: Dictionary = {}) -> Dictionary:
	if not rules_valid(rules) or not demand_valid(demand): return _incomplete("invalid_scoring_data")
	if actual.get("status") != "complete" or not actual.get("attributes") is Dictionary: return _incomplete(str(actual.get("reason", "missing_actual_attributes")))
	for key in ATTRS:
		if not number(actual.attributes.get(key), 0, 100): return _incomplete("invalid_actual_attributes")
	for restriction: Variant in demand.get("constraints", []):
		if not restriction is Dictionary or restriction.get("scope", "served_contents") != "served_contents": return _incomplete("unsupported_constraint_scope")
		var violation: Variant = null
		if restriction.get("kind") == "forbid_items":
			if not restriction.get("items") is Array or not actual.get("items") is Dictionary: return _incomplete("missing_constraint_items")
			violation = false
			for id: Variant in restriction.items:
				if not id is String or not number(actual.items.get(id, 0)): return _incomplete("invalid_constraint_items")
				violation = violation or float(actual.items.get(id, 0)) > 0
		elif restriction.get("kind") == "max_attribute":
			var attribute := str(restriction.get("attribute", ""))
			if attribute not in ATTRS or not number(restriction.get("maximum"), 0, 100): return _incomplete("invalid_attribute_constraint")
			violation = float(actual.attributes[attribute]) > float(restriction.maximum)
		elif restriction.get("kind") == "forbid_fact" or restriction.has("fact"):
			if restriction.get("on_violation", "reject") != "reject" or not actual.get("facts", {}) is Dictionary: return _incomplete("unsupported_fact_constraint")
			violation = _compare(actual.get("facts", {}).get(str(restriction.get("fact", ""))), str(restriction.get("operator", "eq")), restriction.get("value"))
		if violation == null: return _incomplete("unknown_constraint_fact")
		if violation:
			return {"status":"rejected", "data_status":"complete", "constraint_status":"rejected", "satisfaction":null, "stars":1, "satisfied":false, "ordinary_bonus":0, "legendary_bonus":0, "buff_bonus":0, "applied_buffs":[], "reason":str(restriction.get("label", restriction.get("id", "不符合本次要求")))}
	var weighted := 0.0
	var weight_sum := 0.0
	var differences: Dictionary = {}
	var breakdown: Dictionary = {}
	for key in ATTRS:
		var difference := float(actual.attributes[key]) - float(demand.target[key])
		var error := maxf(0, absf(difference) - float(demand.tolerances[key]))
		var weight := float(demand.weights[key])
		differences[key] = difference
		weighted += error * weight
		weight_sum += weight
		breakdown[key] = {"target":demand.target[key], "actual":actual.attributes[key], "tolerance":demand.tolerances[key], "weight":weight, "effective_error":error}
	if not is_finite(weighted) or not is_finite(weight_sum): return _incomplete("invalid_weighted_error")
	var values := scoring(rules)
	var base := clampf(100 - float(values.penalty_scale) * weighted / weight_sum, 0, 100)
	var groups: Dictionary = {}
	var legacy: bool = values.version == "guest-match-playtest-1"
	if not actual.get("states", {}) is Dictionary: return _incomplete("invalid_actual_states")
	for item: Variant in demand.get("soft_state_penalties", []):
		if not item is Dictionary or not item.get("id") is String or not item.get("state_id") is String or not number(item.get("penalty"), -INF, 0): return _incomplete("invalid_soft_penalty")
		if item.get("scope", "served_contents") != "served_contents": return _incomplete("unsupported_soft_penalty_scope")
		var matches: Variant = _compare(actual.get("states", {}).get(item.state_id), str(item.get("operator", "")), item.get("value"))
		if matches == null: return _incomplete("unknown_soft_state")
		if matches:
			var group := str(item.get("dedup_group", item.id))
			if not groups.has(group) or not legacy: groups[group] = minf(float(groups.get(group, 0)), float(item.penalty))
	var raw_penalty := 0.0
	for value in groups.values(): raw_penalty += float(value)
	var timeout := float(rules.timeout_penalty) if late else 0.0
	var penalty := clampf(raw_penalty, -float(values.soft_penalty_limit), 0)
	if legacy:
		penalty = clampf(raw_penalty + timeout, -float(values.soft_penalty_limit), 0)
		timeout = 0.0
	# The delivery service supplies recipe-qualified Buffs. Names and display tags do not qualify a Buff here.
	var bonus_raw := 0.0
	var applied: Array = []
	var counted: Dictionary = {}
	if values.get("buffs_enabled", false):
		if buff_result.get("status", "complete") != "complete" or not buff_result.get("active", []) is Array: return _incomplete("invalid_buff_result")
		for buff: Variant in buff_result.get("active", []):
			if not buff is Dictionary or not buff.get("id") is String or buff.get("kind") not in ["ordinary", "legendary"]: return _incomplete("invalid_active_buff")
			if buff.kind == "legendary": continue # Visual distinction only; no points until effects are designed.
			if counted.has(buff.id): continue
			counted[buff.id] = true
			var points := float(demand.get("buff_affinities", {}).get(buff.id, 0))
			if points > 0:
				bonus_raw += points
				applied.append({"id":buff.id, "name":buff.get("name", buff.id), "kind":"ordinary", "points":points})
	if not is_finite(bonus_raw): return _incomplete("invalid_buff_points")
	var ordinary_bonus := minf(bonus_raw, float(values.get("ordinary_bonus_limit", 0)))
	var score := clampf(base + penalty + timeout + ordinary_bonus, 0, 100)
	var stars := 1
	var applied_threshold := -1.0
	for threshold: Dictionary in rules.star_thresholds:
		if score >= float(threshold.minimum) and float(threshold.minimum) > applied_threshold:
			stars = int(threshold.stars)
			applied_threshold = float(threshold.minimum)
	var reasons: Array = []
	for key in ATTRS:
		breakdown[key].deduction = float(values.penalty_scale) * float(breakdown[key].effective_error) * float(breakdown[key].weight) / weight_sum
		if float(breakdown[key].deduction) > 0: reasons.append(key + ("_below_preference" if float(differences[key]) < 0 else "_above_preference"))
	var satisfied := score >= float(values.satisfied_min)
	return {"status":"scored", "outcome":"satisfied" if satisfied else "unsatisfied", "data_status":"complete", "constraint_status":"passed", "satisfaction_version":values.version,
		"base_score":base, "base_floor_applied":float(values.penalty_scale) * weighted / weight_sum > 100, "soft_penalty":penalty, "raw_soft_penalty":raw_penalty, "timeout_penalty":timeout, "penalty_groups":groups,
		"buff_bonus":ordinary_bonus, "ordinary_bonus":ordinary_bonus, "ordinary_bonus_uncapped":bonus_raw, "ordinary_bonus_cap":values.get("ordinary_bonus_limit", 0), "legendary_bonus":0, "applied_buffs":applied,
		"buff_status":"ordinary_enabled_legendary_reserved" if values.get("buffs_enabled", false) else "not_enabled_for_legacy_order", "satisfaction":score, "satisfied":satisfied, "stars":stars,
		"late":late, "differences":differences, "attribute_breakdown":breakdown, "reason_codes":reasons}
