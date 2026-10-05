extends RefCounted
## Shared gameplay perception: actual composition first, then continuous response curves.
## These scores are independent 0–100 intensities, never physical percentages or ABV.
const CONFIG_PATH := "res://data/sensory/model.json"
const VERSION := "sensory-calibrated-1"
const ATTRS := ["alcohol_intensity", "sweetness", "sourness", "bitterness"]

static func snapshot() -> Dictionary:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(CONFIG_PATH))
	return parsed.duplicate(true) if valid_model(parsed) else {}

static func _number(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value))

static func _profile(value: Variant) -> bool:
	if not value is Array or value.size() != ATTRS.size(): return false
	for entry in value:
		if not _number(entry) or float(entry) < 0.0 or float(entry) > 100.0: return false
	return true

static func valid_model(model: Variant) -> bool:
	if not model is Dictionary or model.get("version") != VERSION: return false
	if model.get("attribute_order") != ATTRS: return false
	if not model.get("profiles") is Dictionary or model.profiles.is_empty(): return false
	if not model.get("solid_profiles") is Dictionary or not model.get("curves") is Dictionary: return false
	if not model.get("aliases", {}) is Dictionary: return false
	for id in model.get("aliases", {}):
		if not id is String or not model.aliases[id] is String or model.aliases[id].is_empty(): return false
	for group in ["profiles", "solid_profiles"]:
		for id in model[group]:
			if not id is String or id.is_empty() or not _profile(model[group][id]): return false
	for attr in ATTRS:
		var points: Variant = model.curves.get(attr)
		if not points is Array or points.size() < 2: return false
		var previous_x := -1.0
		var previous_y := -1.0
		for point in points:
			if not point is Array or point.size() != 2: return false
			if not _number(point[0]) or not _number(point[1]): return false
			var x := float(point[0])
			var y := float(point[1])
			if x < 0.0 or x > 100.0 or y < 0.0 or y > 100.0: return false
			if x <= previous_x or y < previous_y: return false
			previous_x = x
			previous_y = y
		if points[0] != [0.0, 0.0] or points[-1] != [100.0, 100.0]: return false
	for group in ["neutral_solids", "excluded_ids", "known_solids", "fruit_liquids", "pulp_solids"]:
		if not model.get(group) is Array: return false
		for id in model[group]:
			if not id is String or id.is_empty(): return false
	if not _number(model.get("fruit_heavy_fraction")) or float(model.fruit_heavy_fraction) < 0.0 or float(model.fruit_heavy_fraction) > 1.0: return false
	if not model.get("unit_conversions") is Dictionary: return false
	if not _number(model.unit_conversions.get("dash_to_ml")) or float(model.unit_conversions.dash_to_ml) <= 0.0: return false
	return true

static func _zero_attributes() -> Dictionary:
	var result: Dictionary = {}
	for attr in ATTRS: result[attr] = 0.0
	return result

static func _issue(missing: Array, issue: String) -> void:
	if not missing.has(issue): missing.append(issue)

static func _sku(id: Variant, definitions: Dictionary, model: Dictionary) -> String:
	if not (id is String or id is StringName): return ""
	var key := str(id)
	var definition: Variant = definitions.get(key, {})
	var resolved := str(definition.get("sku_id", key)) if definition is Dictionary else key
	return str(model.get("aliases", {}).get(resolved, resolved))

static func _response(raw: float, points: Array) -> float:
	var value := clampf(raw, 0.0, 100.0)
	for index in range(1, points.size()):
		var right: Array = points[index]
		if value <= float(right[0]):
			var left: Array = points[index - 1]
			var fraction := (value - float(left[0])) / (float(right[0]) - float(left[0]))
			var result := lerpf(float(left[1]), float(right[1]), fraction)
			# Removes floating-point residue at calibration knots without integer rounding.
			return float(roundi(result)) if absf(result - roundf(result)) < 0.00000001 else result
	return 100.0

static func evaluate(contents: Dictionary, solids: Dictionary, definitions: Dictionary = {}, model: Dictionary = {}) -> Dictionary:
	var selected: Dictionary = snapshot() if model.is_empty() else model
	var result := {"attributes": _zero_attributes(), "raw_attributes": _zero_attributes(), "missing": [], "version": selected.get("version", VERSION), "data_complete": false, "volume_ml": 0.0}
	if not valid_model(selected):
		result.missing.append("sensory_model")
		return result
	var totals: Array = [0.0, 0.0, 0.0, 0.0]
	var volume := 0.0
	for id in contents:
		var sku := _sku(id, definitions, selected)
		var amount: Variant = contents[id]
		if sku.is_empty() or not _number(amount) or float(amount) < 0.0:
			_issue(result.missing, "invalid_quantity:" + str(id))
			continue
		if float(amount) == 0.0 or selected.excluded_ids.has(sku): continue
		volume += float(amount)
		if not selected.profiles.has(sku):
			_issue(result.missing, sku)
			continue
		var profile: Array = selected.profiles[sku]
		for index in range(ATTRS.size()): totals[index] += float(amount) * float(profile[index])
	for id in solids:
		var sku := _sku(id, definitions, selected)
		var amount: Variant = solids[id]
		if sku.is_empty() or not _number(amount) or float(amount) < 0.0:
			_issue(result.missing, "invalid_quantity:" + str(id))
			continue
		if float(amount) == 0.0 or selected.excluded_ids.has(sku) or selected.neutral_solids.has(sku): continue
		if not selected.solid_profiles.has(sku):
			_issue(result.missing, sku)
			continue
		var profile: Array = selected.solid_profiles[sku]
		for index in range(ATTRS.size()): totals[index] += float(amount) * float(profile[index])
	if not is_finite(volume):
		_issue(result.missing, "quantity_overflow")
		return result
	for total in totals:
		if not is_finite(float(total)):
			_issue(result.missing, "quantity_overflow")
			return result
	result.volume_ml = volume
	if volume <= 0.0:
		_issue(result.missing, "empty_cup")
		return result
	for index in range(ATTRS.size()):
		var attr: String = ATTRS[index]
		var raw: float = float(totals[index]) / volume
		result.raw_attributes[attr] = raw
		result.attributes[attr] = _response(raw, selected.curves[attr])
	result.data_complete = result.missing.is_empty()
	return result

static func standard(recipe: Dictionary, model: Dictionary = {}) -> Dictionary:
	var selected: Dictionary = snapshot() if model.is_empty() else model
	var contents: Dictionary = {}
	var solids: Dictionary = {}
	var unresolved: Array = []
	if not valid_model(selected): return evaluate(contents, solids, {}, selected)
	var rows: Variant = recipe.get("ingredient_rows", [])
	if not rows is Array or rows.is_empty(): rows = recipe.get("ingredients", [])
	if rows is Dictionary:
		# Workbench snapshots use a dictionary of measured liquid ml.
		for id in rows:
			var amount: Variant = rows[id]
			if not (id is String or id is StringName) or not _number(amount) or float(amount) <= 0.0:
				_issue(unresolved, "invalid_quantity:" + str(id))
				continue
			var sku := _sku(id, {}, selected)
			contents[sku] = float(contents.get(sku, 0.0)) + float(amount)
	elif rows is Array:
		for row in rows:
			if not row is Dictionary:
				_issue(unresolved, "invalid_ingredient")
				continue
			var sku := str(row.get("sku_id", ""))
			var use := str(row.get("use", ""))
			if use.contains("装饰") or use.to_lower() == "garnish" or selected.excluded_ids.has(sku): continue
			if sku.is_empty():
				_issue(unresolved, "missing_sku")
				continue
			var unit := str(row.get("inventory_unit", row.get("unit", "")))
			var source_unit := str(row.get("unit", unit))
			var amount: Variant = row.get("inventory_amount")
			if amount == null and source_unit == unit: amount = row.get("amount")
			if amount == null and unit == "ml" and source_unit == "dash" and _number(row.get("amount")):
				amount = float(row.amount) * float(selected.unit_conversions.dash_to_ml)
			if not _number(amount) or float(amount) <= 0.0:
				_issue(unresolved, "unresolved_quantity:" + sku)
				continue
			if unit == "ml":
				contents[sku] = float(contents.get(sku, 0.0)) + float(amount)
			elif unit == "g" or selected.neutral_solids.has(sku):
				solids[sku] = float(solids.get(sku, 0.0)) + float(amount)
			else:
				_issue(unresolved, "unsupported_unit:" + sku)
	else:
		_issue(unresolved, "invalid_ingredients")
	var result := evaluate(contents, solids, {}, selected)
	for issue in unresolved: _issue(result.missing, str(issue))
	result.data_complete = result.missing.is_empty()
	result.contents = contents
	result.solids = solids
	return result
