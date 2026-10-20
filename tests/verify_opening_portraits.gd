extends "res://tests/verify_opening.gd"
const Portrait = preload("res://scripts/opening_portrait.gd")

func shot(label: String) -> void:
	if DisplayServer.get_name()=="headless": return
	await get_tree().create_timer(.7).timeout
	RenderingServer.force_draw()
	DirAccess.make_dir_recursive_absolute("/tmp/opening-portraits")
	get_viewport().get_texture().get_image().save_png("/tmp/opening-portraits/"+label+".png")

func run() -> void:
	if not GameSession.save_path.begins_with("/tmp/"): get_tree().quit(2); return
	TimeManager.set_running(false)
	var stock: Dictionary = Supplies.inventory.serialize().duplicate(true)
	var wallet := SlotWallet.balance
	check(OpeningFlow.begin_story(),"isolated story begins")
	var cases := {
		"s01_young_01":"colleague_a", "s01_young_03":"colleague_b",
		"s01_young_05":"junior_colleague", "s02_02":"old_friend",
		"s02_10":"city_bartender", "s06_00":"caretaker",
		"s01_depart_03":"colleague_b", "s01_depart_04":"colleague_a",
		"s03_night_05":"", "s01_04":"", "s02_01":"", "s02_taste_01":""
	}
	await show_scene("res://scenes/opening_story.tscn")
	page.set_process(false)
	for id in cases:
		check(OpeningFlow.advance(OpeningFlow.node_index(id)),"jump to "+id)
		page._render()
		page.dialogue.visible_characters=page.dialogue.text.length()
		var actor: Control=page.character_art
		check(actor.actor_id==cases[id],"correct speaker identity "+id)
		check(actor.visible==not str(cases[id]).is_empty(),"visibility derived from current line "+id)
		check(actor.mouse_filter==Control.MOUSE_FILTER_IGNORE and actor.portrait.mouse_filter==Control.MOUSE_FILTER_IGNORE,"portrait does not intercept input")
		if actor.visible:
			check(actor.portrait.texture!=null,"texture imported "+id)
			var r: Rect2=actor.portrait.get_rect()
			check(r.position.y==Portrait.HEAD_TOP and r.end.y>=650 and r.position.x>=0 and r.end.x<=1600,"head aligned and body continues behind dialogue "+id)
			var head_px: float=r.size.y/actor.portrait.texture.get_size().y*float(Portrait.HEAD_HEIGHTS[actor.actor_id])
			check(absf(head_px-Portrait.DISPLAY_HEAD_HEIGHT)<1.0,"consistent portrait camera distance "+id)
		if id in ["s01_young_01","s01_young_03","s01_young_05","s02_02","s02_10","s06_00"]: await shot(id)
	OpeningFlow.advance(OpeningFlow.node_index("s02_02"));page._render()
	page.dialogue.visible_characters=page.dialogue.text.length()
	await pointer_click(page.next_button)
	check(page.character_art.actor_id=="" and not page.character_art.visible,"pointer advance to player clears previous speaker")
	await key_press(KEY_SPACE)
	if page.dialogue.visible_characters<page.dialogue.text.length(): await key_press(KEY_SPACE)
	# Explicitly target a voiced line before checking history and reload.
	OpeningFlow.advance(OpeningFlow.node_index("s06_00"));page._render()
	page._open_history();await settle()
	check(is_instance_valid(page.history_panel),"history remains operable above portrait")
	await key_press(KEY_SPACE)
	check(OpeningFlow.state.node_id=="s06_00","history blocks scene advance")
	page._close_history()
	await show_scene("res://scenes/opening_story.tscn")
	page.set_process(false)
	check(page.character_art.actor_id=="caretaker","scene recreation restores speaker from saved node")
	page.fast_forward.press();page.fast_forward.step(.4,true)
	OpeningFlow.advance(OpeningFlow.node_index("s02_10"));page._render()
	check(page.character_art.actor_id=="city_bartender" and page.character_art.portrait.modulate.a==1.0,"fast-forward switches portrait immediately")
	page.fast_forward.cancel()
	page._toggle_auto()
	check(page.autoplay.enabled,"autoplay toggle remains available")
	page._toggle_auto()
	check(OpeningFlow.begin_tutorial(),"isolated tutorial can begin")
	check(OpeningFlow.finish_tutorial(true),"isolated tutorial can finish")
	await show_scene("res://scenes/opening_departure.tscn")
	page.set_process(false)
	for id in ["knock","recipient","give_water","ledger","turn_sign","sign_receipt"]:
		OpeningFlow.update_departure({"node":id});page._render()
		page.dialogue.visible_characters=page.dialogue.text.length()
		var expected := "courier" if id in ["recipient","give_water"] else ("caretaker" if id in ["ledger","turn_sign"] else "")
		check(page.character_art.actor_id==expected,"departure portrait "+id)
		if page.character_art.visible:
			check(page.character_art.portrait.get_rect().end.x<=530,"portrait reserves central prop area")
		if id in ["recipient","give_water","ledger"]: await shot(id)
	OpeningFlow.update_departure({"node":"sign_receipt"});page._render();page.dialogue.visible_characters=page.dialogue.text.length()
	page.name_edit.text="归舟"
	await pointer_click(page.hint_target)
	check(OpeningFlow.state.departure.signed,"signing still works with portrait layer")
	check(Supplies.inventory.serialize()==stock and SlotWallet.balance==wallet,"presentation and isolated tutorial do not alter economy")
	check(Portrait.actor_for({"speaker":"老板娘"})=="","merchant keeps existing separate approved portrait")
	page._start_conversation("merchant_intro",func(): pass)
	await settle()
	var merchant: TextureRect=page.find_child("MerchantPortrait",true,false)
	check(merchant!=null and merchant.size==Vector2(560,725),"merchant stays at intended half-body size after source texture assignment")
	check(merchant.get_parent().clip_contents and merchant.get_parent().size.y==535,"merchant body clipped at dialogue boundary")
	await shot("merchant_intro")
	await pointer_click(page.conversation.next_button)
	check(page.conversation.index==1,"merchant conversation still advances by click")
	page.queue_free();await settle();page=null
	await show_scene("res://scenes/harbor_shop.tscn")
	check(page.merchant_portrait.size==Vector2(644,510),"normal shop portrait keeps designed size after texture import")
	await shot("merchant_shop")
	page.queue_free();await settle();page=null
	print("OPENING PORTRAITS: %d checks, %d failures" % [count,failures.size()])
	get_tree().quit(0 if failures.is_empty() else 1)
