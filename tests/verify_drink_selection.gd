extends "res://tests/verify_workbench_scene.gd"

func _ready() -> void:
	if DisplayServer.get_name()!="headless": DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_NO_FOCUS,true)
	super._ready()

func key(code: int) -> void:
	var event:=InputEventKey.new()
	event.keycode=code
	event.physical_keycode=code
	event.pressed=true
	get_viewport().push_input(event,true)

func run() -> void:
	for service in [SlotWallet,StoryDialogue,GameSession,MenuCatalog,Supplies]:
		if not service.save_path.begins_with("/tmp/"):
			get_tree().quit(2)
			return
	WorkbenchSession.reset_game()
	MenuCatalog.unlocked_ids.assign(["last_word","mojito","gin_and_tonic"])
	check(MenuCatalog.save_menu([],MenuCatalog.design),"save empty menu")
	home=load("res://scenes/home.tscn").instantiate()
	add_child(home)
	TimeManager.advance_minutes(1200-TimeManager.minutes_since_midnight)
	await settle()
	check(home.service_started,"service opened")
	home._on_talk_pressed()
	var guest_id: String=StoryDialogue.guest_id
	var speech: String=StoryDialogue.speech
	click(home.get_node("%OpenButton"))
	await settle()
	check(Navigation.current_route==&"drink_selection","home opens selector before bench")
	var page: Control=home.active_page
	check(page.buttons.is_empty() and page.start_button.disabled,"empty menu cannot start or auto-list")
	check(WorkbenchSession.snapshot().session.is_empty(),"viewing selector does not create cup")
	page._manage_menu()
	await settle()
	check(page.has_meta("editor"),"existing menu editor opens in selector")
	check(MenuCatalog.save_menu([{"id":"last_word","price":60},{"id":"mojito","price":45},{"id":"gin_and_tonic","price":35}],MenuCatalog.design),"save published menu")
	key(KEY_ESCAPE)
	await settle()
	check(not page.has_meta("editor") and Navigation.current_route==&"drink_selection","editor Escape returns to selector")
	check(page.buttons.size()==3 and not page.buttons.has("manhattan"),"only listed drinks appear")
	var stock: Dictionary=Supplies.inventory.serialize().duplicate(true)
	var gold: int=SlotWallet.balance
	click(page.buttons.mojito)
	await settle()
	check(page.title.text=="莫吉托","left selection updates right detail")
	await capture("06-drink-selection")
	click(page.back_button)
	await settle()
	check(Navigation.current_route==&"home" and StoryDialogue.guest_id==guest_id and StoryDialogue.speech==speech,"cancel keeps reception and conversation")
	click(home.get_node("%OpenButton"))
	await settle()
	page=home.active_page
	click(page.buttons.last_word)
	key(KEY_SPACE)
	await settle()
	check(Navigation.current_route==&"mixing","space starts selected drink")
	bench=home.active_page
	check(bench.recipe_title.text=="遗言" and bench.note.text.contains("22.5"),"bench note displays selected recipe and fractional amount")
	var state: Dictionary=WorkbenchSession.snapshot()
	check(state.session.recipe.id=="last_word" and state.session.recipe.ingredients.gin==22.5,"snapshot maps warehouse aliases without rounding")
	check(state.session.guest.id==guest_id and StoryDialogue.speech==speech,"recipe carries current guest without advancing dialogue")
	check(Supplies.inventory.serialize()==stock and SlotWallet.balance==gold,"selection consumes no inventory or money")
	var frozen: Dictionary=state.session.recipe.duplicate(true)
	var original: Dictionary=MenuCatalog._by_id.last_word.duplicate(true)
	MenuCatalog._by_id.last_word.name="changed catalog"
	check(WorkbenchSession.snapshot().session.recipe==frozen,"catalog change does not affect active recipe")
	MenuCatalog._by_id.last_word=original
	bench._begin_measure("gin",WorkbenchSession.dose_target("gin",state.session),"jigger")
	bench.measure.set_process(false)
	bench.measure.progress=bench.measure.target/bench.measure.volume_limit()
	key(KEY_SPACE)
	await settle()
	check(WorkbenchSession.state.session.vessels.jigger.contents.gin==22.5 and WorkbenchSession.remaining("gin")==577.5,"golden target charges exact 22.5 ml")
	check(WorkbenchSession.command("fraction-transfer",state.session.id,"transfer",{"source":"jigger","vessel":"glass"}),"fractional transfer succeeds")
	check(WorkbenchSession.state.session.vessels.glass.contents.gin==22.5 and WorkbenchSession.remaining("gin")==577.5,"transfer preserves fractional volume without second debit")
	await capture("07-selected-recipe-workbench")
	Supplies.load_state()
	check(WorkbenchSession.load_state(),"selected recipe validates from disk")
	check(WorkbenchSession.state.session.recipe==frozen,"selected recipe and decimal cup reload")
	check(WorkbenchSession.state.session.vessels.glass.contents.gin==22.5 and WorkbenchSession.remaining("gin")==577.5,"disk reload retains exact fractional cup and warehouse")
	Navigation.go_to(&"home")
	await settle()
	click(home.get_node("%OpenButton"))
	await settle()
	page=home.active_page
	click(page.buttons.mojito)
	check(page.resume_button.visible and not page.start_button.disabled and page.start_button.text.contains("收拾"),"half-made cup offers both resume and explicit clean-and-start")
	check(not WorkbenchSession.command("unsafe-replace","","select_recipe",{"recipe_id":"mojito"}),"service prevents replacing half-made cup")
	click(page.resume_button)
	await settle()
	check(Navigation.current_route==&"mixing" and WorkbenchSession.state.session.id==state.session.id,"resume keeps original cup ID")
	WorkbenchSession.set_table_materials(["gin","lime"])
	Navigation.go_to(&"home")
	await settle()
	click(home.get_node("%OpenButton"))
	await settle()
	page=home.active_page
	click(page.buttons.mojito)
	var pending: Dictionary=WorkbenchSession.snapshot()
	check(not WorkbenchSession.command("stale-replace","","select_recipe",{"recipe_id":"mojito","replace_session_id":"wrong-cup"}) and WorkbenchSession.state==pending,"stale replacement never discards another cup")
	check(not WorkbenchSession.command("invalid-replace","","select_recipe",{"recipe_id":"manhattan","replace_session_id":pending.session.id}) and WorkbenchSession.state==pending,"unlisted replacement preserves old cup")
	var save_path: String=Supplies.save_path
	Supplies.save_path=save_path+"/unwritable.json"
	click(page.start_button)
	await settle()
	check(WorkbenchSession.state==pending and Navigation.current_route==&"drink_selection","failed clean-and-start rolls back history cup and table together")
	Supplies.save_path=save_path
	page._select("mojito")
	await capture("51-selection-replace")
	DisplayServer.window_set_size(Vector2i(960,540))
	await settle()
	await capture("53-selection-small")
	click(page.start_button)
	key(KEY_SPACE)
	await settle()
	bench=home.active_page
	check(WorkbenchSession.state.session.id!=pending.session.id and WorkbenchSession.state.session.actions.is_empty(),"selector directly starts one fresh cup without visiting previous workbench")
	check(WorkbenchSession.state.table_materials.is_empty() and not WorkbenchSession.state.session.lid,"new choice clears bottles and resets tools")
	var discarded: Dictionary=WorkbenchSession.state.history.back()
	check(discarded.id==pending.session.id and discarded.status=="discarded" and discarded.result.waste.gin==22.5,"old cup archived as discarded with consumed material record")
	check(WorkbenchSession.remaining("gin")==577.5 and SlotWallet.balance==gold,"cleaning neither refunds ingredients nor charges extra")
	check(bench.recipe_title.text=="莫吉托" and bench.note.text.contains("薄荷叶") and bench.note.text.contains("轻压"),"new recipe updates liquid solid ice and step note")
	await capture("08-mojito-workbench")
	check(WorkbenchSession.command("idempotent-select","","select_recipe",{"recipe_id":"gin_and_tonic"}),"empty cup can change recipe")
	var serial: float=WorkbenchSession.state.serial
	check(WorkbenchSession.command("idempotent-select","","select_recipe",{"recipe_id":"gin_and_tonic"}) and WorkbenchSession.state.serial==serial,"repeated selection does not create extra cups")
	check(not WorkbenchSession.command("unlisted-select","","select_recipe",{"recipe_id":"manhattan"}),"unlisted recipe rejected by service")
	check(WorkbenchSession.dose_target("sku_tonic_water",WorkbenchSession.state.session)==60,"large recipe quantity splits into supported pours")
	check(WorkbenchSession.load_state(),"all selected recipe history validates after reload")
	var active_id: String=WorkbenchSession.state.session.id
	check(WorkbenchSession.command("replacement-fixture",active_id,"withdraw",{"material":"gin","ml":10}),"replacement fixture uses real inventory")
	var replacement: Dictionary={"recipe_id":"mojito","replace_session_id":active_id}
	check(WorkbenchSession.command("safe-replacement","","select_recipe",replacement),"explicit atomic replacement accepted")
	var replaced: Dictionary=WorkbenchSession.snapshot()
	check(WorkbenchSession.command("safe-replacement","","select_recipe",replacement) and WorkbenchSession.state==replaced,"retry of replacement does not archive twice or clear new cup")
	Navigation.go_to(&"drink_selection")
	await settle()
	TimeManager.advance_minutes(480)
	await settle()
	check(Navigation.current_route==&"drink_selection" and home.closing_pending and home.service_started,"closing retains final guest selector until send-off")
	print("DRINK SELECTION: %d checks, %d failures" % [count,failures.size()])
	home.queue_free()
	await settle()
	get_tree().quit(0 if failures.is_empty() else 1)
