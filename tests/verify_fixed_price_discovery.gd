extends "res://tests/verify_workbench_scene.gd"
const Pricing=preload("res://scripts/drink_pricing.gd")
const JournalData=preload("res://scripts/guest_journal_data.gd")

func run() -> void:
	CustomerService.endpoint=""
	TimeManager.set_process(false)
	TimeManager.advance_minutes(posmod(1200-TimeManager.minutes_since_midnight,1440))
	for recipe in MenuCatalog.all_recipes():
		check(recipe.reference_price==Pricing.quote(recipe).price,"canonical fixed price "+str(recipe.id))
	MenuCatalog.unlock_recipe("gin_and_tonic")
	var fixed: int=Pricing.quote(MenuCatalog.get_recipe("gin_and_tonic")).price
	check(MenuCatalog.save_menu([{"id":"gin_and_tonic","price":9999}],MenuCatalog.DEFAULT_DESIGN),"menu saved")
	check(MenuCatalog.entries[0].price==fixed,"manual price cannot override fixed price")
	var old: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(MenuCatalog.save_path))
	old.entries[0].price=777
	var file:=FileAccess.open(MenuCatalog.save_path,FileAccess.WRITE);file.store_string(JSON.stringify(old));file.close()
	check(MenuCatalog.load_state() and MenuCatalog.entries[0].price==fixed,"legacy menu price migrated on load")
	check(MenuCatalog.menu_for_ai().selected_drinks[0].price==fixed,"poster/AI uses fixed price")
	check(MenuCatalog.save_state(),"migrated menu can be saved")
	var source_profiles: Array=JournalData.profiles().filter(func(profile): return StoryDialogue.catalog.has(profile.id))
	var index:=0
	for profile in source_profiles:
		for chapter in StoryDialogue.catalog[profile.id]:
			index+=1
			StoryDialogue.progress[profile.id]={"completed":int(chapter.episode)-1}
			check(CustomerService.begin_guest(profile,index,false),"real visit begins "+chapter.id)
			var expected: Dictionary=CustomerService.profiles[profile.id].base_preferences.duplicate(true)
			var matched: Dictionary={}
			for event in CustomerService.events:
				if event.story_episode_id==chapter.id: matched=event
			check(not matched.is_empty(),"event exists "+chapter.id)
			for attr in expected:
				expected[attr]=clampf(float(expected[attr])+float(CustomerService.profiles[profile.id].get("permanent_delta",{}).get(attr,0))+float(matched.preference_delta.get(attr,0)),0,100)
			check(CustomerService.state.active.demand.target==expected,"runtime temporary target "+chapter.id)
			var clue_id: String=matched.demand_line_ref.node_id
			check(chapter.nodes.has(clue_id) and "[b]" in chapter.nodes[clue_id].text,"readable highlighted taste clue "+chapter.id)
			var quote:=CustomerService.prepare_order("gin_and_tonic")
			check(quote.get("price")==fixed and CustomerService.state.active.order.demand.target==expected,"order freezes price and event target "+chapter.id)
			check(CustomerService.begin_guest(profile,index,true) and CustomerService.state.active.demand.target==expected,"restoring visit never stacks deltas "+chapter.id)
			if chapter.id=="stick_02": check(expected.alcohol_intensity==55 and expected.sweetness==15,"stick stronger drink 35 to55 less sweet25 to15")
	StoryDialogue.progress={}
	CustomerService.state.deliveries={}; CustomerService.state.active={}; CustomerService.state.erase("memory_dialogue")
	for profile in source_profiles:
		for item in JournalData.activities(profile.id,StoryDialogue.progress):
			check(not item.accessible and not item.demo,"no unearned demo access "+profile.id)
			Navigation.current_route=&"home";Navigation.go_to(StringName(item.route))
			check(Navigation.current_route==&"home","locked route cannot be navigated "+profile.id)
	var journal=load("res://scenes/guest_journal.tscn").instantiate();add_child(journal);await settle()
	check(journal.tab_buttons[3].text=="？" and journal.tab_buttons[3].disabled,"locked journal tab is a disabled question mark")
	journal._select_tab(3);check(journal.tab!=3,"programmatic locked tab also blocked")
	StoryDialogue.unlock_activity("milo","milo_ferry","test-invitation")
	journal._select_guest("milo");await settle()
	check(not journal.tab_buttons[3].disabled and journal.tab_buttons[3].text=="专属小游戏","earned journal tab revealed")
	journal.queue_free();await settle()
	var settings=load("res://scenes/settings_menu.tscn").instantiate();add_child(settings);await settle()
	check(not settings.has_method("_launch_memory"),"settings has no practice shortcut")
	settings.queue_free();await settle()
	op("begin_research",{"mode":"research_diy"});op("cup",{"cup":"rocks"});op("withdraw",{"material":"gin","ml":30,"vessel":"glass"});op("finish")
	op("save_research",{"name":"固定价测试","english_name":"Fixed price","notes":""})
	var diy:=MenuCatalog.get_recipe("diy_1")
	check(diy.reference_price==Pricing.quote(diy).price,"DIY priced from actual saved amounts")
	check(MenuCatalog.save_menu([{"id":"diy_1","price":9999}],MenuCatalog.DEFAULT_DESIGN) and MenuCatalog.entries[0].price==diy.reference_price,"DIY manual override rejected by normalization")
	var menu=load("res://scenes/drink_menu.tscn").instantiate();add_child(menu);await settle()
	menu._go_selection();await settle()
	menu._refresh_receipt()
	var spin_count:=0
	for child in menu.receipt.get_children():
		if child is SpinBox: spin_count+=1
	check(spin_count==0,"menu has no editable price control")
	menu.queue_free();await settle()
	print("FIXED PRICE AND DISCOVERY: %d checks, %d failures" % [count,failures.size()]);get_tree().quit(0 if failures.is_empty() else 1)

var serial := 0
func op(kind: String,payload: Dictionary={}) -> bool:
	serial+=1
	var success: bool=WorkbenchSession.command("pricing-test-%d" % serial,str(WorkbenchSession.state.session.get("id","")),kind,payload)
	check(success,kind+": "+WorkbenchSession.last_error)
	return success
