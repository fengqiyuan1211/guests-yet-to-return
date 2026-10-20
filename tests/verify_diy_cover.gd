extends "res://tests/verify_research.gd"
const Preview = preload("res://scripts/workbench_drink_preview.gd")

func find_preview(node: Node) -> Control:
	if node.get_script() == Preview: return node
	for child in node.get_children():
		var found := find_preview(child)
		if found != null: return found
	return null

func run() -> void:
	if not OS.get_user_data_dir().contains("Codex-DIY-Image-Test-"):
		get_tree().quit(2)
		return
	var path := "user://diy_cocktails/images/fixture.png"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path.get_base_dir()))
	var picture := Image.create(32, 32, false, Image.FORMAT_RGBA8)
	picture.fill(Color(0.1, 0.8, 0.4, 0.8))
	check(picture.save_png(path) == OK, "private image fixture saved")
	op("begin_research", {"mode":"research_diy"})
	op("withdraw", {"material":"gin","ml":30,"vessel":"glass"})
	op("finish")
	var metadata := {"path":path,"source_drink_id":WorkbenchSession.state.session.result.drink_id,"task_id":"fixture","confirmed":true}
	op("save_research", {"name":"封面验证","english_name":"Cover","notes":"","image":metadata})
	var recipe: Dictionary = WorkbenchSession.research_recipes()[0]
	check(recipe.result.image_path == path and recipe.image_path == path, "new recipe and result both retain confirmed cover")
	check(MenuCatalog.get_recipe(recipe.id).thumbnail == path, "menu bridge preserves cover")
	# Reproduce existing saves made before the fix: only the top-level record has the image.
	var old_result: Dictionary = recipe.result.duplicate(true)
	old_result.erase("image_path")
	WorkbenchSession.state.research.recipes[recipe.id].result = old_result
	recipe = WorkbenchSession.research_recipes()[0]
	check(Research.preview_result(recipe).image_path == path, "old recipe cover takes priority over pre-generation snapshot")
	check(not recipe.result.has("image_path"), "rendering does not rewrite old save data")
	var journal = load("res://scenes/codex.tscn").instantiate()
	journal.selected_filter = 3
	add_child(journal)
	await settle()
	var card = journal.page_content.get_node("CardSlot1")
	var art := find_preview(card)
	check(art != null and art.saved_art != null, "DIY codex card decodes generated PNG")
	if art != null and art.saved_art != null:
		check(art.saved_art.get_image().get_data() == picture.get_data(), "card uses saved cover pixels")
	journal.show_detail(recipe.id)
	await settle()
	art = find_preview(journal.page_content)
	check(art != null and art.saved_art != null, "DIY detail uses generated PNG")
	journal.queue_free()
	var reused := Preview.new()
	add_child(reused)
	reused.result = Research.preview_result(recipe)
	check(reused.saved_art != null, "selection changed after ready loads cover")
	reused.result = old_result
	check(reused.saved_art == null, "image-free selection clears previous cover")
	reused.result = Research.preview_result(recipe)
	check(reused.saved_art != null, "switching back restores saved cover")
	var missing := Research.preview_result(recipe)
	missing.image_path = "user://diy_cocktails/images/missing.png"
	reused.result = missing
	check(reused.saved_art == null, "missing file falls back to recipe preview")
	reused.queue_free()
	check(Supplies.commit_workbench(WorkbenchSession.state), "old-shape fixture persisted")
	check(Supplies.load_state() and WorkbenchSession.load_state(), "saved recipe reloads")
	check(Research.preview_result(WorkbenchSession.research_recipes()[0]).image_path == path, "cover persists across reload")
	await settle()
	print("DIY COVER: %d checks, %d failures" % [count, failures.size()])
	get_tree().quit(0 if failures.is_empty() else 1)
