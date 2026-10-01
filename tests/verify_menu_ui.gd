extends Node
var failures: Array[String] = []
var home: Control
var menu: Control
var directory := "res://../output/menu-preview"

func check(ok: bool, message: String) -> void:
	if not ok:
		failures.append(message)
		push_error(message)

func settle() -> void:
	await get_tree().process_frame
	await get_tree().process_frame

func _ready() -> void:
	if not MenuCatalog.save_path.begins_with("/tmp/") or not GameSession.save_path.begins_with("/tmp/") or not StoryDialogue.save_path.begins_with("/tmp/") or not SlotWallet.save_path.begins_with("/tmp/"):
		get_tree().quit(2)
		return
	TimeManager.set_process(false)
	call_deferred("run")

func capture(name: String) -> void:
	if DisplayServer.get_name() == "headless":
		return
	await get_tree().create_timer(0.2).timeout
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(directory))
	check(get_viewport().get_texture().get_image().save_png(directory.path_join(name + ".png")) == OK, "Save screenshot")

func click(button: Control) -> void:
	var event := InputEventMouseButton.new()
	event.position = button.get_global_rect().get_center()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = true
	get_viewport().push_input(event, true)
	event = event.duplicate()
	event.pressed = false
	get_viewport().push_input(event, true)

func draw_line() -> void:
	var canvas: Control = menu.drawing
	var from: Vector2 = canvas.get_global_transform() * Vector2(70, 691)
	var to: Vector2 = canvas.get_global_transform() * Vector2(170, 693)
	var event := InputEventMouseButton.new()
	event.position = from
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = true
	get_viewport().push_input(event, true)
	var move := InputEventMouseMotion.new()
	move.position = to
	move.button_mask = MOUSE_BUTTON_MASK_LEFT
	get_viewport().push_input(move, true)
	event = event.duplicate()
	event.position = to
	event.pressed = false
	get_viewport().push_input(event, true)

func run() -> void:
	home = load("res://scenes/home.tscn").instantiate()
	add_child(home)
	await settle()
	Navigation.go_to(&"menu")
	await settle()
	menu = home.active_page
	check(menu != null and menu.has_method("_enter_samples"), "Menu route uses real editor")
	check(menu.selected.is_empty() and MenuCatalog.all_recipes().size() == 5 and MenuCatalog.unlocked_recipes().is_empty(), "Five catalogued classics remain locked and off the menu")
	await capture("01-empty-catalog")
	click(menu.find_child("PreviewSamples", true, false))
	await settle()
	check(menu.sample_mode and menu.selected.size() == 4, "Sample entry is interactive")
	await capture("02-select-drinks")
	click(menu.find_child("MakeMenu", true, false))
	await settle()
	check(menu.step == 1 and menu.poster != null, "Selection proceeds to editor")
	await capture("03-parchment-template")
	menu._set_template("nocturne")
	await settle()
	await capture("04-nocturne-template")
	menu._set_template("parchment")
	click(menu.find_child("Method_draw", true, false))
	await settle()
	check(menu.drawing.editable, "Drawing method accepts input")
	menu.drawing.clear_canvas()
	draw_line()
	check(menu.drawing.get_strokes().size() == 1, "Mouse draws through scaled paper")
	menu._set_eraser(true)
	check(menu.drawing.can_undo(), "Tool change preserves undo")
	menu._set_eraser(false)
	menu.drawing.undo()
	check(menu.drawing.get_strokes().is_empty(), "Undo ink")
	menu.drawing.redo()
	check(menu.drawing.get_strokes().size() == 1, "Redo ink")
	menu.design.title = "晚风与好酒"
	menu._refresh_poster()
	check(menu.drawing.can_undo(), "Retitling keeps ink undo history")
	menu._save()
	check(FileAccess.file_exists(MenuCatalog.save_path + ".sample"), "Sample persisted")
	check(MenuCatalog.entries.is_empty() and MenuCatalog.menu_for_ai().selected_drinks.is_empty(), "Samples never reach real orders")
	await capture("05-drawing-editor")
	if DisplayServer.get_name() != "headless":
		var output := ProjectSettings.globalize_path(directory.path_join("06-exported-menu.png"))
		check(await menu.export_png(output), "Export high resolution PNG")
		var png := Image.load_from_file(output)
		check(png.get_size() == Vector2i(1080, 1620), "Export dimensions")
	click(menu.find_child("Method_ai", true, false))
	await settle()
	menu.prompt_edit.text = "像一封从荒野寄来的旧信，边角有野花。"
	menu.design.ai_prompt = menu.prompt_edit.text
	await capture("07-ai-artist")
	check(not MenuArt.is_available(), "No fake connected AI")
	var payload := MenuArt.build_request(menu.design.ai_prompt, menu._selected_drinks(), menu.design.title, menu.design.subtitle)
	check(payload.selected_drinks.size() == 4 and payload.render_mode == "background_only", "Provider request contains choices and safe text layout")
	menu._go_selection()
	await settle()
	menu._leave_samples()
	check(menu.selected.is_empty(), "Leaving preview returns real menu")
	menu._enter_samples()
	menu._go_editor()
	await settle()
	check(menu.design.title == "晚风与好酒" and menu.drawing.get_strokes().size() == 1, "Reload sample retains ink and title")
	get_window().size = Vector2i(960, 540)
	await settle()
	await capture("08-small-landscape")
	Navigation.go_to(&"home")
	await settle()
	check(home.get_node("%HomeContent").visible and home.active_page == null, "Home navigation restored")
	print("MENU_UI: ", "PASS" if failures.is_empty() else failures)
	get_tree().quit(0 if failures.is_empty() else 1)
