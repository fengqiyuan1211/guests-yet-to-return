extends Node
var failures:=0
func check(value: bool,label: String) -> void:
	if not value: failures+=1; push_error(label)
func _ready() -> void:
	if not WorkbenchSession.save_path.begins_with("/tmp/"): get_tree().quit(2); return
	await get_tree().process_frame
	var codex=load("res://scripts/codex.gd").new()
	var original: Dictionary=WorkbenchSession.state.research.duplicate(true)
	WorkbenchSession.state.research.acquired={}
	var research=load("res://scenes/research.tscn").instantiate()
	add_child(research)
	research._show("legendary")
	check(research.body.find_children("Legendary_*", "Button", true, false).is_empty(),"unearned research recipes hidden")
	for filter in [0,1,2]:
		codex.selected_filter=filter
		for recipe in codex._visible_recipes():
			check(str(recipe.get("source_guest","")).is_empty() and recipe.get("unlock_kind")!="legendary_mastery","secret hidden in all filters")
	for id in ["character_milo","character_ada","character_hank","childhood_keepsake"]:
		check(codex._recipe(id).is_empty(),"secret detail hidden: "+id)
	WorkbenchSession.state.research.acquired.character_milo="test"
	codex.selected_filter=0
	var found:=0
	for recipe in codex._visible_recipes():
		if recipe.id=="character_milo": found+=1
	check(found==1,"earned reward appears exactly once")
	check(not codex._recipe("character_milo").is_empty(),"earned detail available")
	check(codex._recipe("character_ada").is_empty(),"other reward remains hidden")
	check(not codex._recipe("gin_and_tonic").is_empty(),"classic recipe preserved")
	research._refresh()
	var choices: Array=research.body.find_children("Legendary_*", "Button", true, false)
	check(choices.size()==1 and choices[0].name=="Legendary_character_milo","research shows only earned reward")
	research.queue_free()
	# Exercise the longest production titles with every story reward visible.
	for recipe: Dictionary in preload("res://scripts/research_data.gd").config().legendary_recipes:
		WorkbenchSession.state.research.acquired[recipe.id]="test"
	check(MenuCatalog.unlock_recipe("childhood_keepsake"),"isolated keepsake unlocked for cover preview")
	var journal=load("res://scenes/codex.tscn").instantiate()
	add_child(journal)
	journal._replace_page(1)
	await get_tree().process_frame
	for card: Button in journal.page_content.find_children("CardSlot*", "Button", true, false):
		var title:=card.get_node_or_null("RecipeTitle") as Label
		if title==null: continue
		var english:=card.get_node("RecipeEnglish") as Label
		var category:=card.find_child("RecipeCategory",true,false) as Label
		check(title.get_line_count()<=2,"complete title fits two lines: "+title.text)
		check(title.get_visible_line_count()==title.get_line_count(),"all title lines are visible: "+title.text)
		check(english.get_line_count()<=3,"English title fits three lines: "+english.text)
		check(english.get_visible_line_count()==english.get_line_count(),"all English lines are visible: "+english.text)
		check(title.get_rect().end.x<=277 and title.get_rect().end.y<=english.position.y,"title stays inside card and clears subtitle")
		check(english.get_rect().end.y<=168,"subtitle clears flavor tags")
		check(category.get_theme_font("font").get_string_size(category.text,HORIZONTAL_ALIGNMENT_LEFT,-1,category.get_theme_font_size("font_size")).x<=category.size.x,"category fits stamp")
		if title.text=="童年拾忆":
			var picture:=card.get_node("DrinkPicture") as TextureRect
			check(picture.texture!=null and picture.texture.resource_path.ends_with("childhood_keepsake_pixel.png"),"keepsake card uses authored pixel cover")
			check(picture.texture_filter==CanvasItem.TEXTURE_FILTER_NEAREST,"pixel cover stays crisp")
			for child in card.get_children():
				check(child.get_script()!=preload("res://scripts/workbench_drink_preview.gd"),"procedural drink cannot cover authored art")
	if "--screenshots" in OS.get_cmdline_user_args():
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("/tmp/codex-layout-earned.png")
	journal.show_detail("childhood_keepsake")
	await get_tree().process_frame
	var detail_cover:=journal.find_child("CodexCover",true,false) as TextureRect
	check(detail_cover!=null and detail_cover.texture.resource_path.ends_with("childhood_keepsake_pixel.png"),"keepsake detail uses same cover")
	if "--screenshots" in OS.get_cmdline_user_args():
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("/tmp/keepsake-pixel-detail.png")
	journal.queue_free()
	WorkbenchSession.state.research=original
	codex.free()
	print("CODEX SECRETS failures: ",failures)
	get_tree().quit(0 if failures==0 else 1)
