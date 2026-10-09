extends "res://tests/verify_workbench_drag.gd"
const Notes=preload("res://scripts/workbench_notes.gd")

func op(kind: String,payload: Dictionary={}) -> void:
	check(bench._issue(kind,payload),kind+": "+WorkbenchSession.last_error)

func run() -> void:
	Supplies.inventory.purchase("sku_mint_leaf",1)
	Supplies.inventory.purchase("sku_maraschino",1)
	check(Supplies._write(Supplies.inventory.serialize(),Supplies.workbench),"private ingredients")
	Supplies.changed.emit()
	WorkbenchSession.reset_game()
	home=load("res://scenes/home.tscn").instantiate()
	add_child(home)
	await settle()
	Navigation.go_to(&"mixing")
	await settle()
	bench=home.active_page
	op("cup",{"cup":"highball"})
	var frozen: Dictionary=bench.data.recipe.duplicate(true)
	op("withdraw",{"material":"vodka","ml":340,"vessel":"glass"})
	op("withdraw",{"material":"gin","ml":30,"vessel":"jigger"})
	check(bench.note.text.contains("金酒 30 ml · 现有 30 ml"),"recipe shows current table quantity")
	var stock: Dictionary=WorkbenchSession.state.stock.duplicate(true)
	op("transfer",{"source":"jigger","vessel":"glass"})
	check(WorkbenchSession.amount(bench.data.vessels.jigger)==20 and bench.data.vessels.glass.contents.gin==10,"full receiver retains 20 ml in source")
	check(bench.note.text.contains("金酒 30 ml · 现有 30 ml"),"partial transfer does not double count")
	drag_between(local_point(bench.table.POS.jigger),local_point(bench.table.DRAIN_RECT.get_center()))
	check(WorkbenchSession.amount(bench.data.vessels.jigger)==0,"native drag empties jigger")
	check(bench.note.text.contains("金酒 30 ml · 现有 10 ml") and bench.note.text.contains("待加 20 ml"),"discard immediately reduces visible current quantity")
	check(WorkbenchSession.dose_target("gin",bench.data)==20,"golden target agrees with remaining table contents")
	check(bench.note.text.contains("已倒掉 金酒 20 ml"),"discarded quantity remains a separate note")
	check(WorkbenchSession.state.stock==stock and bench.data.withdrawn.gin==30 and bench.data.consumed.sku_gin_london_dry==30,"discard cannot refund stock or reduce historical consumption")
	var actual: Dictionary=bench.data.duplicate(true)
	actual.recipe=WorkbenchSession.recipe_snapshot(MenuCatalog.get_recipe("gin_and_tonic"))
	check(WorkbenchSession.recipe_note(actual).contains("现有 10 ml"),"catalog recipe rows use physical quantity instead of consumed ledger")
	var saved: Dictionary=WorkbenchSession.snapshot()
	var path: String=Supplies.save_path
	Supplies.save_path=path+"/blocked.json"
	check(not bench._issue("empty",{"vessel":"glass"}) and WorkbenchSession.snapshot()==saved,"failed discard cannot change visible or saved quantity")
	Supplies.save_path=path
	WorkbenchSession.last_error=""
	op("empty",{"vessel":"glass"})
	check(bench.note.text.contains("金酒 30 ml · 现有 0 ml") and not bench.note.text.contains("＋额外 伏特加"),"fully discarded ingredient no longer counts as extra or current")
	check(WorkbenchSession.dose_target("gin",bench.data)==30,"full discard resets dose target")
	op("add_solid",{"material":"sku_mint_leaf","vessel":"mixing"})
	op("ice",{"ice":"cube","vessel":"mixing"})
	op("withdraw",{"material":"soda","ml":30,"vessel":"mixing"})
	op("filter",{"source":"mixing","vessel":"glass"})
	check(bench.note.text.contains("额外 薄荷叶 1") and bench.note.text.contains("制作冰 · 方冰现有 50 g"),"filtered solids and ice remain in source and notes")
	op("garnish",{"material":"garnish"})
	op("empty",{"vessel":"mixing"})
	check(not bench.note.text.contains("额外 薄荷叶") and not bench.note.text.contains("方冰现有 50 g"),"discard clears solid and ice progress too")
	check(bench.note.text.contains("额外 青柠角 1"),"discard leaves garnish in other cup intact")
	op("empty",{"vessel":"glass"})
	check(not bench.note.text.contains("额外 青柠角"),"discarded garnish no longer counts")
	check(bench.data.recipe==frozen,"recipe is unchanged")
	check(WorkbenchSession.load_state(),"save reload")
	bench._refresh()
	check(bench.note.text.contains("金酒 30 ml · 现有 0 ml") and not bench.note.text.contains("额外 薄荷叶"),"reload keeps accurate current quantities")
	# Compare the upper metal bowl, including the old disc position. The full hitbox
	# overlaps the changing bottom guidance panel and cannot be compared as an image.
	bench.table.selected=""
	bench.table.hover=""
	bench.table.transition_progress=1
	await capture("jigger-no-disc-empty")
	var empty_image: Image
	if DisplayServer.get_name()!="headless": empty_image=get_viewport().get_texture().get_image()
	op("withdraw",{"material":"sku_maraschino","ml":40,"vessel":"jigger"})
	bench.table.selected=""
	bench.table.hover=""
	bench.table.transition_progress=1
	await capture("jigger-no-disc-filled")
	if empty_image!=null:
		var filled:=get_viewport().get_texture().get_image()
		var rect: Rect2=bench.table.RECTS.jigger
		rect.size.y*=.5
		var render_scale:=Vector2(filled.get_size())/get_viewport().get_visible_rect().size
		var bounds:=Rect2i(local_point(rect.position)*render_scale,rect.size*bench.table.get_global_transform_with_canvas().get_scale()*render_scale)
		check(empty_image.get_region(bounds).get_data()==filled.get_region(bounds).get_data(),"pink liquid does not paint a floating disc over metal jigger")
	print("DISPOSAL NOTES: %d checks, %d failures" % [count,failures.size()])
	home.queue_free()
	await settle()
	get_tree().quit(0 if failures.is_empty() else 1)
