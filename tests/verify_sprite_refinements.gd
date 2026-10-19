extends "res://tests/verify_character_activities.gd"
const Pixel=preload("res://scripts/pixel_art.gd")

func run() -> void:
	home=load("res://scenes/home.tscn").instantiate(); add_child(home); await settle()
	check(GuestActivities.begin("milo_ferry"),"ferry demo begins")
	Navigation.go_to(&"milo_ferry"); await settle(); bench=home.active_page
	bench._start(); await settle()
	if DisplayServer.get_name()!="headless": get_window().grab_focus(); await settle()
	if bench.paused: bench._resume()
	await capture("sprite-01-ferry-bank")
	await ferry_drag()
	bench.select_person(0); bench.select_person(1); await settle()
	await capture("sprite-02-ferry-boat")
	check(bench.selection==[1,1],"both passenger types board together")
	bench.remove_person(0); bench.remove_person(1)
	await complete_game()
	bench.board.hide(); bench._close(); await settle()
	Navigation.go_to(&"mixing"); await settle(); bench=home.active_page
	SlotWallet.balance=300000
	check(Supplies.purchase("sku_mint_sprig") and Supplies.purchase("sku_cocktail_cherry"),"private garnish stock")
	bench._act("cup",{"cup":"highball"})
	bench._issue("withdraw",{"material":"gin","ml":40,"vessel":"glass"})
	bench._issue("withdraw",{"material":"soda","ml":100,"vessel":"glass"})
	bench._show_category("装饰")
	var before:=WorkbenchSession.remaining("garnish")
	bench._act("garnish",{"material":"garnish"}); await get_tree().create_timer(.5).timeout
	check(WorkbenchSession.remaining("garnish")==before-1,"rim artwork still consumes exactly one lime")
	await capture("sprite-03-lime-highball")
	for id in ["lemon_slice","sku_cocktail_cherry","sku_mint_sprig"]:
		before=WorkbenchSession.remaining(id)
		bench._act("garnish",{"material":id})
		check(WorkbenchSession.remaining(id)==before-1,"decoration consumes one unit: "+id)
	await get_tree().create_timer(.5).timeout
	await capture("sprite-04-mixed-garnishes")
	var state:=WorkbenchSession.snapshot()
	bench.table.set_process(false)
	bench.table.animated_source="glass"; bench.table.animated_destination="mixing"; bench.table.animation_progress=.5
	bench.table.queue_redraw(); await capture("sprite-06-tilted-garnishes")
	bench.table.animated_source=""; bench.table.set_process(true); await settle()
	var gallery:=Control.new(); gallery.size=Vector2(1600,900); bench.surface.add_child(gallery)
	var backing:=ColorRect.new(); backing.size=gallery.size; backing.color=Color("352b25"); gallery.add_child(backing)
	var ids: Array=["garnish","lemon_slice","sku_cocktail_cherry","sku_mint_sprig"]
	var cups: Array=["highball","coupe","glass_cocktail_glass","glass_balloon_glass"]
	for i in range(4):
		var preview:=preload("res://scripts/workbench_drink_preview.gd").new()
		preview.position=Vector2(30+i*390,150); preview.size=Vector2(360,570)
		preview.result={"cup":cups[i],"capacity_ml":200,"contents":{"contents":{"gin":40.0,"soda":90.0},"solids":{},"garnish":true,"garnishes":[ids[i]]}}
		gallery.add_child(preview)
	await capture("sprite-05-garnish-glasses")
	check(WorkbenchSession.snapshot()==state,"preview rendering never changes recipe or inventory")
	gallery.queue_free(); await settle()
	home.queue_free(); await settle()
	print("SPRITE REFINEMENTS: %d checks, %d failures" % [count,failures.size()])
	get_tree().quit(0 if failures.is_empty() else 1)
