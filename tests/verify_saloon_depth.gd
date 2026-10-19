extends "res://tests/verify_pixel_b.gd"
const Composition = preload("res://scripts/saloon_composition.gd")

func run() -> void:
	output="/tmp/saloon-depth-preview"
	home=load("res://scenes/home.tscn").instantiate()
	add_child(home)
	await settle()
	TimeManager.set_process(false)
	var guests=home.get_node("%GuestLayer")
	var foreground: TextureRect=home.get_node("Stage/ForegroundCounter")
	var background: TextureRect=home.get_node("Background")
	check(foreground.get_index()>guests.get_index(),"counter occludes guests")
	check(foreground.get_index()<home.get_node("%HomeContent").get_index(),"counter stays behind interface")
	check(foreground.material==background.material,"counter shares live room lighting")
	check(foreground.mouse_filter==Control.MOUSE_FILTER_IGNORE,"counter never intercepts input")
	await screenshot("00-empty")
	for i in range(guests.profiles.size()):
		guests.show_guest(i)
		await screenshot("01-"+str(guests.profiles[i].id))
		check(not guests._window.clip_contents,"guest is occluded by scenery, not cut at frame")
		if str(guests.profiles[i].id) in Pixel.CAMEOS:
			check(guests._art.texture.resource_path==str(guests.profiles[i].texture),"cameo source unchanged")
		if DisplayServer.get_name()!="headless":
			var stage: Control=home.get_node("%Stage")
			var origin:=stage.get_global_transform_with_canvas()*Vector2(420,Composition.COUNTER_Y+8)
			var region:=Rect2i(Vector2i(origin),Vector2i(Vector2(650,55)*stage.scale))
			var with_guest:=get_viewport().get_texture().get_image().get_region(region).get_data()
			guests.hide()
			await settle(); await RenderingServer.frame_post_draw
			var without_guest:=get_viewport().get_texture().get_image().get_region(region).get_data()
			check(with_guest==without_guest,"no body pixels leak onto countertop: "+str(guests.profiles[i].id))
			guests.show()
	guests.show_guest(1)
	TimeManager.minutes_since_midnight=12*60
	await screenshot("03-day")
	check(foreground.material.get_shader_parameter("day_weight")>.99,"counter receives daytime lighting")
	TimeManager.minutes_since_midnight=21*60
	await screenshot("03-night")
	check(background.light_weights.y>.99,"night lighting still follows the game clock")
	check(foreground.material.get_shader_parameter("night_weight")>.99,"counter receives the same night lighting")
	TimeManager.minutes_since_midnight=18*60
	var original_size:=get_window().size
	for resolution in [Vector2i(1024,768),Vector2i(1600,720)]:
		get_window().size=resolution
		await settle()
		var stage: Control=home.get_node("%Stage")
		check(background.position.is_equal_approx(stage.position),"background and guests share letterbox origin")
		check(background.size.is_equal_approx(Composition.DESIGN_SIZE*stage.scale),"background and guests share scale")
		var expected_y:=background.position.y+background.size.y*Composition.COUNTER_SOURCE_Y/Composition.SOURCE_SIZE.y
		check(absf(foreground.get_global_rect().position.y-expected_y)<.1,"foreground lip aligns with painted edge")
		await screenshot("02-%dx%d" % [resolution.x,resolution.y])
	get_window().size=original_size; await settle()
	var before:=StoryDialogue.speech
	Navigation.go_to(&"shop"); await settle()
	check(not guests.visible,"shop hides guests")
	Navigation.go_to(&"home"); await settle()
	check(guests.visible and StoryDialogue.speech==before,"return preserves guest and dialogue")
	home.queue_free(); await settle()
	print("SALOON DEPTH: %d checks, %d failures" % [count,failures.size()])
	get_tree().quit(0 if failures.is_empty() else 1)
