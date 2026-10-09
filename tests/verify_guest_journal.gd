extends "res://tests/verify_workbench_scene.gd"
const JournalData = preload("res://scripts/guest_journal_data.gd")
var serial := 0

func _ready() -> void:
	if "--journal-resume" in OS.get_cmdline_user_args():
		TimeManager.set_process(false)
		call_deferred("resume_check")
	else: super._ready()

func op(kind: String, payload: Dictionary={}) -> void:
	serial += 1
	check(WorkbenchSession.command("journal-test-%d" % serial,str(WorkbenchSession.state.session.get("id","")),kind,payload),kind+": "+WorkbenchSession.last_error)

func text_in(node: Node) -> String:
	var text := str(node.text)+"\n" if node is Label or node is Button else ""
	for child in node.get_children(): text += text_in(child)
	return text

func count_lines(groups: Array) -> int:
	var n := 0
	for group in groups: n += group.lines.size()
	return n

func run() -> void:
	WorkbenchSession.reset_game()
	home = load("res://scenes/home.tscn").instantiate()
	add_child(home)
	await settle()
	var entry: Button = home.find_child("ReviewsButton",true,false)
	check(entry.text == "手帐" and entry.get_meta("route") == "journal","journal replaces reviews without changing cocktail codex")
	click(entry)
	await settle()
	bench = home.active_page
	check(Navigation.current_route == &"journal","native navigation enters journal")
	check(not text_in(bench).contains("演过小游戏的演员") and not text_in(bench).contains("无气泡"),"unknown guests do not leak biography or preferences")
	await capture("journal-00-unknown")
	Navigation.go_to(&"home")
	StoryDialogue.start_guest("stick")
	StoryDialogue.choose(StoryDialogue.current_choices()[0].id,StoryDialogue.revision)
	check(StoryDialogue.is_known("stick"),"identity revealed through real dialogue")
	StoryDialogue.continue_talking()
	StoryDialogue.choose(StoryDialogue.current_choices()[0].id,StoryDialogue.revision)
	var groups := JournalData.conversations("stick",StoryDialogue.progress,StoryDialogue.catalog)
	check(count_lines(groups)>3,"unfinished conversation visible immediately")
	check(not JSON.stringify(groups).contains("最近活没那么多"),"unchosen branch is not revealed")
	while StoryDialogue.phase == "story":
		if not StoryDialogue.current_choices().is_empty(): StoryDialogue.choose(StoryDialogue.current_choices()[0].id,StoryDialogue.revision)
		else: StoryDialogue.continue_talking()
	for i in range(StoryDialogue.smalltalk.stick.size()): StoryDialogue.continue_talking()
	var first_count := count_lines(JournalData.conversations("stick",StoryDialogue.progress,StoryDialogue.catalog))
	for i in range(StoryDialogue.smalltalk.stick.size()*2): StoryDialogue.continue_talking()
	check(count_lines(JournalData.conversations("stick",StoryDialogue.progress,StoryDialogue.catalog))==first_count,"repeated idle dialogue is deduplicated")
	var legacy := StoryDialogue.progress.duplicate(true)
	legacy.stick.erase("archive")
	check(StoryDialogue._valid_save({"version":1,"guests":legacy}) and count_lines(JournalData.conversations("stick",legacy,StoryDialogue.catalog))>0,"old heard histories migrate without reading unseen nodes")
	MenuCatalog.unlocked_ids.assign(["last_word"])
	check(MenuCatalog.save_menu([{"id":"last_word","price":70}],MenuCatalog.design),"menu fixture")
	op("select_recipe",{"recipe_id":"last_word","guest":{"id":"stick","name":"小线","day":1,"visit":1}})
	op("withdraw",{"material":"gin","ml":22.5,"vessel":"glass"})
	op("withdraw",{"material":"lime","ml":22.5,"vessel":"glass"})
	op("withdraw",{"material":"syrup","ml":10,"vessel":"glass"})
	op("finish")
	var original_result: Dictionary = WorkbenchSession.state.session.result.duplicate(true)
	var drink_id: String = original_result.drink_id
	Navigation.go_to(&"journal")
	await settle()
	bench = home.active_page
	bench._select_guest("stick")
	check(JournalData.drinks("stick",WorkbenchSession.state).size()==1,"current completed cup included once before archival")
	check(text_in(bench).contains("未结算") and not text_in(bench).contains("实付 0"),"unsettled cups never fabricate payment or customer score")
	check(text_in(bench).contains(str(original_result.evaluation.title)),"display uses saved actual evaluation")
	await capture("journal-01-overview")
	click(bench.tab_buttons[1])
	await settle()
	check(bench.tab==1 and text_in(bench).contains("这里招演员吗"),"native tabs show archived story")
	await capture("journal-02-dialogues")
	var gold: int = SlotWallet.balance
	var inventory: Dictionary = Supplies.inventory.serialize().duplicate(true)
	var receipt := {"id":"test-payment-1","delivered":true,"paid":true,"satisfaction":"很满意","score":92,"base_paid":70,"tip":10,"total_paid":80}
	check(WorkbenchSession.record_guest_settlement(drink_id,receipt),"future settlement adapter stores complete receipt")
	check(WorkbenchSession.record_guest_settlement(drink_id,receipt),"duplicate receipt is idempotent")
	var conflicting := receipt.duplicate(true)
	conflicting.score=65
	check(not WorkbenchSession.record_guest_settlement(drink_id,conflicting),"completed receipt cannot be silently changed")
	var invalid := receipt.duplicate(true)
	invalid.total_paid=81
	check(not WorkbenchSession.record_guest_settlement(drink_id,invalid),"inconsistent payout rejected")
	check(SlotWallet.balance==gold and Supplies.inventory.serialize()==inventory,"journal receipt adapter never credits coins or consumes stock")
	click(bench.tab_buttons[2])
	await settle()
	check(text_in(bench).contains("实付 80 金币") and text_in(bench).contains("92"),"actual receipt fields displayed separately from quality")
	await capture("journal-03-receipt")
	op("start")
	check(JournalData.drinks("stick",WorkbenchSession.state).size()==1,"archiving current cup does not duplicate it")
	op("withdraw",{"material":"gin","ml":10,"vessel":"glass"})
	op("finish")
	var second_id: String=WorkbenchSession.state.session.result.drink_id
	check(not WorkbenchSession.record_guest_settlement(second_id,receipt),"one payment cannot be attached to two cups")
	var second_receipt := receipt.duplicate(true)
	second_receipt.id="test-payment-2"
	var before: Dictionary=WorkbenchSession.snapshot()
	var path: String=Supplies.save_path
	Supplies.save_path=path+"/bad.json"
	check(not WorkbenchSession.record_guest_settlement(second_id,second_receipt) and WorkbenchSession.snapshot()==before,"failed receipt save rolls back")
	Supplies.save_path=path
	WorkbenchSession.last_error=""
	for i in range(7):
		op("start")
		op("withdraw",{"material":"gin","ml":10,"vessel":"glass"})
		op("finish")
	check(JournalData.drinks("stick",WorkbenchSession.state).size()==9,"same cocktail on nine cups keeps nine records")
	bench._select_tab(2)
	check(text_in(bench).contains("下一页"),"long history has accessible pagination")
	bench._change_page(1)
	check(text_in(bench).contains("实付 80 金币"),"oldest receipt remains accessible on later page")
	var fake := WorkbenchSession.snapshot()
	fake.history.append(fake.session.duplicate(true))
	check(JournalData.drinks("stick",fake).size()==9,"duplicate drink IDs do not duplicate display")
	fake.session.mode="research_diy"
	fake.history=[]
	check(JournalData.drinks("stick",fake).is_empty(),"research is excluded from guest consumption")
	check(JournalData.drinks("ada",WorkbenchSession.state).is_empty(),"guest records remain isolated")
	bench._select_tab(3)
	check(text_in(bench).contains("内测演示") and not StoryDialogue.progress.stick.get("activity_unlocks",{}).has("stick_minigame"),"demo access does not grant permanent story unlock")
	check(StoryDialogue.unlock_activity("stick","stick_minigame","test-story-event"),"authored unlock hook persists")
	check(StoryDialogue.unlock_activity("stick","stick_minigame","test-story-event"),"unlock retries are idempotent")
	check(text_in(bench).contains("开始游戏"),"badminton demo has a real launch entry")
	var route: StringName = &"stick_demo"
	var scene: PackedScene = Navigation.registered_pages[route]
	Navigation.registered_pages.erase(route)
	bench._launch_activity("stick_minigame")
	check(Navigation.current_route==&"journal","missing scene is never launched")
	Navigation.registered_pages[route]=scene
	await capture("journal-04-activities")
	var story_snapshot := StoryDialogue.session_snapshot()
	var story_progress := StoryDialogue.progress.duplicate(true)
	click(home.find_child("CodexButton",true,false))
	await settle()
	check(Navigation.current_route==&"codex","cocktail codex remains a separate working route")
	click(entry)
	await settle()
	bench=home.active_page
	check(StoryDialogue.session_snapshot()==story_snapshot and StoryDialogue.progress==story_progress,"navigation never advances dialogue or grants knowledge")
	get_window().size=Vector2i(1024,768)
	await settle()
	await capture("journal-05-small")
	check(bench.content_scroll.get_global_rect().end.x<=1601,"book content remains inside design bounds")
	check(GameSession.save_game(),"shared story save persists journal archive")
	check(WorkbenchSession.load_state(),"reload cups with receipt")
	check(JournalData.drinks("stick",WorkbenchSession.state).size()==9,"reload preserves all records")
	print("GUEST JOURNAL: %d checks, %d failures" % [count,failures.size()])
	home.queue_free()
	await settle()
	get_tree().quit(0 if failures.is_empty() else 1)

func resume_check() -> void:
	check(GameSession.save_path.begins_with("/tmp/"),"private resume save")
	check(JournalData.drinks("stick",WorkbenchSession.state).size()==9,"new process recovers nine cups")
	var drinks := JournalData.drinks("stick",WorkbenchSession.state)
	if not drinks.is_empty(): check(drinks.back().result.customer_receipt.total_paid==80,"new process recovers original immutable settlement")
	check(StoryDialogue.progress.get("stick",{}).get("activity_unlocks",{}).has("stick_minigame"),"new process recovers unlock")
	check(count_lines(JournalData.conversations("stick",StoryDialogue.progress,StoryDialogue.catalog))>10,"new process recovers dialogue archive")
	print("GUEST JOURNAL RESTORE: %d checks, %d failures" % [count,failures.size()])
	get_tree().quit(0 if failures.is_empty() else 1)
