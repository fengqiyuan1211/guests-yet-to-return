extends "res://tests/verify_workbench_drag.gd"
const Mint=preload("res://scripts/workbench_mint.gd")
const Preview=preload("res://scripts/workbench_drink_preview.gd")
const GarnishPreview=preload("res://scripts/workbench_garnish_preview.gd")

func run() -> void:
	for id in ["sku_mint_leaf","sku_mint_sprig","sku_cointreau","sku_maraschino"]: Supplies.inventory.purchase(id,2)
	check(Supplies._write(Supplies.inventory.serialize(),Supplies.workbench),"private mint and color fixture")
	Supplies.changed.emit()
	WorkbenchSession.reset_game()
	home=load("res://scenes/home.tscn").instantiate()
	add_child(home)
	await settle()
	Navigation.go_to(&"mixing")
	await settle()
	bench=home.active_page
	for id in ["gin","rum","vodka","lime","soda"]: check(bench._place_material(id),"place "+id)
	bench._issue("withdraw",{"material":"gin","ml":20,"vessel":"glass"})
	var before:=WorkbenchSession.snapshot()
	check(bench._place_material("syrup"),"sixth material available")
	check(WorkbenchSession.state.table_materials==["rum","vodka","lime","soda","syrup"],"FIFO return oldest bottle")
	check(WorkbenchSession.state.session==before.session and WorkbenchSession.state.stock==before.stock,"return changes no production or inventory facts")
	check(bench.feedback_text.text.contains("已收起"),"non-modal return feedback")
	before=WorkbenchSession.snapshot()
	check(bench._place_material("vodka") and WorkbenchSession.snapshot()==before,"reselect existing bottle neither duplicates nor reorders")
	var path: String=Supplies.save_path
	Supplies.save_path=path+"/blocked.json"
	check(not bench._place_material("gin") and WorkbenchSession.snapshot()==before,"FIFO write failure is atomic")
	Supplies.save_path=path
	check(not WorkbenchSession.place_table_material("unknown") and WorkbenchSession.snapshot()==before,"unknown material cannot evict bottle")
	check(not WorkbenchSession.place_table_material("sku_cola") and WorkbenchSession.snapshot()==before,"out-of-stock material cannot evict bottle")
	bench._begin_measure("gin",20,"jigger")
	check(is_instance_valid(bench.measure),"sixth material directly starts pouring")
	before=WorkbenchSession.snapshot()
	bench._begin_measure("rum",20,"jigger")
	check(WorkbenchSession.snapshot()==before and bench.table.bottle=="gin","active measuring bottle cannot be displaced")
	cancel()
	check(WorkbenchSession.load_state() and WorkbenchSession.state.table_materials==before.table_materials,"FIFO arrangement survives reload")
	var rect:=Rect2(0,0,180,280)
	var layers: Array=[{"contents":{"sku_maraschino":90.0}},{"contents":{"sku_cointreau":90.0}},{"contents":{"soda":90.0}}]
	var snapshot:=layers.duplicate(true)
	var bands:=Liquid.layer_bands(rect,270,350,false,false,false,0,"highball",layers)
	check(layers==snapshot and bands.size()==3,"soft-edge model never edits saved layers")
	for i in range(2):
		var y: float=bands[i].top
		var width: float=bands[i].width
		check(width>0 and width<=minf(bands[i].height,bands[i+1].height)*.31,"gradient bounded by both neighboring layer heights")
		var a:=Liquid.layer_color_at(Vector2(90,y-.01),rect,bands)
		var b:=Liquid.layer_color_at(Vector2(90,y+.01),rect,bands)
		check(absf(a.r-b.r)+absf(a.g-b.g)+absf(a.b-b.b)+absf(a.a-b.a)<.01,"boundary colors are continuous")
		check(a!=bands[i].tint and a!=bands[i+1].tint,"boundary has an intermediate translucent color")
	var thin:=Liquid.layer_bands(rect,181,350,false,false,false,0,"highball",[{"contents":{"gin":90.0}},{"contents":{"lime":1.0}},{"contents":{"soda":90.0}}])
	check(thin[0].width+thin[1].width<thin[1].height,"one-ml thin layer is not swallowed by neighboring gradients")
	check(Mint.TEXTURE.get_width()>500 and Mint.TEXTURE.get_image().get_pixel(0,0).a<.01,"B painted asset loads with transparent exterior")
	check(Mint._mesh_point(Vector2(.8,.3),70,0,0)!=Mint._mesh_point(Vector2(.8,.3),70,0,1),"leaf surface bends during motion")
	bench._issue("discard")
	bench._issue("start")
	bench._issue("cup",{"cup":"highball"})
	for id in ["gin","rum","vodka","lime","soda","syrup"]: bench._place_material(id)
	for target in ["glass","mixing"]:
		for i in range(3): bench._issue("add_solid",{"material":"sku_mint_leaf","vessel":target})
		bench._issue("withdraw",{"material":"sku_maraschino","ml":60,"vessel":target})
		bench._issue("withdraw",{"material":"sku_cointreau","ml":60,"vessel":target})
		bench._issue("withdraw",{"material":"soda","ml":70,"vessel":target})
	bench._act("garnish",{"material":"sku_mint_sprig"})
	bench._show_category("配料")
	await get_tree().create_timer(1.3).timeout
	before=WorkbenchSession.snapshot()
	await capture("b-polish-01-table")
	check(WorkbenchSession.snapshot()==before,"mint and gradient animation preserves authoritative state")
	var gallery:=Control.new()
	gallery.size=Vector2(1600,900)
	bench.surface.add_child(gallery)
	var bg:=ColorRect.new()
	bg.size=gallery.size
	bg.color=Color("30251d")
	gallery.add_child(bg)
	bench._text(gallery,Rect2(35,20,1500,60),"B 版薄荷 · 分层柔化 · Godot 实际渲染",30)
	var art:=GarnishPreview.new()
	art.kind="sku_mint_leaf"
	art.position=Vector2(50,150)
	art.size=Vector2(350,470)
	gallery.add_child(art)
	bench._text(gallery,Rect2(80,730,360,40),"备料柜与拖动共用的薄荷",22)
	for i in range(2):
		var preview:=Preview.new()
		preview.position=Vector2(450+i*550,95)
		preview.size=Vector2(530,660)
		var vessel: Dictionary=bench.data.vessels.glass.duplicate(true)
		if i==1:
			vessel.contents={"rum":45.0,"lime":25.0,"soda":120.0}
			vessel.layers=[{"contents":vessel.contents.duplicate()}]
			vessel.ice="cube"
			vessel.ice_batches=[{"kind":"cube","mass_g":50.0,"volume":50.0,"pieces":4}]
		preview.result={"cup":"highball","contents":vessel,"capacity_ml":350,"liquid_profiles":bench.data.liquid_profiles}
		gallery.add_child(preview)
		bench._text(gallery,Rect2(505+i*550,778,440,45),"柔化分层与薄荷" if i==0 else "混合酒液、薄荷与冰块",23)
	await capture("b-polish-02-details")
	gallery.queue_free()
	print("B POLISH: %d checks, %d failures" % [count,failures.size()])
	home.queue_free()
	await settle()
	get_tree().quit(0 if failures.is_empty() else 1)
