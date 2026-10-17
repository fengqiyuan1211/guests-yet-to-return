extends Node
var failures: Array[String]=[]
var count:=0
var serial:=0
var page: Control
var baseline: Dictionary
var bench_before: Dictionary
var wallet_before: int
var guide: Control
func check(ok: bool,message: String) -> void:
	count+=1
	if not ok:
		failures.append(message)
		push_error(message)
func op(kind: String,payload: Dictionary={}) -> bool:
	serial+=1
	var ok:=WorkbenchSession.command("opening-qa-%s-%d"%["resume" if "--opening-resume" in OS.get_cmdline_user_args() else "seed",serial],str(WorkbenchSession.state.session.get("id","")),kind,payload)
	check(ok,kind+": "+WorkbenchSession.last_error)
	return ok
func settle() -> void:
	await get_tree().process_frame
	await get_tree().process_frame
func capture(label: String) -> void:
	if DisplayServer.get_name()=="headless": return
	await get_tree().create_timer(.8).timeout
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute("/tmp/opening-preview")
	get_viewport().get_texture().get_image().save_png("/tmp/opening-preview/"+label+".png")
func show_scene(path: String) -> void:
	if is_instance_valid(page):
		page.queue_free()
		await settle()
	page=load(path).instantiate()
	add_child(page)
	await settle()
func _ready() -> void:
	call_deferred("run")
func run() -> void:
	if not GameSession.save_path.begins_with("/tmp/") or not Supplies.save_path.begins_with("/tmp/"): get_tree().quit(2); return
	OpeningFlow.front_end=true
	TimeManager.set_running(false)
	if not "--opening-resume" in OS.get_cmdline_user_args():
		check(preload("res://tests/workbench_fixture.gd").seed(Supplies,WorkbenchSession),"prepare pre-existing warehouse")
		op("start")
		op("withdraw",{"material":"gin","ml":22,"vessel":"mixing"})
	baseline=Supplies.inventory.serialize().duplicate(true)
	bench_before=WorkbenchSession.snapshot()
	wallet_before=SlotWallet.balance
	if "--opening-resume" in OS.get_cmdline_user_args():
		check(OpeningFlow.state.phase=="tutorial","process restart restores tutorial phase")
		check(OpeningFlow.begin_tutorial(),"restore actual cup")
		check(WorkbenchSession.state.session.vessels.shaker.contents.gin==22.5,"same measured liquid restored")
		check(OpeningFlow.state.stock.sku_gin_london_dry==112.5,"same stock restored in same transaction")
		await show_scene("res://scenes/workbench.tscn")
		guide=page.surface.get_node("OpeningTutorialGuide")
	else:
		check(OpeningFlow.state.phase=="new","fresh player starts on title")
		await show_scene("res://scenes/title_screen.tscn")
		var minute:=TimeManager.minutes_since_midnight
		TimeManager._process(100)
		check(TimeManager.minutes_since_midnight==minute,"title pauses business time")
		check(SaloonAudio.active_path==SaloonAudio.SCENE_TRACKS.title,"title uses chosen Laura music")
		await capture("01-title")
		if DisplayServer.get_name()!="headless":
			var bg: TextureRect=page.stage.get_child(0)
			bg.set_process(false)
			bg.material.set_shader_parameter("clock",0.0)
			await RenderingServer.frame_post_draw
			var first:=get_viewport().get_texture().get_image()
			bg.material.set_shader_parameter("clock",4.0)
			await RenderingServer.frame_post_draw
			var second:=get_viewport().get_texture().get_image()
			var water_change:=0.0
			var land_change:=0.0
			for x in range(100,400,13):
				for y in range(520,680,17):
					water_change+=absf(first.get_pixel(x,y).r-second.get_pixel(x,y).r)
				for y in range(20,80,17):
					land_change+=absf(first.get_pixel(x,y).r-second.get_pixel(x,y).r)
			check(water_change>.1 and land_change<.001,"rendered waves move water while sky stays stable")
			bg.set_process(true)
		check(OpeningFlow.begin_story(),"start CG")
		await show_scene("res://scenes/opening_story.tscn")
		page._advance()
		check(page.dialogue.visible_characters==page.dialogue.text.length(),"space reveals complete line")
		var index:=int(OpeningFlow.state.node)
		page._advance()
		check(OpeningFlow.state.node==index+1,"next space advances once")
		await capture("02-apartment")
		for i in range(page.nodes.size()):
			var node: Dictionary=page.nodes[i]
			check(ResourceLoader.exists("res://assets/art/saloon-day-unlit-v2.png" if node.background=="saloon" else "res://assets/art/opening/"+str(node.background)+".png"),"CG resource "+str(i))
			if node.has("choices"):
				OpeningFlow.advance(i)
				OpeningFlow.advance(i,str(node.choices[0].text))
				check(OpeningFlow.state.choices[str(node.id)]==node.choices[0].text,"choice persists by stable story ID")
		var old_ids: Array=JSON.parse_string(FileAccess.get_file_as_string("res://data/opening/story-v1-index.json"))
		var old_save:=OpeningFlow.fresh()
		for field in ["story_version","node_id","mail_read"]: old_save.erase(field)
		old_save.node=old_ids.find("s03_10")
		old_save.choices={str(old_save.node):"那就替我留个位置。"}
		var upgraded: Dictionary=OpeningFlow.upgrade_story_progress(old_save)
		check(OpeningFlow.valid(upgraded) and upgraded.node_id=="s03_10" and upgraded.node==OpeningFlow.node_index("s03_10"),"legacy offsets map to original dialogue after insertion")
		check(upgraded.choices.get("s03_10")=="那就替我留个位置。" and not old_save.has("node_id"),"legacy choice preserved and source untouched")
		old_save.node=9999
		check(not OpeningFlow.valid(OpeningFlow.upgrade_story_progress(old_save)),"corrupt legacy index is rejected without guessing")
		for id in ["s01_young_01","s01_depart_03"]:
			OpeningFlow.advance(OpeningFlow.node_index(id))
			page._render()
			await capture("02-"+id)
		var mail_index:=OpeningFlow.node_index("s01_04")
		OpeningFlow.advance(mail_index)
		page._render()
		await capture("02-mail-notification")
		page.mail_button.pressed.emit()
		await settle()
		page._advance()
		check(is_instance_valid(page.mail_reader) and OpeningFlow.state.node==mail_index and not OpeningFlow.state.mail_read.get("handover_notice",false),"opening reader and repeated advance do not skip unread mail")
		await capture("02-mail-open")
		var mail_path:=OpeningFlow.save_path
		OpeningFlow.save_path+="/unwritable"
		page._read_mail()
		OpeningFlow.save_path=mail_path
		check(is_instance_valid(page.mail_reader) and not OpeningFlow.state.mail_read.get("handover_notice",false),"failed read save leaves letter open and unread")
		var escape:=InputEventKey.new()
		escape.pressed=true
		escape.keycode=KEY_ESCAPE
		page._unhandled_key_input(escape)
		check(not is_instance_valid(page.mail_reader) and OpeningFlow.state.node==mail_index,"Escape closes mail without quitting story or marking read")
		await show_scene("res://scenes/opening_story.tscn")
		check(page.active_mail_id=="handover_notice","re-entering an unread mail node restores notification")
		page._open_mail()
		page.mail_reader.read_requested.emit()
		await settle()
		var saved_mail: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(OpeningFlow.save_path))
		check(saved_mail.mail_read.get("handover_notice",false) and OpeningFlow.state.node==mail_index+1,"read button persists and advances exactly one node")
		OpeningFlow.advance(OpeningFlow.node_index("s04_00"))
		page._render()
		page._open_mail()
		await settle()
		await capture("02-private-letter")
		page._read_mail()
		check(OpeningFlow.state.mail_read.get("private_letter",false),"personal letter has its own durable read state")
		OpeningFlow.advance(OpeningFlow.node_index("s02_11"))
		page._render()
		await capture("03-city-bar")
		check(OpeningFlow.begin_tutorial(),"enter isolated tutorial: "+OpeningFlow.last_error)
		if not WorkbenchSession.tutorial_active:
			print("DIAGNOSTIC ",MenuCatalog.last_error," db=",CocktailDatabase.last_error)
			for recipe: Dictionary in MenuCatalog._finished_recipes():
				var q: Dictionary=preload("res://scripts/drink_pricing.gd").quote(recipe)
				if not q.ok: print(recipe.id," ",q)
			await finish()
			return
		await show_scene("res://scenes/workbench.tscn")
		guide=page.surface.get_node("OpeningTutorialGuide")
		check(guide.next_step(page.data).key=="cup","tutorial starts at choosing coupe")
		await capture("04-tutorial")
		op("cup",{"cup":"coupe"})
		await settle()
		check(guide.mouse_filter==Control.MOUSE_FILTER_IGNORE and guide.gesture=="drag","visual guide leaves real input available and demonstrates dragging")
		await capture("04b-tutorial-drag")
		page._begin_measure("gin",22.5,"jigger")
		await settle()
		check(guide.gesture=="space" and guide.visible,"dosing replaces drag demonstration with space cue above the modal")
		await capture("04c-tutorial-space")
		page._clear_modal()
		await settle()
		check(WorkbenchSession.dose_target("gin",page.data)==22.5,"gold target follows recipe")
		var id: String=WorkbenchSession.state.session.id
		check(WorkbenchSession.command("first-dose",id,"withdraw",{"material":"gin","ml":22.5}),"real jigger dose")
		check(WorkbenchSession.command("first-dose",id,"withdraw",{"material":"gin","ml":22.5}),"duplicate dose accepted idempotently")
		check(OpeningFlow.state.stock.sku_gin_london_dry==112.5,"duplicate did not deduct again")
		op("transfer",{"source":"jigger","vessel":"shaker"})
		check(OpeningFlow.state.stock.sku_gin_london_dry==112.5,"transfer is not consumption")
		check(Supplies.inventory.serialize()==baseline and SlotWallet.balance==wallet_before,"tutorial never consumes warehouse or coins")
		if "--opening-seed" in OS.get_cmdline_user_args():
			finish()
			return
	for row in [["sku_bleu_de_minuit",22.5],["sku_maraschino",22.5],["lime",22.5]]:
		op("withdraw",{"material":row[0],"ml":row[1],"vessel":"jigger"})
		op("transfer",{"source":"jigger","vessel":"shaker"})
	for i in range(3): op("ice",{"vessel":"shaker","ice":"cube"})
	op("lid")
	for i in range(14): op("shake",{"vessel":"shaker","seconds":.5,"control":1.0})
	check(guide.next_step(page.data).key=="pour","guide recognizes shake duration")
	op("filter",{"source":"shaker","vessel":"glass","integrated_strainer":true})
	check(guide.next_step(page.data).key=="finish","after pouring never asks to refill shaker")
	check(WorkbenchSession.amount(page.data.vessels.glass)>=90,"whole recipe fits coupe")
	check(WorkbenchSession.ice_mass(page.data.vessels.shaker)==150,"strainer retains ice")
	var tint: Color=preload("res://scripts/workbench_liquid_appearance.gd").sample(page.data.vessels.glass.contents).color
	check(tint.b>tint.r*1.5 and tint.b>tint.g*1.5 and tint.g>tint.r*1.3 and tint.b>.7 and tint.a<.85,"actual mixed drink is transparent cobalt")
	check(page.data.recipe.ingredients.size()==4 and page.data.recipe.ingredients.values().all(func(v): return is_equal_approx(float(v),22.5)),"all four ingredients use confirmed equal parts")
	var shop_ids: Array=[]
	for item: Dictionary in Supplies.list_shop_items(): shop_ids.append(item.id)
	check(shop_ids.has("sku_bleu_de_minuit") and not shop_ids.has("sku_blue_curacao"),"shop offers midnight herb, retired blue curacao is hidden")
	check(MenuCatalog.get_recipe("last_word").ingredients.any(func(r): return r.sku_id=="sku_green_chartreuse"),"classic Last Word keeps green Chartreuse")
	await capture("05-blue-echo")
	var proper: Dictionary=page.data.duplicate(true)
	var bad: Dictionary=proper.duplicate(true)
	bad.actions=bad.actions.filter(func(a: Dictionary): return a.kind!="shake")
	var definitions:=WorkbenchSession.draft_definitions()
	var eval=preload("res://scripts/workbench_evaluation.gd")
	check(eval.evaluate(bad,definitions).score<eval.evaluate(proper,definitions).score,"omitting shake genuinely lowers quality")
	var before_failure:=WorkbenchSession.snapshot()
	var stock_before: Dictionary=OpeningFlow.state.stock.duplicate(true)
	var path:=OpeningFlow.save_path
	OpeningFlow.save_path+="/unwritable"
	check(not WorkbenchSession.command("fail-dose",str(page.data.id),"withdraw",{"material":"gin","ml":3,"vessel":"mixing"}),"failed tutorial save rejects action")
	OpeningFlow.save_path=path
	check(WorkbenchSession.snapshot()==before_failure and OpeningFlow.state.stock==stock_before,"failed save preserves cup and stock atomically")
	op("finish")
	check(float(page.data.result.evaluation.score)>=95,"correct midnight herbal recipe receives high quality")
	page._result()
	await capture("06-result")
	check(OpeningFlow.finish_tutorial(),"real finished cup completes tutorial")
	check(not WorkbenchSession.tutorial_active,"leaving restores normal workshop")
	check(Supplies.inventory.serialize()==baseline and SlotWallet.balance==wallet_before,"full tutorial preserves warehouse wallet")
	check(WorkbenchSession.state.session==bench_before.session,"normal work in progress restored exactly")
	await show_scene("res://scenes/opening_story.tscn")
	await capture("07-ready-to-open")
	get_tree().current_scene=null
	check(OpeningFlow.finish_opening(),"opening enters real home")
	await settle()
	check(OpeningFlow.state.phase=="ready" and OpeningFlow.state.reward_claimed,"completion durable")
	check(MenuCatalog.unlocked_ids.has("echo_world"),"echo unlocked in codex")
	TimeManager._process(5)
	await settle()
	check(TimeManager.is_open and StoryDialogue.guest_id=="milo","first evening opens with Milo")
	check(not OpeningFlow.arrival_pending(),"arrival consumed once")
	var actual_state:=OpeningFlow.state.duplicate(true)
	var story_before:=StoryDialogue.session_snapshot()
	check(OpeningFlow.begin_replay(),"existing player can replay without reset")
	check(OpeningFlow.begin_tutorial(),"replay uses isolated practice materials")
	check(OpeningFlow.finish_tutorial(true),"optional skip leads to ending")
	check(OpeningFlow.finish_opening(),"replay returns to title")
	await settle()
	check(OpeningFlow.state==actual_state and not OpeningFlow.replaying,"replay restores actual story phase")
	check(StoryDialogue.session_snapshot()==story_before and Supplies.inventory.serialize()==baseline,"replay does not change formal guest or stock")
	print("OPENING: %d checks, %d failures" % [count,failures.size()])
	get_tree().quit(0 if failures.is_empty() else 1)
func finish() -> void:
	if is_instance_valid(page):
		page.queue_free()
		await settle()
	print("OPENING: %d checks, %d failures" % [count,failures.size()])
	get_tree().quit(0 if failures.is_empty() else 1)
