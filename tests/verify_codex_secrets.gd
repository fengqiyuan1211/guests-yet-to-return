extends Node
var failures:=0
func check(value: bool,label: String) -> void:
	if not value: failures+=1; push_error(label)
func _ready() -> void:
	if not WorkbenchSession.save_path.begins_with("/tmp/"): get_tree().quit(2); return
	await get_tree().process_frame
	var codex=load("res://scripts/codex.gd").new()
	var original: Dictionary=WorkbenchSession.state.research.duplicate(true)
	WorkbenchSession.state.research.acquired={}
	for filter in [0,1,2]:
		codex.selected_filter=filter
		for recipe in codex._visible_recipes():
			check(str(recipe.get("source_guest","")).is_empty() and recipe.get("unlock_kind")!="legendary_mastery","secret hidden in all filters")
	for id in ["character_milo","character_ada","character_hank","childhood_keepsake"]:
		check(codex._recipe(id).is_empty(),"secret detail hidden: "+id)
	WorkbenchSession.state.research.acquired.character_milo="test"
	codex.selected_filter=0
	var found:=0
	for recipe in codex._visible_recipes():
		if recipe.id=="character_milo": found+=1
	check(found==1,"earned reward appears exactly once")
	check(not codex._recipe("character_milo").is_empty(),"earned detail available")
	check(codex._recipe("character_ada").is_empty(),"other reward remains hidden")
	check(not codex._recipe("gin_and_tonic").is_empty(),"classic recipe preserved")
	WorkbenchSession.state.research=original
	codex.free()
	print("CODEX SECRETS failures: ",failures)
	get_tree().quit(0 if failures==0 else 1)
