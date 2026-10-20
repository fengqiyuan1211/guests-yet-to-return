extends "res://tests/verify_opening.gd"
const Prep=preload("res://scripts/opening_preparation.gd")
var mode:=""
func _ready() -> void:
	if not GameSession.save_path.begins_with("/tmp/"): get_tree().quit(2); return
	TimeManager.set_running(false)
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--lesson-"): mode=arg
	call_deferred("run")
func action(kind: String,payload: Dictionary={}) -> void:
	serial+=1
	check(WorkbenchSession.command(mode+str(serial),str(WorkbenchSession.state.session.get("id","")),kind,payload),kind+": "+WorkbenchSession.last_error)
func capture(label: String) -> void:
	if DisplayServer.get_name()=="headless": return
	await get_tree().create_timer(.3).timeout
	# A background test window may stop scheduling draw notifications on macOS.
	RenderingServer.force_draw()
	DirAccess.make_dir_recursive_absolute("/tmp/opening-preview")
	get_viewport().get_texture().get_image().save_png("/tmp/opening-preview/"+label+".png")

func talk(shop: Control) -> void:
	await pointer_click(shop.topic_button)
	var n:=0
	while is_instance_valid(shop.merchant_dialogue) and n<20:
		n+=1
		await pointer_click(shop.merchant_dialogue.next_button)
	check(n<20,"native merchant dialogue completes")
func run() -> void:
	if mode=="--lesson-seed":
		check(OpeningFlow.begin_story() and OpeningFlow.begin_tutorial() and OpeningFlow.finish_tutorial(true),"finish echo tutorial")
		check(OpeningFlow.begin_departure(),"begin departure")
		check(OpeningFlow.update_departure({"node":"prepare","signed":true,"water":true}),"reach actual procurement lesson")
		await show_scene("res://scenes/opening_departure.tscn")
		await settle()
		var lesson: Control=page.preparation
		var shop: Control=lesson.page
		check(shop.get_script().resource_path=="res://scripts/harbor_shop.gd","directly enters production shop, no preparation invoice")
		check(not shop.opening_visit,"native merchant conversations enabled")
		await capture("shop-lesson-01-intro")
		await talk(shop)
		check(not lesson.guide._purchase_reason("sku_gin_london_dry",5).is_empty(),"tutorial protects opening budget from excess purchase")
		check(Relationships.state.flags.get("done:merchant_intro",false),"native intro persisted")
		for sku in ["sku_gin_london_dry","sku_tonic_water","sku_lime_wedge"]:
			lesson.guide.refresh()
			check(shop.selected_id==sku,"guide selects next missing item: "+sku)
			if sku=="sku_tonic_water":
				await pointer_click(shop.find_child("QuantityPlus",true,false))
			await pointer_click(shop.buy_button)
			lesson.guide.refresh()
		check(SlotWallet.balance==166,"real fresh budget 300 minus purchases 134")
		check(Prep.report("gin_and_tonic").ready,"warehouse now contains recipe ingredients")
		await talk(shop)
		lesson.guide.refresh()
		check(Relationships.state.flags.get("done:merchant_seed",false),"relationship seed heard in real shop")
		check(MenuCatalog.entries.is_empty(),"no automatic listing on purchase")
		await capture("shop-lesson-02-purchased")
		await pointer_click(lesson.guide.proceed)
		await settle()
		var bench: Control=lesson.page
		check(bench.data.get("opening_practice",false),"new actual-stock lesson session")
		check(not WorkbenchSession.tutorial_active,"no free Echo sandbox for second cup")
		check(bench.data.recipe.id=="gin_and_tonic" and bench.data.cup=="highball","frozen recipe and correct cup")
		check(MenuCatalog.entries.is_empty(),"unlisted recipe permitted only for opening practice")
		await capture("shop-lesson-03-ice")
		for i in range(3): action("ice",{"ice":"cube","vessel":"glass"})
		bench._begin_measure("gin",50,"jigger")
		check(bench.measure.precise and bench.measure.target==50,"jigger exposes 50 ml target")
		bench.measure.progress=50.0/bench.measure.volume_limit()
		await key_press(KEY_SPACE)
		check(Supplies.total_remaining("sku_gin_london_dry")==700,"real 50 ml consumption before transfer")
		check(SlotWallet.balance==166,"no sale or extra fee")
	elif mode=="--lesson-resume":
		check(OpeningFlow.state.departure.lesson.phase=="mixing","phase survives process restart")
		check(WorkbenchSession.state.session.vessels.jigger.contents.gin==50,"half cup survives restart")
		await show_scene("res://scenes/opening_departure.tscn")
		await settle()
		var lesson: Control=page.preparation
		var bench: Control=lesson.page
		var g: Control=bench.surface.find_child("OpeningTutorialGuide",true,false)
		check(g.next_step(bench.data).key=="transfer_stock","resumed guide points to filled jigger")
		action("transfer",{"source":"jigger","vessel":"glass"})
		check(Supplies.total_remaining("sku_gin_london_dry")==700,"transfer cannot deduct stock twice")
		bench._begin_measure("sku_tonic_water",150,"glass")
		check(not bench.measure.precise,"direct tonic pour keeps its by-eye interaction")
		bench.measure.progress=150.0/bench.measure.volume_limit()
		await key_press(KEY_SPACE)
		action("spoon",{"target":"glass"})
		await settle()
		check(g.next_step(bench.data).key=="stir","guide explains gentle stirring")
		await capture("shop-lesson-04-stir")
		for i in range(6): action("stir",{"vessel":"glass","seconds":.5})
		check(g.next_step(WorkbenchSession.state.session).key=="remove_spoon","three seconds matches evaluation rule")
		action("spoon",{"target":""})
		action("garnish",{"material":"garnish"})
		check(g.next_step(WorkbenchSession.state.session).key=="finish","all steps finish instead of requesting refills")
		await settle()
		bench._finish()
		await settle()
		check(bench.data.status=="finished","real evaluation produced")
		check(MenuCatalog.entries.is_empty(),"result still requires explicit publication")
		await capture("shop-lesson-05-quality")
		await pointer_click(button_named(bench,"确认这杯，加入今晚酒单 →"))
		check(OpeningFlow.state.departure.node=="ready","result returns to opening story")
		check(MenuCatalog.entries.size()==1 and MenuCatalog.entries[0].id=="gin_and_tonic","explicit confirmed listing")
		check(SlotWallet.balance==166,"practice earns no sales money")
		var advance_count:=0
		while OpeningFlow.state.departure.node!="turn_sign" and advance_count<15:
			advance_count+=1
			page.dialogue.visible_characters=-1
			await pointer_click(page.next_button)
		await capture("shop-lesson-06-open")
		# Let the normal scene transition own the production home scene.
		get_tree().current_scene=null
		page.dialogue.visible_characters=-1
		await pointer_click(page.next_button)
		await get_tree().create_timer(9).timeout
		await settle_opening_transition()
		check(OpeningFlow.state.phase=="ready","opening sign automatically finishes tutorial")
		check(get_tree().current_scene!=null and get_tree().current_scene.scene_file_path=="res://scenes/home.tscn","remains in game, never goes to title")
		check(TimeManager.is_open and StoryDialogue.guest_id=="milo","time fast-forwarded, first guest arrived")
		check(not OpeningFlow.state.arrival_pending,"arrival acknowledged without extra button")
		page.queue_free()
		page=null
		await capture("shop-lesson-07-first-guest")
	else:
		check(OpeningFlow.state.phase=="ready" and not OpeningFlow.state.arrival_pending,"completed tutorial survives restart")
		check(Supplies.total_remaining("sku_gin_london_dry")==700 and SlotWallet.balance==166,"no repeated purchases or material deductions")
		check(MenuCatalog.entries.size()==1,"menu publication not duplicated")
	print("SHOP LESSON ",mode,": ",count," checks, ",failures.size()," failures")
	get_tree().quit(0 if failures.is_empty() else 1)
