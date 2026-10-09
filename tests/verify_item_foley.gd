extends "res://tests/verify_workbench_drag.gd"

func pause_clicks() -> void:
	var deadline:=Time.get_ticks_msec()+100
	while Time.get_ticks_msec()<deadline: await get_tree().process_frame

func run() -> void:
	var ui: Node=SaloonAudio.ui
	ui.focused=true
	var families: Dictionary={}
	for row in Supplies.catalog.list_items():
		var family: String=ui.material(row)
		check(family!="click","catalog material mapped: "+str(row.id))
		families[family]=true
	for pair in [["gin","bottle"],["sku_angostura_bitters","small_bottle"],["lime","juice_bottle"],["soda","fizzy_bottle"],["sku_mint_leaf","leaf"],["sku_mint_sprig","leaf"],["sku_white_cane_sugar","grain"],["garnish","fruit"],["sku_cocktail_cherry","cherry"],["mixing","glass"],["muddler","wood"],["spoon","metal"],["cube","ice"],["crushed","crushed_ice"]]:
		check(ui.material({"id":pair[0]})==pair[1],"specific item family: "+pair[0])
		families[pair[1]]=true
	for family: String in families:
		for purchase in [false,true]:
			for variant in [1,2]:
				var path: String=ui.config.root+("purchase-" if purchase else "")+family+"-%d.wav" % variant
				var clip:=load(path) as AudioStreamWAV
				check(clip!=null and clip.get_length()>.03 and clip.get_length()<1 and clip.data.size()>1000,"short recorded/composite cue decodes: "+path)
	ui.item("gin")
	var first: String=ui.last_clip
	var hits: int=ui.played
	ui.item("gin")
	check(ui.played==hits,"duplicate contact within one event is suppressed")
	await pause_clicks()
	ui.item("gin")
	check(ui.last_clip!=first and ui.last_cue=="bottle","repeated item rotates clip rather than identical playback")
	Supplies.inventory.purchase("sku_mint_leaf",1)
	check(Supplies._write(Supplies.inventory.serialize(),Supplies.workbench),"isolated herb stock")
	Supplies.changed.emit()
	WorkbenchSession.reset_game()
	home=load("res://scenes/home.tscn").instantiate()
	add_child(home)
	await settle()
	Navigation.go_to(&"mixing")
	await settle()
	bench=home.active_page
	await pause_clicks()
	var stock: Dictionary=WorkbenchSession.state.stock.duplicate(true)
	hits=ui.played
	click(bench.item_buttons.gin)
	check(ui.played==hits+1 and ui.last_cue=="bottle","pantry click plays bottle exactly once on pickup")
	check(WorkbenchSession.state.stock==stock,"clicking material does not consume stock")
	await pause_clicks()
	hits=ui.played
	table_click(bench.table.bottle_rect("gin").get_center())
	check(ui.played==hits+1 and ui.last_cue=="bottle","table bottle gets same material cue")
	await pause_clicks()
	hits=ui.played
	table_click(bench.table.POS.mixing)
	check(ui.played==hits+1 and ui.last_cue=="glass","table mixing glass sounds like glass not metal")
	bench._show_category("配料")
	await settle()
	await pause_clicks()
	hits=ui.played
	from_pantry("sku_mint_leaf","glass")
	check(ui.last_cue=="leaf" and ui.played==hits+1,"native leaf drag replaces generic click and same-frame duplicate placement")
	check(bench.data.vessels.glass.solids.get("sku_mint_leaf",0)==1,"leaf drag still consumes and adds exactly once")
	bench._show_category("冰块")
	await settle()
	await pause_clicks()
	hits=ui.played
	from_pantry("crushed","glass")
	check(ui.last_cue=="crushed_ice" and ui.played==hits+1,"crushed ice has granular ice cue")
	bench._show_category("器具")
	await settle()
	await pause_clicks()
	hits=ui.played
	from_pantry("muddler","glass")
	check(ui.last_cue=="wood" and ui.played==hits+1,"muddler pickup is muted wood not metallic click")
	await pause_clicks()
	hits=ui.played
	table_click(bench.table.muddler_rect().position+Vector2(26,30))
	check(ui.last_cue=="wood" and ui.played==hits+1,"inserted handle regrab has material cue")
	Navigation.go_to(&"backpack")
	await settle()
	var backpack: Control=home.active_page
	await pause_clicks()
	hits=ui.played
	var card: Button=backpack.item_buttons[0]
	click(card)
	check(ui.played==hits+1 and ui.last_cue==ui.material({"id":card.get_meta("item_id")}),"warehouse card shares same SKU material cue")
	print("ITEM FOLEY: %d checks, %d failures" % [count,failures.size()])
	home.queue_free()
	await settle()
	get_tree().quit(0 if failures.is_empty() else 1)
