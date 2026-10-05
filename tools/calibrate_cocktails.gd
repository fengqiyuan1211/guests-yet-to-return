extends SceneTree
## Rebuild canonical standard-cup fields using the exact runtime evaluator.
const Sensory := preload("res://scripts/sensory_model.gd")
const FIELDS := ["alcohol_intensity", "sweetness", "sourness", "bitterness"]
func _initialize() -> void:
	var catalog: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://data/cocktails/catalog.json"))
	if not catalog is Dictionary or not catalog.get("cocktails") is Array:
		push_error("Cannot read catalog")
		quit(1)
		return
	var model := Sensory.snapshot()
	for record: Dictionary in catalog.cocktails:
		var result := Sensory.standard(record, model)
		if not result.data_complete:
			push_error("Incomplete standard: " + str(record.id) + " " + str(result.missing))
			quit(1)
			return
		if not record.has("reference_attributes"):
			record.reference_attributes = {}
			for field in FIELDS: record.reference_attributes[field] = record[field]
		for field in FIELDS: record[field] = snappedf(float(result.attributes[field]), 0.000001)
		record["sensory_model_version"] = result.version
		record["scores_basis"] = "标准配方由共享感官模型计算"
	catalog["sensory_model_version"] = model.version
	var destination := "res://data/cocktails/catalog.json"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--output="): destination = arg.trim_prefix("--output=")
	var file := FileAccess.open(destination, FileAccess.WRITE)
	if file == null:
		push_error("Cannot save catalog")
		quit(1)
		return
	file.store_string(JSON.stringify(catalog, "  ") + "\n")
	file.close()
	print(JSON.stringify({"calibrated":catalog.cocktails.size(), "model":model.version, "output":destination}))
	quit(0)
