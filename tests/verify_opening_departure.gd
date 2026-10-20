extends "res://tests/verify_opening.gd"
const Prep=preload("res://scripts/opening_preparation.gd")
var command_serial:=0

func _ready() -> void:
	if not GameSession.save_path.begins_with("/tmp/"): get_tree().quit(2); return
	TimeManager.set_running(false)
	call_deferred("run")

func topic_to_end() -> void:
	var shop: Control=page.preparation.page
	var limit:=0
	while is_instance_valid(shop.merchant_dialogue) and limit<20:
		limit+=1
		await pointer_click(shop.merchant_dialogue.next_button)
	check(limit<20,"native merchant topic completes by mouse")

func next_line() -> void:
	while is_instance_valid(page) and page.busy: await get_tree().process_frame
	if page.row.get("action")=="sign":
		page.name_edit.text="归舟"
		await pointer_click(page.signature_button)
		return
	page.dialogue.visible_characters=page.dialogue.text.length()
	await key_press(KEY_SPACE)

func run() -> void:
	if "--departure-final" in OS.get_cmdline_user_args():
		check(Relationships.writable and Relationships.state.flags.get("invoice_seen",false),"third process restores observed evidence")
		check(Relationships.state.flags.get("done:old_invoice",false),"completed topic survives restart")
		check(Relationships.state.flags.get("guide_seen",false),"guide remains acknowledged")
		var before:=Relationships.state.duplicate(true)
		check(Relationships.reconcile() and Relationships.state==before,"third process does not re-award relationship events")
		check(not Relationships.topic_available("old_invoice"),"completed clue does not reopen as a new event")
		print("DEPARTURE FINAL: %d checks, %d failures" % [count,failures.size()])
		get_tree().quit(0 if failures.is_empty() else 1)
		return
	if "--departure-seed" in OS.get_cmdline_user_args():
		check(SlotWallet.balance==300,"real fresh budget, no test grant")
		check(OpeningFlow.begin_story() and OpeningFlow.begin_tutorial() and OpeningFlow.finish_tutorial(true),"skip practice enters authored ending")
		await show_scene("res://scenes/opening_departure.tscn")
		check(MenuCatalog.unlocked_ids.has("echo_world") and MenuCatalog.entries.is_empty(),"echo unlocked before preparation but not auto-listed")
		check(not OpeningFlow.finish_opening(),"cannot enter business without prep")
		await pointer_click(page.auto_button)
		check(page.autoplay.enabled and page._can_auto_advance(),"departure auto enabled by click for ordinary dialogue")
		await key_press(KEY_H)
		check(is_instance_valid(page.history_panel),"new story has backlog")
		check(not page._can_auto_advance(),"departure auto pauses during history")
		var node: String=OpeningFlow.state.departure.node
		await key_press(KEY_SPACE)
		check(OpeningFlow.state.departure.node==node,"backlog consumes space")
		await key_press(KEY_H)
		await key_press(KEY_A)
		check(not page.autoplay.enabled,"departure auto can be disabled by A")
		await next_line()
		check(not is_instance_valid(page.history_panel) and OpeningFlow.state.departure.node!=node,"space after history continues story")
		while OpeningFlow.state.departure.node!="prepare":
			if str(page.row.get("action",""))!="":
				check(not page._can_auto_advance(),"auto waits for player action: "+str(page.row.action))
			await next_line()
		check(not page._can_auto_advance(),"auto cannot bypass menu and shopping preparation")
		check(OpeningFlow.state.departure.signed and OpeningFlow.state.departure.water,"sign and water preserved")
		check(not TimeManager.running and not TimeManager.is_open,"preparation pauses business time")
		var echo:=Prep.report("echo_world")
		check(not echo.ready and echo.cost==394 and echo.cost>SlotWallet.balance,"real echo shortfall is disclosed")
		check(Prep.report("gin_and_tonic").cost==122,"affordable first-order route exists")
		await settle()
		var shop: Control=page.preparation.page
		check(shop.get_script().resource_path=="res://scripts/harbor_shop.gd","preparation directly opens existing shop")
		await pointer_click(shop.topic_button)
		await topic_to_end()
		check(Relationships.known("harbor_merchant"),"merchant has real identity event")
		await capture("departure-02-shop")
		shop.focus_item("sku_gin_london_dry")
		await settle()
		await pointer_click(shop.buy_button)
		check(Supplies.total_remaining("sku_gin_london_dry")==750 and SlotWallet.balance==300,"teaching purchase delivers real package without cost")
		check(Relationships.summary("harbor_merchant").points==0,"buying cannot purchase affection")
		await pointer_click(shop.topic_button)
		check(is_instance_valid(shop.merchant_dialogue) and shop.merchant_dialogue.topic=="merchant_seed","native shop offers clue seed")
		await pointer_click(shop.merchant_dialogue.next_button)
		check(not Relationships.state.flags.get("invoice_seen",false),"clue evidence not leaked by initial conversation")
		var save:=Relationships.state.duplicate(true)
		var path:=Relationships.save_path
		Relationships.save_path+="/unwritable"
		check(not Relationships.advance_topic("merchant_seed",1) and Relationships.state==save,"failed relationship write cannot advance cursor")
		Relationships.save_path=path
		print("DEPARTURE SEED: %d checks, %d failures" % [count,failures.size()])
		get_tree().quit(0 if failures.is_empty() else 1)
		return
	check(OpeningFlow.state.phase=="ending" and OpeningFlow.state.departure.node=="prepare","process restart resumes preparation")
	check(OpeningFlow.protagonist_name()=="归舟","protagonist signature survives process restart")
	check(SlotWallet.balance==300 and Supplies.total_remaining("sku_gin_london_dry")==750,"restart retains one purchase exactly")
	check(Relationships.state.cursors.get("merchant_seed")==1,"interrupted conversation resumes correct line")
	await show_scene("res://scenes/opening_departure.tscn")
	await settle()
	var shop: Control=page.preparation.page
	for sku in ["sku_tonic_water","sku_lime_wedge"]:
		shop.focus_item(sku)
		if sku=="sku_tonic_water": await pointer_click(shop.find_child("QuantityPlus",true,false))
		await pointer_click(shop.buy_button)
	await pointer_click(shop.topic_button)
	check(shop.merchant_dialogue.index==1,"returning to seed does not start it over")
	await topic_to_end()
	check(Relationships.state.flags.get("invoice_heard",false) and not Relationships.state.flags.get("invoice_seen",false),"heard clue and physical evidence are distinct")
	check(Prep.report("gin_and_tonic").ready,"all required ingredients now available")
	check(SlotWallet.balance==300,"no duplicate or hidden purchase")
	page.preparation.guide.refresh()
	await pointer_click(page.preparation.guide.proceed)
	await settle()
	for i in range(3): operation("ice",{"ice":"cube","vessel":"glass"})
	operation("withdraw",{"material":"gin","ml":50,"vessel":"glass"})
	operation("withdraw",{"material":"sku_tonic_water","ml":150,"vessel":"glass"})
	operation("garnish",{"material":"garnish"})
	page.preparation.page._finish()
	await settle()
	await pointer_click(button_named(page.preparation.page,"确认这杯，加入今晚酒单 →"))
	check(MenuCatalog.entries.size()==1 and MenuCatalog.entries[0].id=="gin_and_tonic","explicit menu publication")
	while OpeningFlow.state.departure.node!="my_door": await next_line()
	check(OpeningFlow.state.departure.opened,"sign opened once")
	await capture("departure-03-open")
	get_tree().current_scene=null
	await next_line()
	await settle_opening_transition()
	var home: Control=get_tree().current_scene
	page.queue_free()
	page=null
	await settle()
	TimeManager._process(5)
	await settle()
	check(TimeManager.is_open and StoryDialogue.guest_id=="milo","existing first guest preserved")
	var story_steps:=0
	while StoryDialogue.phase=="story" and story_steps<90:
		story_steps+=1
		if StoryDialogue.current_choices().is_empty(): StoryDialogue.continue_talking()
		else: StoryDialogue.choose(StoryDialogue.current_choices()[0].id,StoryDialogue.revision)
	check(story_steps<90,"first chapter terminates")
	print("FIRST CHAPTER: ",StoryDialogue.guest_id," / ",StoryDialogue.phase," / ",StoryDialogue.node_id)
	await settle()
	check(Relationships.summary("milo").points==int(Relationships.config.chapter_points),"real completed chapter produces one configured event")
	var guest:={"id":"milo","visit_id":home.reception_id,"visit":home.guest_count,"day":TimeManager.day}
	var order:=GuestService.make_order(guest,"gin_and_tonic")
	check(not order.is_empty(),"actual customer order created")
	operation("select_recipe",{"recipe_id":"gin_and_tonic","guest":guest,"order":order})
	operation("withdraw",{"material":"gin","ml":50,"vessel":"glass"})
	operation("withdraw",{"material":"sku_tonic_water","ml":150,"vessel":"glass"})
	operation("finish")
	var drink: String=WorkbenchSession.state.session.result.drink_id
	check(GuestService.deliver(drink),"real first delivery settles")
	await settle()
	var relation:=Relationships.state.duplicate(true)
	var gold:=SlotWallet.balance
	check(GuestService.deliver(drink) and Relationships.reconcile(),"retry delivery and reconciliation")
	check(Relationships.state==relation and SlotWallet.balance==gold,"same drink cannot grant relation or payment twice")
	check(Relationships.guide_pending(),"first real service offers relationship teaching")
	Navigation.go_to(&"journal")
	await settle()
	var journal: Control=home.active_page
	journal._select_guest("milo")
	await settle()
	await capture("departure-04-relationship")
	check(button_named(journal,"我明白了")!=null,"guide is actual actionable journal card")
	await pointer_click(button_named(journal,"我明白了"))
	check(not Relationships.guide_pending(),"acknowledgement persists")
	journal._select_guest("harbor_merchant")
	await settle()
	check(not Relationships.topic_available("old_invoice"),"first purchase and first drink do not reveal private evidence")
	await capture("departure-05-clue-seed")
	Navigation.go_to(&"shop")
	await settle()
	shop=home.active_page
	await pointer_click(shop.topic_button)
	var limit:=0
	while is_instance_valid(shop.merchant_dialogue) and limit<20:
		limit+=1
		await pointer_click(shop.merchant_dialogue.next_button)
	check(Relationships.topic_available("old_invoice"),"return conversation opens independently configured clue")
	await pointer_click(shop.topic_button)
	await pointer_click(shop.merchant_dialogue.next_button)
	check(not Relationships.state.flags.get("invoice_seen",false),"opening topic alone does not reveal unseen paper")
	await pointer_click(shop.merchant_dialogue.next_button)
	check(Relationships.state.flags.get("invoice_seen",false),"observed evidence recorded at actual paper line")
	await capture("departure-06-evidence")
	limit=0
	while is_instance_valid(shop.merchant_dialogue) and limit<20:
		limit+=1
		await pointer_click(shop.merchant_dialogue.next_button)
	var before:=Relationships.state.duplicate(true)
	check(Relationships.next_merchant_topic().is_empty(),"completed topic cannot be farmed")
	Relationships.reconcile()
	check(Relationships.state==before,"reconcile leaves observed history immutable")
	var baseline: Dictionary=Supplies.inventory.serialize()
	gold=SlotWallet.balance
	check(OpeningFlow.begin_replay() and OpeningFlow.begin_tutorial() and OpeningFlow.finish_tutorial(true),"replay isolates new opening")
	check(OpeningFlow.begin_departure(),"replay departure starts")
	check(not Relationships.observe_line("merchant_intro",0),"replay cannot modify official merchant relation")
	OpeningFlow.return_to_title()
	await settle_opening_transition()
	check(Relationships.state==before and SlotWallet.balance==gold and Supplies.inventory.serialize()==baseline,"replay preserves relationship wallet inventory")
	check(Relationships.load_state() and Relationships.state==before,"relationship record restores durable state")
	print("DEPARTURE RESUME: %d checks, %d failures" % [count,failures.size()])
	get_tree().quit(0 if failures.is_empty() else 1)

func operation(kind: String, payload: Dictionary={}) -> void:
	command_serial+=1
	check(WorkbenchSession.command("departure-test-%d" % command_serial,str(WorkbenchSession.state.session.get("id","")),kind,payload),kind+": "+WorkbenchSession.last_error)
