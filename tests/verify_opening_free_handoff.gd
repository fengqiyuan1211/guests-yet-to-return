extends "res://tests/verify_opening_shop_lesson.gd"

func run() -> void:
	# Stocked and penniless: the lesson must still require all three purchase interactions.
	SlotWallet.balance=10000
	SlotWallet.persist()
	for sku in Supplies.OPENING_PACKS:
		check(Supplies.purchase(sku,5),"seed an already stocked warehouse")
	check(OpeningFlow.begin_story() and OpeningFlow.begin_tutorial() and OpeningFlow.finish_tutorial(true) and OpeningFlow.begin_departure(),"enter ordinary preparation")
	check(OpeningFlow.update_departure({"node":"prepare","lesson":{"phase":"shop","accepted_drink":""}}),"prepare lesson state")
	SlotWallet.balance=0
	SlotWallet.persist()
	var wallet_bytes:=FileAccess.get_file_as_bytes(SlotWallet.save_path)
	check(not Supplies.opening_purchase_report().ready,"full warehouse does not skip teaching purchases")
	var stock: Dictionary=Supplies.inventory.serialize()
	var bench:=WorkbenchSession.state.duplicate(true)
	var path:=Supplies.save_path
	Supplies.save_path+="/no-directory"
	check(not Supplies.purchase_opening("sku_gin_london_dry",1),"failed grant write rejected")
	check(stock==Supplies.inventory.serialize() and bench==WorkbenchSession.state,"failed grant leaves stock and receipt unchanged")
	Supplies.save_path=path
	for sku in Supplies.OPENING_PACKS:
		var before:=Supplies.total_remaining(sku)
		check(Supplies.purchase_opening(sku,Supplies.OPENING_PACKS[sku]),"zero coin teaching grant: "+sku)
		var after:=Supplies.total_remaining(sku)
		check(after>before and SlotWallet.balance==0,"gift actually adds stock without spending")
		check(not Supplies.purchase_opening(sku,Supplies.OPENING_PACKS[sku]),"duplicate grant rejected")
		check(Supplies.total_remaining(sku)==after,"no duplicate materials")
	check(Supplies.opening_purchase_report().ready,"all required purchase interactions completed")
	check(FileAccess.get_file_as_bytes(SlotWallet.save_path)==wallet_bytes,"free purchases never even rewrite wallet")
	check(not Supplies.quote_purchase("sku_gin_london_dry",1).ok,"ordinary shop still charges coins")
	# Build an ordinary save with a half-finished cup to verify replay never replaces it.
	action("select_recipe",{"recipe_id":"gin_and_tonic","opening_practice":true})
	action("withdraw",{"material":"gin","ml":17,"vessel":"jigger"})
	check(GameSession.save_game(),"persist original game")
	var original:=OpeningFlow.state.duplicate(true)
	var original_stock: Dictionary=Supplies.inventory.serialize()
	var original_bench:=WorkbenchSession.state.duplicate(true)
	var original_relations:=Relationships.state.duplicate(true)
	var files: Dictionary={}
	for file_path: String in [OpeningFlow.save_path,GameSession.save_path,Supplies.save_path,SlotWallet.save_path,MenuCatalog.save_path,StoryDialogue.save_path,CustomerService.save_path,Relationships.save_path,PlayModes.path,WorkbenchSession.save_path]:
		files[file_path]=FileAccess.get_file_as_bytes(file_path) if FileAccess.file_exists(file_path) else PackedByteArray()
	check(OpeningFlow.begin_replay() and OpeningFlow.begin_tutorial() and OpeningFlow.finish_tutorial(true) and OpeningFlow.begin_departure(),"replay reaches departure")
	check(OpeningFlow.update_departure({"node":"prepare","signed":true,"water":true}),"replay reaches preparation")
	await show_scene("res://scenes/opening_departure.tscn")
	await settle()
	check(OpeningFlow.replay_world.active,"replay creates independent economy")
	check(GameSession.save_path!=path and SlotWallet.balance==300,"replay has separate initial budget")
	check(WorkbenchSession.state.session.is_empty(),"original half cup is not in demo world")
	var lesson: Control=page.preparation
	var shop: Control=lesson.page
	check(shop.get_script().resource_path=="res://scripts/harbor_shop.gd" and shop.opening_free_lesson,"replay uses production shop with free lesson")
	await talk(shop)
	for sku in Supplies.OPENING_PACKS:
		lesson.guide.refresh()
		if sku=="sku_tonic_water": await pointer_click(shop.find_child("QuantityPlus",true,false))
		await pointer_click(shop.buy_button)
	check(SlotWallet.balance==300,"replay native purchase buttons are free")
	await talk(shop)
	lesson.guide.refresh()
	await capture("free-lesson-01-shop")
	await pointer_click(lesson.guide.proceed)
	await settle()
	check(lesson.page.data.get("opening_practice",false),"replay can start actual workbench lesson")
	for i in range(3): action("ice",{"ice":"cube","vessel":"glass"})
	action("withdraw",{"material":"gin","ml":50,"vessel":"glass"})
	action("withdraw",{"material":"sku_tonic_water","ml":150,"vessel":"glass"})
	action("garnish",{"material":"garnish"})
	lesson.page._finish()
	await settle()
	await pointer_click(button_named(lesson.page,"确认这杯，加入今晚酒单 →"))
	check(OpeningFlow.state.departure.node=="ready","replay publishes lesson drink")
	var limit:=0
	while OpeningFlow.state.departure.node!="turn_sign" and limit<20:
		limit+=1
		page.dialogue.visible_characters=-1
		await pointer_click(page.next_button)
	get_tree().current_scene=null
	page.dialogue.visible_characters=-1
	await pointer_click(page.next_button)
	await get_tree().create_timer(10).timeout
	await settle_opening_transition()
	check(get_tree().current_scene!=null and get_tree().current_scene.scene_file_path=="res://scenes/home.tscn","replay automatically enters real home instead of title")
	page.queue_free()
	page=null
	var home: Control=get_tree().current_scene
	check(OpeningFlow.first_service_pending() and StoryDialogue.guest_id=="milo","first service awaits Milo's real drink")
	await capture("free-lesson-02-milo")
	limit=0
	while StoryDialogue.phase=="story" and limit<90:
		limit+=1
		if StoryDialogue.current_choices().is_empty(): StoryDialogue.continue_talking()
		else: StoryDialogue.choose(StoryDialogue.current_choices()[0].id,StoryDialogue.revision)
	await settle()
	await pointer_click(home.get_node("%OpenButton"))
	await settle()
	var picker: Control=home.active_page
	check(picker.get_script().resource_path=="res://scripts/drink_selection.gd" and picker.selected_id=="gin_and_tonic","normal order picker recommends lesson drink")
	await capture("free-lesson-03-order")
	await pointer_click(picker.start_button)
	await settle()
	var actual_bench: Control=home.active_page
	check(actual_bench.data.guest.id=="milo" and not actual_bench.data.get("opening_practice",false),"new service cup is linked to Milo, not the practice cup")
	check(is_instance_valid(actual_bench.surface.find_child("OpeningTutorialGuide",true,false)),"real first service retains dynamic mixing hints")
	for i in range(3): action("ice",{"ice":"cube","vessel":"glass"})
	action("withdraw",{"material":"gin","ml":50,"vessel":"glass"})
	action("withdraw",{"material":"sku_tonic_water","ml":150,"vessel":"glass"})
	action("spoon",{"target":"glass"})
	for i in range(6): action("stir",{"vessel":"glass","seconds":.5})
	action("spoon",{"target":""})
	action("garnish",{"material":"garnish"})
	await capture("free-lesson-04-serve")
	actual_bench._finish()
	await settle()
	# Use the normal result button, not a synthesized guest-service order.
	check(OpeningFlow.first_service_pending() and not CustomerService.has_delivery(),"finish alone does not submit the teaching cup")
	var deliver: Button=button_named(actual_bench,"交给米洛 · 空格")
	check(is_instance_valid(deliver),"real cup presents delivery action")
	await pointer_click(deliver)
	await settle()
	check(not OpeningFlow.first_service_pending(),"real settled delivery completes first service teaching")
	check(CustomerService.has_delivery(),"Milo's drink is in production customer ledger")
	check(get_tree().current_scene==home,"delivery remains in game")
	await capture("free-lesson-05-feedback")
	OpeningFlow.return_to_title()
	await settle_opening_transition()
	check(not OpeningFlow.replaying and not OpeningFlow.replay_world.active,"explicit exit ends replay world")
	check(OpeningFlow.state==original and Supplies.inventory.serialize()==original_stock,"original opening and warehouse restored")
	check(WorkbenchSession.state==original_bench and SlotWallet.balance==0,"original half cup and balance restored")
	check(Relationships.state==original_relations,"original relationships restored")
	for file_path: String in files:
		var data:=FileAccess.get_file_as_bytes(file_path) if FileAccess.file_exists(file_path) else PackedByteArray()
		check(data==files[file_path],"original file unchanged: "+file_path.get_file())
	print("FREE PROCUREMENT AND MILO: ",count," checks, ",failures.size()," failures")
	get_tree().quit(0 if failures.is_empty() else 1)
