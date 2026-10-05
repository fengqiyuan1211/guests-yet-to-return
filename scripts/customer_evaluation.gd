extends RefCounted
## Actual cup first; selected recipe never participates in sensory computation.
const ATTRS := ["alcohol_intensity", "sweetness", "sourness", "bitterness"]
const Craft := preload("res://scripts/workbench_evaluation.gd")

static func sensory(result: Dictionary, definitions: Dictionary, rules: Dictionary) -> Dictionary:
	var vessel: Dictionary = result.get("contents", {})
	var actual := Craft.canonical(vessel.get("contents", {}), definitions)
	var profiles: Dictionary = rules.sensory.profiles
	var unknown: Array = []
	for id in actual:
		if not profiles.has(id): unknown.append(id)
	var solids := Craft.canonical(vessel.get("solids", {}), definitions)
	var all_items := actual.duplicate(true)
	all_items.merge(solids, true)
	for id in Craft.decoration_ids(vessel): all_items[Craft.sku(str(id), definitions)] = 1
	for id in solids:
		if id not in rules.sensory.known_solids: unknown.append(id)
	if not unknown.is_empty() or Craft.total(actual) <= 0:
		return {"status": "data_incomplete", "missing": unknown, "attributes": {}, "items": all_items}
	var average := Craft.average(actual, profiles)
	var attributes: Dictionary = {}
	for i in range(4):
		attributes[ATTRS[i]] = clampf(float(average[i]) * float(rules.sensory.gains[i]), 0, 100)
	attributes.sweetness = clampf(float(attributes.sweetness) + 100 * float(solids.get("sku_white_cane_sugar", 0)) / maxf(20, Craft.total(actual)), 0, 100)
	var fruit := 0.0
	for id in rules.sensory.fruit_liquids: fruit += float(actual.get(id, 0))
	var pulp := false
	for id in rules.sensory.pulp_solids: pulp = pulp or float(solids.get(id, 0)) > 0
	return {"status": "complete", "version": rules.sensory.version, "draft": true,
		"attributes": attributes, "items": all_items,
		"states": {"mouthfeel.pulp": pulp, "flavor.fruit_intensity": "heavy" if fruit / Craft.total(actual) >= 0.25 else "light"}}

static func evaluate(demand: Dictionary, actual: Dictionary, late: bool, rules: Dictionary) -> Dictionary:
	for restriction in demand.get("constraints", []):
		if restriction.get("kind") == "forbid_items":
			for id in restriction.items:
				if float(actual.get("items", {}).get(id, 0)) > 0:
					return {"status": "rejected", "satisfaction": null, "stars": 1, "satisfied": false, "reason": restriction.label}
		elif restriction.get("kind") == "max_attribute":
			if actual.get("status") != "complete": return {"status": "data_incomplete", "satisfaction": null, "stars": null, "satisfied": false}
			if float(actual.attributes[restriction.attribute]) > float(restriction.maximum):
				return {"status": "rejected", "satisfaction": null, "stars": 1, "satisfied": false, "reason": restriction.label}
		else:
			return {"status": "data_incomplete", "satisfaction": null, "stars": null, "satisfied": false}
	if actual.get("status") != "complete":
		return {"status": "data_incomplete", "satisfaction": null, "stars": null, "satisfied": false}
	var states: Dictionary = actual.states
	var weighted := 0.0
	var weight_sum := 0.0
	var differences: Dictionary = {}
	for key in ATTRS:
		var difference := float(actual.attributes[key]) - float(demand.target[key])
		var tolerance := float(demand.tolerances.get(key, 5))
		var weight := float(demand.weights.get(key, 1))
		differences[key] = difference
		weighted += maxf(0, absf(difference) - tolerance) * weight
		weight_sum += weight
	if weight_sum <= 0: return {"status": "data_incomplete", "satisfaction": null, "stars": null, "satisfied": false}
	var base := clampf(100 - 2 * weighted / weight_sum, 0, 100)
	var penalty := float(rules.timeout_penalty) if late else 0.0
	var seen: Array = []
	for item in demand.get("soft_state_penalties", []):
		var state_id := str(item.state_id)
		if not states.has(state_id) or item.get("operator") != "eq":
			return {"status": "data_incomplete", "satisfaction": null, "stars": null, "satisfied": false}
		var group := str(item.get("dedup_group", item.id))
		if states[state_id] == item.value and not seen.has(group):
			penalty += minf(0, float(item.penalty))
			seen.append(group)
	penalty = maxf(-20, penalty)
	# No unearned buffs: eligibility/legendary recipes are not enabled yet.
	var score := maxf(0, base + penalty)
	var stars := 1
	for threshold in rules.star_thresholds:
		if score >= float(threshold.minimum):
			stars = int(threshold.stars)
			break
	return {"status": "scored", "base_score": base, "soft_penalty": penalty, "buff_bonus": 0,
		"satisfaction": score, "satisfied": score >= 70, "stars": stars, "late": late, "differences": differences}
