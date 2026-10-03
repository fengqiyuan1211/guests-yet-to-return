extends "res://tests/verify_workbench_stir_audio.gd"

func finish_fade() -> void:
	if is_instance_valid(SaloonAudio.fade): SaloonAudio.fade.custom_step(4.0)

func sweep(center: Vector2, speed: float) -> void:
	# Straight sweeps rather than circles; the visual orbit must still run.
	for i in range(24):
		motion(center+Vector2(sin(i*.35)*speed,0))
		await get_tree().create_timer(.025).timeout

func run() -> void:
	WorkbenchSession.reset_game()
	check(Supplies.purchase("sku_mint_leaf"),"buy isolated mint stock")
	home=load("res://scenes/home.tscn").instantiate()
	add_child(home)
	await settle()
	var hall: String=SaloonAudio.active_path
	Navigation.go_to(&"mixing")
	await settle()
	bench=home.active_page
	check(SaloonAudio.active_path==SaloonAudio.WORKBENCH_TRACK and SaloonAudio.active_path!=hall,"workbench uses a different track on shared music decks")
	check(SaloonAudio._stream_for(SaloonAudio.WORKBENCH_TRACK).get_length()>260,"complete licensed music imports")
	finish_fade()
	check(SaloonAudio.players.size()==2,"no extra music player")
	bench._act("cup",{"cup":"highball"})
	bench._issue("withdraw",{"material":"gin","ml":50,"vessel":"mixing"})
	check(bench._issue("add_solid",{"material":"sku_mint_leaf","vessel":"mixing"}),"mint enters mixing glass")
	bench._act("ice",{"vessel":"mixing","ice":"cube"})
	bench._act("ice",{"vessel":"mixing","ice":"crushed"})
	bench._show_category("器具")
	for id in ["spoon","strainer","shaker","jigger","mixing","muddler"]:
		check(bench.item_buttons[id].tooltip_text.contains("\n"),"tool menu explains usage: "+id)
	from_pantry("spoon","mixing")
	var center: Vector2=bench.table.POS.mixing
	pointer(local_point(center),true)
	await sweep(center,12)
	var slow_rate: float=bench.table.stir_rate
	var angle: float=bench.table.stir_angle
	await get_tree().create_timer(.06).timeout
	check(absf(angle-bench.table.stir_angle)>.02,"orbit advances between input events")
	await sweep(center,60)
	check(bench.table.stir_rate>slow_rate*1.4,"faster straight mouse movement accelerates automatic orbit")
	check(actions("stir")>0 and not bench.table.moving_mixing,"straight sweeps stir rather than dragging the vessel")
	pointer(local_point(center),false)
	await get_tree().create_timer(.4).timeout
	var paused:=actions("stir")
	await get_tree().create_timer(.3).timeout
	check(actions("stir")==paused and absf(bench.table.stir_rate)<.05,"released pointer stops accrued duration and orbit")
	await capture("43-automatic-stir")
	var stock: Dictionary=WorkbenchSession.state.stock.duplicate(true)
	var start: Vector2=bench.table._rect("mixing").position+Vector2(90,220)
	drag_between(local_point(start),local_point(bench.table.POS.glass))
	check(WorkbenchSession.amount(bench.data.vessels.glass)==50 and WorkbenchSession.ice_mass(bench.data.vessels.glass)==100,"native mixing-glass drag pours liquid and both ice portions")
	check(bench.data.vessels.glass.solids.get("sku_mint_leaf")==1 and bench.data.vessels.mixing.solids.is_empty(),"direct pour carries mint and empties source")
	check(WorkbenchSession.ice_mass(bench.data.vessels.mixing)==0 and bench.data.spoon_vessel=="","direct pour empties source ice and retracts spoon")
	check(WorkbenchSession.state.stock==stock,"direct transfer does not consume stock twice")
	var saved: Dictionary=WorkbenchSession.snapshot()
	var action: Dictionary=saved.session.actions.back()
	check(WorkbenchSession.command(action.command_id,saved.session.id,action.kind,action.payload) and WorkbenchSession.state==saved,"retry transfers exactly once")
	check(WorkbenchSession.load_state() and WorkbenchSession._valid_session(WorkbenchSession.state.session),"mixed-ice transfer persists and restores")
	await get_tree().create_timer(1.2).timeout
	await capture("44-direct-all-contents")
	bench._issue("withdraw",{"material":"lime","ml":30,"vessel":"mixing"})
	check(bench._issue("add_solid",{"material":"sku_mint_leaf","vessel":"mixing"}),"mint enters mixing glass")
	bench._act("ice",{"vessel":"mixing","ice":"cube"})
	from_pantry("strainer","mixing")
	check(WorkbenchSession.amount(bench.data.vessels.glass)==80 and WorkbenchSession.ice_mass(bench.data.vessels.glass)==100,"strainer transfers only liquid")
	check(WorkbenchSession.ice_mass(bench.data.vessels.mixing)==50 and bench.data.vessels.mixing.solids.get("sku_mint_leaf")==1,"strainer leaves mint and ice")
	check(bench.table.mixing_pour_offset==Vector2.ZERO,"later filtering starts from the resting vessel")
	await get_tree().create_timer(1.2).timeout
	drag_between(local_point(start),local_point(bench.table.POS.glass))
	check(WorkbenchSession.ice_mass(bench.data.vessels.glass)==150 and WorkbenchSession.ice_mass(bench.data.vessels.mixing)==0,"can pour remaining ice and solids without liquid")
	bench._issue("withdraw",{"material":"gin","ml":90,"vessel":"mixing"})
	bench._act("ice",{"vessel":"mixing","ice":"cube"})
	var before: Dictionary=WorkbenchSession.snapshot()
	var save_path: String=Supplies.save_path
	Supplies.save_path=save_path+"/unwritable.json"
	check(not bench._issue("transfer",{"source":"mixing","vessel":"glass"}) and WorkbenchSession.state==before,"failed partial pour save leaves both containers unchanged")
	Supplies.save_path=save_path
	check(bench._issue("transfer",{"source":"mixing","vessel":"glass"}) and is_equal_approx(WorkbenchSession.amount(bench.data.vessels.glass)+WorkbenchSession.ice_mass(bench.data.vessels.glass),350),"combined ice and liquid fills available room")
	check(WorkbenchSession.amount(bench.data.vessels.mixing)>0 and not bench._issue("filter",{"source":"mixing","vessel":"glass"}),"full cup leaves remaining liquid in source")

	var popup: Control=bench.table._make_custom_tooltip(bench.ToolHelp.description("mixing"))
	popup.position=Vector2(740,440)
	bench.surface.add_child(popup)
	await capture("45-tool-help")
	check(popup.size.y>80 and popup.size.x<420,"tool popup wraps instructions at readable width")
	popup.queue_free()
	var frozen: Dictionary=MenuCatalog.get_recipe("gin_and_tonic")
	check(frozen.glass=="高球杯" and not JSON.stringify(frozen).contains("球形杯"),"menu and codex recipe consistently use highball")
	var recipe: Dictionary=WorkbenchSession.recipe_snapshot(frozen)
	check(recipe.glass=="高球杯","new sessions freeze highball recipe")
	var other:=Node.new()
	add_child(other)
	SaloonAudio.acquire_workbench(other)
	Navigation.go_to(&"menu")
	await settle()
	check(SaloonAudio.active_path==SaloonAudio.WORKBENCH_TRACK,"old page exit cannot cancel another workbench owner")
	SaloonAudio.release_workbench(other)
	other.queue_free()
	check(SaloonAudio.active_path==hall,"last workbench exit fades back to hall")
	Navigation.go_to(&"mixing")
	await settle()
	bench=home.active_page
	TimeManager.restore({"minutes":1200})
	SaloonAudio._process(0)
	check(SaloonAudio.active_path==SaloonAudio.WORKBENCH_TRACK,"clock change retains workbench atmosphere")
	Navigation.go_to(&"menu")
	await settle()
	check(SaloonAudio.active_path in SaloonAudio.NIGHT_TRACKS,"exit after clock change selects current nighttime playlist")
	finish_fade()
	var playing:=0
	for player in SaloonAudio.players:
		if player.playing: playing+=1
	check(playing==1,"rapid page and clock changes end with one audible deck")
	print("WORKBENCH FLOW: %d checks, %d failures" % [count,failures.size()])
	home.queue_free()
	await settle()
	get_tree().quit(0 if failures.is_empty() else 1)
