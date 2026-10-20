extends "res://tests/verify_workbench_scene.gd"
const Journal=preload("res://scripts/guest_journal_data.gd")
var serial:=0
func _ready() -> void:
	if not Supplies.save_path.begins_with("/tmp/"): get_tree().quit(2); return
	get_tree().current_scene=null # Runner survives PlayModes scene replacement.
	if "--integration-resume" in OS.get_cmdline_user_args(): call_deferred("restored"); return
	super._ready()
func op(kind: String,payload: Dictionary={}) -> bool:
	serial+=1
	var ok:=WorkbenchSession.command("merge-%d" % serial,str(WorkbenchSession.state.session.get("id","")),kind,payload)
	check(ok,kind+": "+WorkbenchSession.last_error); return ok
func talk() -> void:
	for i in range(90):
		if StoryDialogue.phase!="story": break
		if StoryDialogue.current_choices().is_empty(): StoryDialogue.continue_talking()
		else: StoryDialogue.choose(StoryDialogue.current_choices()[0].id,StoryDialogue.revision)
	check(StoryDialogue.phase!="story","chapter and authored taste clue finish")
func finish_gin() -> void:
	op("ice",{"ice":"cube","vessel":"glass"})
	op("ice",{"ice":"cube","vessel":"glass"})
	op("ice",{"ice":"cube","vessel":"glass"})
	op("withdraw",{"material":"gin","ml":50,"vessel":"glass"})
	op("withdraw",{"material":"sku_tonic_water","ml":150,"vessel":"glass"})
	op("garnish",{"material":"garnish","vessel":"glass"})
	op("spoon",{"target":"glass"})
	for i in range(8): op("stir",{"vessel":"glass","seconds":.5,"control":1.0})
	op("finish")
func feedback() -> void:
	for i in range(5):
		await settle()
		var record:=CustomerService.current_record()
		if record.is_empty() or record.feedback.done: break
		CustomerService.choose_feedback(0,int(record.feedback.round))
	check(CustomerService.current_record().feedback.done,"offline feedback completes without external service")
func run() -> void:
	CustomerService.endpoint=""
	for sku in ["sku_gin_london_dry","sku_tonic_water","sku_lime_wedge"]: check(Supplies.inventory.purchase(sku,10),"stock "+sku)
	check(Supplies._write(Supplies.inventory.serialize(),{}),"save private stock")
	MenuCatalog.unlock_recipe("gin_and_tonic")
	check(MenuCatalog.save_menu([{"id":"gin_and_tonic","price":80}],MenuCatalog.design),"publish gin menu")
	home=load("res://scenes/home.tscn").instantiate(); get_tree().root.add_child(home); get_tree().current_scene=home; await settle()
	TimeManager.set_process(false); TimeManager.advance_minutes(posmod(1200-TimeManager.minutes_since_midnight,1440)); await settle()
	check(home.find_child("ReviewsButton",true,false).text=="手帐","menu replaces reviews with journal")
	check(is_instance_valid(home.mode_button),"free mixing mode remains in menu")
	home.get_node("%GuestLayer").show_guest(0); await settle(); talk(); await settle()
	home._on_open_pressed(); await settle(); bench=home.active_page
	check(Navigation.current_route==&"drink_selection","chat leads to drink menu")
	bench._select("gin_and_tonic"); bench._start(); await settle(); bench=home.active_page
	check(Navigation.current_route==&"mixing" and not WorkbenchSession.state.session.has("order"),"new UI uses single canonical customer order")
	finish_gin(); await settle()
	var result: Dictionary=WorkbenchSession.state.session.result.duplicate(true)
	var balance:=SlotWallet.balance
	var wallet_path: String=SlotWallet.save_path
	SlotWallet.save_path=wallet_path+"/blocked"
	check(not CustomerService.deliver(result) and SlotWallet.balance==balance,"new payment failure keeps money unchanged and retryable")
	SlotWallet.save_path=wallet_path
	var service_path: String=CustomerService.save_path
	CustomerService.save_path=service_path+"/blocked"
	check(not CustomerService.deliver(result),"new receipt write failure remains recoverable after wallet credit")
	var paid_once:=SlotWallet.balance
	CustomerService.save_path=service_path
	bench._send_finished_drink(); await settle()
	check(SlotWallet.balance==paid_once,"receipt retry does not credit twice")
	var record:=CustomerService.current_record()
	check(record.status=="settled" and SlotWallet.balance==balance+record.amount,"UI delivers and credits once")
	check(record.amount==record.base_paid+record.tip,"tips included in one receipt")
	check(CustomerService.deliver(result) and GuestService.deliver(result.drink_id) and SlotWallet.balance==balance+record.amount,"both API entries are idempotent on new cup")
	check(GuestActivities.satisfied_count("milo")==1,"canonical satisfied visit counts towards activity invitation")
	var drinks:=Journal.drinks("milo",WorkbenchSession.state)
	check(drinks.size()==1 and drinks[0].result.customer_receipt.total_paid==record.amount,"journal projects canonical payment and actual drink")
	bench._return_after_serving(); await settle(); await feedback()
	check(not Journal.conversations("milo",StoryDialogue.progress,StoryDialogue.catalog,WorkbenchSession.state).is_empty(),"dialogue archive includes canonical feedback")
	Navigation.go_to(&"journal"); await settle(); bench=home.active_page; bench._select_guest("milo"); bench._select_tab(2); await capture("merge-journal-new-receipt")
	Navigation.go_to(&"reviews"); await settle(); check(Navigation.current_route==&"journal","legacy reviews links open journal")
	Navigation.go_to(&"home"); await settle()
	var first_record: String=record.id
	var story_progress:=StoryDialogue.progress.duplicate(true)
	var before_switch:=SlotWallet.balance
	check(PlayModes.switch_to("mixing"),"switch to free mixing")
	await settle(); home=get_tree().current_scene; TimeManager.set_process(false)
	check(PlayModes.mode=="mixing" and SlotWallet.balance==before_switch and CustomerService.state.deliveries.has(first_record),"switch preserves wallet and journal records")
	check(StoryDialogue.progress==story_progress,"free mode does not advance story")
	if not TimeManager.is_open: TimeManager.advance_minutes(posmod(1200-TimeManager.minutes_since_midnight,1440)); await settle()
	home.get_node("%GuestLayer").show_guest(0); await settle()
	check(not CustomerService.state.active.free_order.is_empty(),"free mode creates frozen menu request")
	home._on_open_pressed(); await settle(); bench=home.active_page; bench._select("gin_and_tonic"); bench._start(); await settle(); bench=home.active_page
	finish_gin(); await settle(); bench._send_finished_drink(); await settle()
	record=CustomerService.current_record()
	check(record.get("play_mode")=="mixing" and record.status=="settled" and record.free_settlement.matched,"free mode brewing and settlement connected")
	check(Journal.drinks("milo",WorkbenchSession.state).size()==2,"free mode drink appears in same journal")
	check(GuestActivities.satisfied_count("milo")==1,"practice orders do not forge story invitations")
	check(StoryDialogue.progress==story_progress,"free orders do not change chapter progress")
	var free_id: String=record.id
	check(PlayModes.switch_to("story"),"return to story mode")
	await settle(); home=get_tree().current_scene; TimeManager.set_process(false)
	check(CustomerService.state.active.delivery_id==first_record,"story reception restores separately")
	check(CustomerService.state.deliveries.has(free_id) and Journal.drinks("milo",WorkbenchSession.state).size()==2,"both modes retain shared history")
	# A real new-model hard restriction is recorded without charging or granting tips.
	home.get_node("%GuestLayer").show_guest(4); await settle()
	# Yellow's current authored preferences allow alcohol. Explicitly lock a hard
	# restriction in this isolated fixture to continue testing the refusal pathway.
	CustomerService.state.active.demand.constraints=[{"kind":"forbid_items","items":["sku_gin_london_dry"],"label":"本次测试不接受金酒"}]
	CustomerService._write()
	talk(); await settle()
	home._on_open_pressed(); await settle(); bench=home.active_page; bench._select("gin_and_tonic"); bench._start(); await settle(); bench=home.active_page
	finish_gin(); await settle()
	var refused_balance:=SlotWallet.balance
	bench._send_finished_drink(); await settle()
	var refused:=CustomerService.current_record()
	check(refused.guest_id=="yellow_creature" and refused.review.status=="rejected" and refused.amount==0 and refused.tip==0,"hard restriction produces a zero-value receipt")
	check(SlotWallet.balance==refused_balance and CustomerService.deliver(WorkbenchSession.state.session.result),"refusal and retry do not take money")
	check(Journal.drinks("yellow_creature",WorkbenchSession.state)[0].result.customer_receipt.total_paid==0,"journal agrees with refused receipt")
	await feedback()
	# The formal badminton scene is reachable from the journal, and its exit returns there.
	Navigation.journal_focus_guest="stick"; Navigation.go_to(&"journal"); await settle(); bench=home.active_page
	bench._launch_activity("stick_minigame"); await settle()
	check(Navigation.current_route==&"journal","unearned badminton remains locked")
	StoryDialogue.unlock_activity("stick","stick_minigame","test-earned-invitation")
	bench._launch_activity("stick_minigame"); await settle(); bench=home.active_page
	check(Navigation.current_route==&"stick_badminton" and bench.match_context.mode=="practice","journal launches formal badminton in practice mode")
	bench.close_requested.emit(); await settle(); check(Navigation.current_route==&"journal","badminton returns to journal")
	check(preload("res://scripts/research_data.gd").config().legendary_recipes.size()==4,"all four reward recipes retained")
	# No reset or migration erases either store.
	check(GameSession.save_game() and CustomerService._write() and WorkbenchSession._valid(WorkbenchSession.state),"combined save valid")
	var f:=FileAccess.open(Supplies.save_path+".integration",FileAccess.WRITE);f.store_string(JSON.stringify({"balance":SlotWallet.balance,"first":first_record,"free":free_id}));f.close()
	print("BRANCH INTEGRATION: %d checks, %d failures" % [count,failures.size()]); get_tree().quit(0 if failures.is_empty() else 1)
func restored() -> void:
	await settle()
	var expected: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(Supplies.save_path+".integration"))
	check(WorkbenchSession.writable and CustomerService.writable and GameSession.writable and PlayModes.writable,"all stores reopen")
	check(SlotWallet.balance==expected.balance,"relaunch no repeated payment")
	check(CustomerService.state.deliveries.has(expected.first) and CustomerService.state.deliveries.has(expected.free),"both mode receipts survive")
	check(PlayModes.mode=="story" and PlayModes.contexts.has("mixing"),"mode context survives")
	check(Journal.drinks("milo",WorkbenchSession.state).size()==2,"journal survives new process")
	print("BRANCH INTEGRATION RESTORE: %d checks, %d failures" % [count,failures.size()]);get_tree().quit(0 if failures.is_empty() else 1)
