extends "res://tests/verify_workbench_scene.gd"
const Pixel=preload("res://scripts/pixel_art.gd")
var page: Control
var output := "/tmp/pixel-b-preview"

func screenshot(label: String) -> void:
	await settle()
	if DisplayServer.get_name()=="headless": return
	await get_tree().create_timer(.35).timeout
	RenderingServer.force_draw()
	DirAccess.make_dir_recursive_absolute(output)
	get_viewport().get_texture().get_image().save_png(output+"/"+label+".png")

func fits_viewport(control: Control, label: String) -> void:
	var rect:=control.get_global_rect()
	var viewport:=get_viewport().get_visible_rect().grow(1)
	check(viewport.encloses(rect),label+" fits viewport: "+str(rect))

func run() -> void:
	for sku in ["sku_tonic_water","sku_bleu_de_minuit"]:
		check(Supplies.inventory.purchase(sku,2),"private render stock "+sku)
	check(Supplies._write(Supplies.inventory.serialize(),{}),"save private render stock")
	for item: Dictionary in preload("res://scripts/supply_catalog.gd").new().list_items():
		check(Pixel.sprite(str(item.id))!=null,"pixel SKU: "+str(item.id))
	var profiles: Array=JSON.parse_string(FileAccess.get_file_as_string("res://data/guests.json"))
	for profile in profiles:
		var picture:=Pixel.person(profile)
		check(picture!=null,"portrait "+str(profile.id))
		if profile.id in Pixel.CAMEOS: check(picture.resource_path==profile.texture,"cameo original source "+str(profile.id))
	page=load("res://scenes/title_screen.tscn").instantiate()
	add_child(page)
	await screenshot("01-title")
	page.queue_free(); await settle()
	home=load("res://scenes/home.tscn").instantiate()
	add_child(home)
	await settle()
	TimeManager.set_process(false)
	home.get_node("%GuestLayer").show_guest(2)
	await screenshot("02-home-hank")
	for id in ["ada","milo"]:
		for i in range(profiles.size()):
			if profiles[i].id==id: home.get_node("%GuestLayer").show_guest(i)
		await screenshot("02-home-"+id)
	for route in [&"shop",&"research",&"codex",&"menu",&"backpack",&"journal"]:
		Navigation.go_to(route); await settle()
		check(is_instance_valid(home.active_page),"page opens: "+str(route))
		await screenshot("03-"+str(route))
		if route==&"research":
			home.active_page._show("legendary")
			await screenshot("03-research-legendary")
			home.active_page._show("library")
			await screenshot("03-research-library")
	Navigation.go_to(&"mixing"); await settle(); bench=home.active_page
	bench._issue("cup",{"cup":"highball"})
	bench._issue("withdraw",{"material":"gin","ml":50,"vessel":"glass"})
	bench._issue("withdraw",{"material":"sku_tonic_water","ml":150,"vessel":"glass"})
	bench._issue("ice",{"ice":"cube","vessel":"glass"})
	bench._place_material("gin")
	bench._place_material("sku_bleu_de_minuit")
	await screenshot("04-workbench")
	bench._issue("lid")
	check(WorkbenchSession.state.session.lid,"new shaker artwork still assembles")
	await screenshot("04-workbench-closed-shaker")
	table_click(bench.table._rect("cap").get_center())
	await settle()
	check(not WorkbenchSession.state.session.lid,"assembled cap remains clickable")
	check(Pixel.sprite("highball_glass").resource_path.contains("/v3/"),"approved fine-pixel glass art is used")
	check(Pixel.sprite("shaker_body").resource_path.contains("/v3/"),"approved fine-pixel shaker art is used")
	check(bench.table.RECTS.shaker.end.y<780,"shaker clears the bottom instruction panel")
	var original_size:=get_window().size
	for resolution in [Vector2i(1024,768),Vector2i(1280,800),Vector2i(1280,540)]:
		get_window().size=resolution
		await settle()
		fits_viewport(bench.surface,"workbench "+str(resolution))
		await screenshot("08-workbench-%dx%d" % [resolution.x,resolution.y])
	get_window().size=original_size
	await settle()
	var before:=WorkbenchSession.snapshot()
	await settle()
	check(WorkbenchSession.snapshot()==before,"rendering never mutates drink state")
	for id in ["milo_ferry","ada_watch_memory","hank_lantern"]:
		check(GuestActivities.begin(id),"activity begins "+id)
		Navigation.go_to(StringName(id)); await settle()
		home.active_page._start(); await settle()
		check(Pixel.scene(id)==Pixel.scene(id),"background retained between draw frames "+id)
		await screenshot("05-"+id)
	Navigation.go_to(&"mixing"); await settle(); bench=home.active_page
	var gallery:=Control.new()
	gallery.size=Vector2(1600,900)
	bench.surface.add_child(gallery)
	var backdrop:=ColorRect.new()
	backdrop.size=gallery.size; backdrop.color=Color("382b31"); gallery.add_child(backdrop)
	var cups: Array=["coupe","highball","glass_cocktail_glass","glass_balloon_glass"]
	for i in range(cups.size()):
		var preview:=preload("res://scripts/workbench_drink_preview.gd").new()
		preview.position=Vector2(35+i*390,150); preview.size=Vector2(360,570)
		preview.result={"cup":cups[i],"capacity_ml":200,"contents":{"contents":{"sku_bleu_de_minuit":130.0},"solids":{}}}
		gallery.add_child(preview)
	await screenshot("06-glass-liquid-alignment")
	gallery.queue_free(); await settle()
	home.queue_free(); await settle()
	check(OpeningFlow.begin_story(),"private opening preview starts")
	page=load("res://scenes/opening_story.tscn").instantiate()
	add_child(page); await settle()
	page.dialogue.visible_characters=page.dialogue.text.length()
	click(page.auto_button); await settle()
	check(page.autoplay.enabled,"actual autoplay button accepts mouse")
	await screenshot("07-opening-auto")
	for resolution in [Vector2i(1024,768),Vector2i(1280,800),Vector2i(1280,540)]:
		get_window().size=resolution; await settle()
		fits_viewport(page.stage,"opening "+str(resolution))
		fits_viewport(page.auto_button,"autoplay button "+str(resolution))
	await screenshot("08-opening-wide")
	get_window().size=original_size; await settle()
	print("PIXEL B: %d checks, %d failures" % [count,failures.size()])
	get_tree().quit(0 if failures.is_empty() else 1)
