extends Node
const ITEM := "tool_yellow_bar_spoon"
const Inventory = preload("res://scripts/supply_inventory.gd")
var checks := 0
var failures: Array = []
func check(ok: bool, message: String) -> void:
	checks+=1
	if not ok: failures.append(message); push_error(message)
func frames() -> void:
	for i in range(6): await get_tree().process_frame
func issue(id: String, kind: String, payload: Dictionary={}) -> bool:
	return WorkbenchSession.command(id,str(WorkbenchSession.state.session.get("id","")),kind,payload)
func _ready() -> void:
	if not Supplies.save_path.begins_with("/tmp/"): get_tree().quit(2); return
	TimeManager.set_process(false)
	await frames()
	if "--spoon-resume" in OS.get_cmdline_user_args():
		check(Supplies.is_owned(ITEM),"reward survives actual process restart")
		check(WorkbenchSession.state.session.get("spoon_tool_id")==ITEM,"equipped spoon survives process restart")
		check(WorkbenchSession.state.session.get("spoon_vessel")=="glass","attached spoon survives process restart")
		finish(); return
	check(Supplies.reset_game() and WorkbenchSession.reset_game(),"isolated reset")
	var inv=Inventory.new()
	check(not inv.is_unlocked(ITEM) and inv.total_remaining(ITEM)==0,"legendary not given by default")
	check(inv.total_remaining("tool_bar_spoon")==1,"ordinary spoon still free")
	var old: Dictionary=inv.serialize(); old.items.erase(ITEM)
	check(inv.restore(old) and not inv.is_unlocked(ITEM),"older save keeps new reward locked")
	check(not Supplies.quote_purchase(ITEM).ok,"reward cannot be bought")
	check(issue("start","start"),"workbench can start")
	check(not issue("locked","spoon",{"target":"glass","tool_id":ITEM}),"locked spoon cannot be equipped")
	var ski=load("res://scenes/yellow_ski.tscn").instantiate()
	add_child(ski); await frames()
	ski.model.state="lost"
	check(not ski._claim_spoon() and not Supplies.is_owned(ITEM),"losing awards nothing")
	ski.model.state="won"; ski.model.x=ski.model.LENGTH
	check(not ski._claim_spoon() and not Supplies.is_owned(ITEM),"uninvited game awards nothing")
	var next: Dictionary=WorkbenchSession.snapshot()
	next.activities=preload("res://scripts/guest_activity_rules.gd").fresh_book()
	next.activities.unlocks.yellow_ski={"source":"isolated-test"}
	check(WorkbenchSession._commit(next),"invited fixture saved")
	var original_save: String=Supplies.save_path
	Supplies.save_path="/tmp/nonexistent-spoon-folder/no-save.json"
	check(not ski._claim_spoon() and not Supplies.is_owned(ITEM),"write failure does not grant transient item")
	Supplies.save_path=original_save
	var balance: int=SlotWallet.balance
	check(ski._claim_spoon() and Supplies.is_owned(ITEM),"formal win grants spoon")
	var stock: Dictionary=Supplies.inventory.serialize()
	check(ski._claim_spoon() and Supplies.inventory.serialize()==stock,"repeat victory cannot duplicate item")
	check(SlotWallet.balance==balance,"reward does not change coins")
	ski._finish(); await frames()
	check(ski.overlay!=null,"win panel includes reward")
	if "--spoon-capture" in OS.get_cmdline_user_args():
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("/tmp/legendary-spoon-reward.png")
	ski.queue_free(); await frames()
	check(Supplies.load_state() and Supplies.is_owned(ITEM),"stock reload preserves reward")
	check(WorkbenchSession.load_state(),"workbench reload after reward")
	var locked: Dictionary=Supplies.inventory.serialize(); locked.items[ITEM]={"unlocked":false,"owned":false}
	Supplies.inventory.restore(locked); Supplies.save_state()
	var legacy:=ConfigFile.new(); legacy.set_value("best","distance",2000)
	var record_path: String=GameSession.save_path.get_base_dir().path_join("yellow_ski.cfg")
	legacy.save(record_path)
	check(GuestActivities.migrate_legacy_ski_spoon() and Supplies.is_owned(ITEM),"prior formal clear receives reward without replay")
	Supplies.inventory.restore(locked); Supplies.save_state()
	check(GuestActivities.migrate_legacy_ski_spoon() and not Supplies.is_owned(ITEM),"migration receipt prevents old records regranting after reset")
	check(Supplies.grant_activity_equipment(ITEM,"yellow_ski"),"restore test reward")
	check(WorkbenchSession.pantry_items("器具").has([ITEM,"我是奶龙"]),"reward available in tool pantry")
	SlotWallet.balance=10000; SlotWallet.persist()
	check(Supplies.purchase("sku_gin_london_dry",1),"stock for stirring test")
	check(issue("pour","withdraw",{"material":"gin","ml":30,"vessel":"glass"}),"liquid for stirring test")
	var bench=load("res://scenes/workbench.tscn").instantiate()
	add_child(bench); bench.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT); await frames()
	bench._show_category("器具")
	check(bench.item_buttons.has(ITEM),"legendary tool button visible")
	check(bench.table.can_target(ITEM,"器具","glass"),"legendary drag recognizes glass")
	bench._dropped("器具",ITEM,"glass",true); await frames()
	check(WorkbenchSession.state.session.get("spoon_tool_id")==ITEM and WorkbenchSession.state.session.spoon_vessel=="glass","drag equips legendary on actual vessel")
	var before_stir: Dictionary=Supplies.inventory.serialize()
	check(issue("legendary-stir","stir",{"vessel":"glass","seconds":0.5}),"legendary spoon performs real mixing")
	check(Supplies.inventory.serialize()==before_stir,"stirring consumes no extra inventory")
	var geometry: Dictionary=bench.table.spoon_geometry()
	check(geometry.get("tool_id")==ITEM and geometry.handle.y<geometry.tip.y,"head remains above working bowl")
	check(bench.table._hit(geometry.handle)=="spoon","legendary handle has clickable hit area")
	if "--spoon-capture" in OS.get_cmdline_user_args():
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("/tmp/legendary-spoon-workbench.png")
	bench._choose_item("器具","spoon"); await frames()
	check(WorkbenchSession.state.session.get("spoon_tool_id")=="tool_bar_spoon","ordinary spoon can be selected again")
	check(issue("remove","spoon",{"target":""}),"spoon removable")
	bench._choose_item("器具",ITEM); await frames()
	check(WorkbenchSession.state.session.get("spoon_tool_id")==ITEM,"click equips legendary")
	check(issue("reinsert","spoon",{"target":"glass","tool_id":ITEM}),"legendary reinsert")
	bench.queue_free(); await frames()
	var bag=load("res://scenes/backpack.tscn").instantiate(); add_child(bag); await frames()
	bag._select_item(ITEM); await frames()
	check(bag.detail_name.text=="我是奶龙" and bag.detail_status.text.contains("传说"),"backpack details use player-facing name and rarity")
	if "--spoon-capture" in OS.get_cmdline_user_args():
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("/tmp/legendary-spoon-backpack.png")
	bag.queue_free(); await frames()
	var reset_inv=Inventory.new(); check(reset_inv.restore(Supplies.inventory.serialize()),"reward state validates")
	reset_inv.reset(); check(not reset_inv.is_unlocked(ITEM),"new game clears reward")
	finish()
func finish() -> void:
	print("LEGENDARY SPOON: %d checks, %d failures" % [checks,failures.size()])
	get_tree().quit(0 if failures.is_empty() else 1)
