extends "res://tests/verify_workbench_drag.gd"
const GIN := "sku_gin_london_dry"
const LEMON := "sku_lemon_slice"

func same(a: Variant,b: Variant) -> bool:
	return JSON.parse_string(JSON.stringify(a))==JSON.parse_string(JSON.stringify(b))

func key(code: Key) -> void:
	var e:=InputEventKey.new()
	e.keycode=code
	e.pressed=true
	get_viewport().push_input(e,true)
	e.pressed=false
	get_viewport().push_input(e,true)

func issue(id: String,kind: String,payload: Dictionary={}) -> bool:
	return WorkbenchSession.command(id,str(WorkbenchSession.state.session.get("id","")),kind,payload)

func run() -> void:
	check(Supplies.reset_game() and WorkbenchSession.reset_game(),"empty shared inventory fixture")
	SlotWallet.balance=300000
	check(SlotWallet.persist(),"test wallet persists")
	home=load("res://scenes/home.tscn").instantiate()
	add_child(home)
	await settle()
	Navigation.go_to(&"mixing")
	await settle()
	bench=home.active_page
	check(WorkbenchSession.remaining("gin")==0 and not bench.item_buttons.has("gin") and bench.pantry_empty.visible,"empty warehouse has no free workbench stock")
	bench._begin_measure("gin",30)
	check(not is_instance_valid(bench.measure) and bench.status_label.text.contains("补货"),"empty material cannot start pouring")
	check(not issue("empty","withdraw",{"material":"gin","ml":5}),"service also refuses empty stock")
	key(KEY_S)
	await settle()
	check(is_instance_valid(bench.external_page) and bench.external_page.supplies==Supplies,"shortcut opens real shop using same warehouse")
	bench.external_page._select_item(GIN)
	var price: int=Supplies.get_unit_price(GIN)
	await get_tree().create_timer(.25).timeout
	await capture("shop-before-buy")
	click(bench.external_page.buy_button)
	await settle()
	check(SlotWallet.balance==300000-price and Supplies.total_remaining(GIN)==750,"native shop purchase debits wallet and delivers a full bottle")
	cancel()
	await settle()
	check(not is_instance_valid(bench.external_page) and bench.table.input_enabled,"escape returns to same workbench")
	check(bench.stock_labels.gin.text=="750 ml","purchase refreshes workbench stock immediately")
	from_pantry("gin","jigger")
	if not is_instance_valid(bench.measure): get_tree().quit(1); return
	bench.measure_waiting=false
	bench.measure.set_process(false)
	bench.measure.progress=.4
	space()
	check(Supplies.total_remaining(GIN)==732 and WorkbenchSession.state.session.vessels.jigger.contents.get("gin")==18,"off-golden actual 18 ml debits warehouse once")
	check(Supplies.get_state(GIN).quantity==1 and Supplies.get_state(GIN).current_remaining==732,"current bottle remaining tracked accurately")
	check(MenuCatalog.inventory[GIN]==732,"codex stock projection matches warehouse")
	var stock: Dictionary=Supplies.inventory.serialize()
	drag_between(local_point(bench.table.POS.jigger),local_point(bench.table.POS.glass))
	check(Supplies.inventory.serialize()==stock,"container transfer never debits warehouse")
	var before_balance: int=SlotWallet.balance
	key(KEY_B)
	await settle()
	check(is_instance_valid(bench.external_page) and bench.external_page.supplies==Supplies,"warehouse panel uses same service")
	bench.external_page._select_item(GIN)
	check(bench.external_page.detail_stock.text.contains("1") or bench.external_page.detail_values[0].text.contains("1"),"warehouse shows remaining packaged stock")
	await capture("17-shared-warehouse")
	cancel()
	await settle()
	check(WorkbenchSession.state.session.vessels.glass.contents.get("gin")==18 and SlotWallet.balance==before_balance,"warehouse round trip retains cup and wallet")
	check(Supplies.purchase(LEMON),"purchase lemon slices")
	var slices: float=Supplies.total_remaining(LEMON)
	click(bench.category_buttons[2])
	await settle()
	check(bench.stock_labels.lemon_slice.text=="%d 片" % int(slices),"lemon slices use pieces not ml")
	from_pantry("lemon_slice","glass")
	check(Supplies.total_remaining(LEMON)==slices-1 and WorkbenchSession.state.session.vessels.glass.garnish_id=="lemon_slice","dragging lemon consumes exactly one slice")
	var before: Dictionary=Supplies.serialize()
	from_pantry("lemon_slice","glass")
	check(Supplies.total_remaining(LEMON)==slices-2,"second deliberate garnish consumes a second slice")
	before=Supplies.serialize()
	check(WorkbenchSession.state.session.consumed[GIN]==18 and WorkbenchSession.state.session.consumed[LEMON]==2,"single cup records SKU quantities in their real units")
	var path: String=Supplies.save_path
	Supplies.save_path=path+"/unwritable.json"
	check(not issue("failed","withdraw",{"material":"gin","ml":10,"vessel":"mixing"}) and Supplies.serialize()==before,"save failure changes neither stock nor cup nor action log")
	Supplies.save_path=path
	check(issue("retry","withdraw",{"material":"gin","ml":10,"vessel":"mixing"}),"direct pour commits after write restored")
	before=Supplies.serialize()
	check(issue("retry","withdraw",{"material":"gin","ml":10,"vessel":"mixing"}) and Supplies.serialize()==before,"retry uses persisted receipt without extra debit")
	var disk: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(path))
	check(disk.has("workbench") and not disk.workbench.has("stock") and disk.workbench.session.vessels.mixing.contents.gin==10,"one file holds actual inventory and workbench, without a second stock ledger")
	check(Supplies.load_state() and WorkbenchSession.load_state() and same(Supplies.serialize(),before),"reload restores the complete transaction")
	check(issue("retry","withdraw",{"material":"gin","ml":10,"vessel":"mixing"}) and same(Supplies.serialize(),before),"retry after reload still cannot consume twice")
	var stock_before: Dictionary=Supplies.inventory.serialize()
	check(issue("discard","discard") and issue("new","start"),"discard and new session")
	check(Supplies.inventory.serialize()==stock_before,"discard/new never refunds or replenishes warehouse")
	# Run across a package boundary: 5 ml in the open bottle, then 750 ml unopened.
	check(Supplies.consume(GIN,Supplies.total_remaining(GIN)-5) and Supplies.purchase(GIN),"prepare open-bottle boundary through real service")
	check(issue("cross","withdraw",{"material":"gin","ml":18,"vessel":"glass"}),"pour crosses bottle boundary")
	check(Supplies.get_state(GIN).quantity==1 and Supplies.get_state(GIN).current_remaining==737,"one empty bottle removed and 13 ml taken from next bottle")
	check(Supplies.consume(GIN,730),"leave seven ml")
	before=Supplies.serialize()
	check(not issue("too-much","withdraw",{"material":"gin","ml":8}) and Supplies.serialize()==before,"insufficient actual dose fails atomically")
	check(issue("last","withdraw",{"material":"gin","ml":7}),"last seven ml can be used")
	check(Supplies.get_state(GIN).quantity==0 and Supplies.get_state(GIN).current_remaining==0,"empty last bottle has zero quantity and ml")
	check(Supplies.purchase(GIN) and WorkbenchSession.remaining("gin")==750,"shop refill is immediately usable again")
	var saved_cup: Dictionary=WorkbenchSession.state.session.duplicate(true)
	check(Supplies.purchase("sku_simple_syrup") and WorkbenchSession.state.session==saved_cup,"purchasing another material preserves half-made cup")
	check(issue("finished","finish") and WorkbenchSession.state.session.result.sales==false,"finishing does not invent sales revenue")
	# Import a legacy practice snapshot once, preserving its cup but not its free stock.
	var legacy: Dictionary=WorkbenchSession.state.duplicate(true)
	legacy.schema=1
	legacy.stock={"gin":600,"rum":600,"vodka":600,"lime":600,"syrup":600,"soda":600}
	legacy.garnish_stock=20
	var old_path: String=WorkbenchSession.save_path
	WorkbenchSession.save_path=path+".legacy"
	var file:=FileAccess.open(WorkbenchSession.save_path,FileAccess.WRITE)
	file.store_string(JSON.stringify(legacy))
	file.close()
	stock_before=Supplies.inventory.serialize()
	Supplies.workbench={}
	Supplies.workbench_initialized=false
	check(WorkbenchSession.load_state() and Supplies.inventory.serialize()==stock_before and WorkbenchSession.state.schema==2,"legacy migration preserves cup/history without granting or charging old free materials")
	check(FileAccess.file_exists(WorkbenchSession.save_path),"legacy file retained as original backup")
	WorkbenchSession.save_path=old_path
	check(Supplies.reset_game() and WorkbenchSession.state.session.is_empty(),"full game inventory reset clears associated cup")
	check(Supplies.load_state() and WorkbenchSession.load_state() and WorkbenchSession.remaining("gin")==0 and WorkbenchSession.state.session.is_empty(),"restart cannot resurrect the old practice stock")
	# Leave a fresh bought-and-poured UI for actual rendering verification.
	bench._clear_modal()
	issue("preview-start","start")
	Supplies.purchase(GIN)
	Supplies.purchase(LEMON)
	issue("preview-pour","withdraw",{"material":"gin","ml":30,"vessel":"glass"})
	issue("preview-garnish","garnish",{"material":"lemon_slice"})
	WorkbenchSession.set_table_materials(["gin"])
	click(bench.category_buttons[2])
	await settle()
	await get_tree().create_timer(1.2).timeout
	await capture("18-linked-workbench")
	print("WORKBENCH INVENTORY: %d checks, %d failures" % [count,failures.size()])
	home.queue_free()
	await settle()
	get_tree().quit(0 if failures.is_empty() else 1)
