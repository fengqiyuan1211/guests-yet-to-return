extends "res://tests/verify_workbench_stir_audio.gd"
const State=preload("res://scripts/workbench_liquid_state.gd")

func _ready() -> void:
	if "--liquid-resume" in OS.get_cmdline_user_args():
		if not str(Supplies.save_path).begins_with("/tmp/"): get_tree().quit(2); return
		call_deferred("verify_restored_liquid")
		return
	super._ready()

func verify_restored_liquid() -> void:
	var s: Dictionary=WorkbenchSession.state.session
	check(WorkbenchSession.writable and s.get("status")=="finished","separate process restores finished liquid")
	check(s.result.contents.layers.size()==1 and s.vessels.mixing.layers.size()==3,"uniform result and untouched layered vessel survive restart")
	check(s.result.liquid_profiles==s.liquid_profiles and s.liquid_model.version=="layers-v1","appearance snapshots and algorithm version survive restart")
	check(is_equal_approx(WorkbenchSession.remaining("gin"),480) and WorkbenchSession._valid_session(s),"stock and layer ledgers remain consistent after restart")
	print("LIQUID RESTORE: %d checks, %d failures" % [count,failures.size()])
	get_tree().quit(0 if failures.is_empty() else 1)

func op(kind: String,payload: Dictionary={}) -> void:
	check(bench._issue(kind,payload),kind+": "+WorkbenchSession.last_error)

func run() -> void:
	Supplies.inventory.purchase("sku_sweet_red_vermouth",2)
	check(Supplies._write(Supplies.inventory.serialize(),Supplies.workbench),"seed visual fixture")
	Supplies.changed.emit()
	WorkbenchSession.reset_game()
	home=load("res://scenes/home.tscn").instantiate()
	add_child(home)
	await settle()
	Navigation.go_to(&"mixing")
	await settle()
	bench=home.active_page
	op("cup",{"cup":"highball"})
	for target in ["glass","mixing"]:
		op("withdraw",{"vessel":target,"material":"sku_sweet_red_vermouth","ml":60})
		op("withdraw",{"vessel":target,"material":"lime","ml":60})
		op("withdraw",{"vessel":target,"material":"gin","ml":60})
	await get_tree().create_timer(1.3).timeout
	await capture("52-liquid-layers")
	check(bench.table.layers_for("glass").size()==3 and bench.table.layers_for("mixing").size()==3,"table displays three liquid layers in both glasses")
	op("spoon",{"target":"glass"})
	bench._select("glass")
	op("stir",{"vessel":"glass","seconds":.5,"control":1})
	op("stir",{"vessel":"glass","seconds":.5,"control":1})
	await get_tree().create_timer(1.3).timeout
	await capture("53-liquid-partial-mix")
	for i in range(20): op("stir",{"vessel":"glass","seconds":.5,"control":1})
	await get_tree().create_timer(1.3).timeout
	await capture("54-liquid-fully-mixed")
	check(bench.data.vessels.glass.layers.size()==1,"stirred cup becomes uniform while mixing glass remains layered")
	bench._finish()
	await settle()
	await capture("55-liquid-finished")
	check(bench.data.result.contents.layers.size()==1 and bench.data.result.has("liquid_profiles"),"result preview uses frozen layers and profiles")
	check(WorkbenchSession.load_state(),"native session reload")
	print("LIQUID VISUAL: %d checks, %d failures" % [count,failures.size()])
	home.queue_free()
	await settle()
	get_tree().quit(0 if failures.is_empty() else 1)
