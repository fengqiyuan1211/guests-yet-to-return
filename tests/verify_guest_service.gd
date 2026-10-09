extends "res://tests/verify_research.gd"
const Judge=preload("res://scripts/guest_evaluation.gd")

func _ready() -> void:
	if OS.get_cmdline_user_args().has("--service-resume"):
		if not Supplies.save_path.begins_with("/tmp/"): get_tree().quit(2); return
		call_deferred("resume_service")
	else: super._ready()

func run() -> void:
	WorkbenchSession.reset_game()
	MenuCatalog.unlock_recipe("gin_and_tonic")
	check(MenuCatalog.save_menu([{"id":"gin_and_tonic","price":50}],MenuCatalog.design),"business menu fixture")
	home=load("res://scenes/home.tscn").instantiate()
	add_child(home)
	TimeManager.advance_minutes(1200-TimeManager.minutes_since_midnight)
	await settle()
	var guest:={"id":StoryDialogue.guest_id,"visit_id":home.reception_id,"visit":home.guest_count,"day":TimeManager.day}
	var order:=GuestService.make_order(guest,"gin_and_tonic")
	check(not order.is_empty(),"locks demand and menu price")
	var demand: Dictionary=order.demand.duplicate(true)
	MenuCatalog.save_menu([{"id":"gin_and_tonic","price":80}],MenuCatalog.design)
	check(order.price==50 and GuestService.ensure_demand(guest)==demand,"locked order price and demand remain unchanged")
	op("select_recipe",{"recipe_id":"gin_and_tonic","guest":guest,"order":order})
	op("withdraw",{"material":"gin","ml":30,"vessel":"glass"})
	op("withdraw",{"material":"soda","ml":100,"vessel":"glass"})
	op("finish")
	var cup: Dictionary=WorkbenchSession.state.session.duplicate(true)
	var definitions:=WorkbenchSession.MATERIALS.duplicate(true)
	definitions.merge(WorkbenchSession.SOLIDS)
	definitions.merge(WorkbenchSession.GARNISHES)
	var custom:=Judge.demand("milo","")
	custom.targets=Research.attributes(cup,definitions).attributes
	var perfect:=Judge.evaluate(cup,custom,definitions)
	check(perfect.ok and perfect.score==100,"matching actual attributes gives full satisfaction regardless of recipe quality")
	var renamed:=cup.duplicate(true)
	renamed.recipe={"id":"unrelated","version":4,"ingredients":{},"sweetness":99}
	check(Judge.evaluate(renamed,custom,definitions).attributes==perfect.attributes,"actual sensory is independent of selected recipe")
	var rejected:=Judge.evaluate(cup,Judge.demand("yellow_creature",""),definitions)
	check(rejected.ok and rejected.status=="rejected" and rejected.score==null,"hard alcohol restriction is rejected without numeric score")
	var id: String=cup.result.drink_id
	var balance: int=SlotWallet.balance
	var stock: Dictionary=Supplies.inventory.serialize()
	var real_visit: String=home.reception_id
	home.reception_id="different-guest-visit"
	check(not GuestService.deliver(id) and SlotWallet.balance==balance,"old order cannot be handed to a different reception")
	home.reception_id=real_visit
	check(GuestService.deliver(id),"real delivery completes")
	var receipt: Dictionary=WorkbenchSession.state.session.result.customer_receipt
	check(SlotWallet.balance==balance+int(receipt.total_paid),"wallet receives exactly recorded total")
	check(Supplies.inventory.serialize()==stock,"delivery does not debit ingredients again")
	check(GuestService.deliver(id) and SlotWallet.balance==balance+int(receipt.total_paid),"duplicate click cannot pay twice")
	check(GuestService.make_order(guest,"gin_and_tonic").is_empty(),"one visit cannot be settled twice")
	Navigation.go_to(&"mixing")
	await settle()
	bench=home.active_page
	bench._delivery_result()
	await settle()
	check(button_named("返回酒馆")!=null,"customer result has return action")
	await capture("service-01-result")
	Navigation.journal_focus_guest=guest.id
	Navigation.go_to(&"journal")
	await settle()
	bench=home.active_page
	bench.tab=2
	bench._refresh()
	await settle()
	await capture("service-02-journal")
	Navigation.go_to(&"home")
	home.on_drink_served()
	await settle()
	home.get_node("%GuestLayer").show_guest(4)
	await settle()
	var reject_guest:={"id":StoryDialogue.guest_id,"visit_id":home.reception_id,"visit":home.guest_count,"day":TimeManager.day}
	var reject_order:=GuestService.make_order(reject_guest,"gin_and_tonic")
	op("select_recipe",{"recipe_id":"gin_and_tonic","guest":reject_guest,"order":reject_order})
	op("withdraw",{"material":"gin","ml":10,"vessel":"glass"})
	op("finish")
	var rejected_balance: int=SlotWallet.balance
	check(GuestService.deliver(WorkbenchSession.state.session.result.drink_id),"real hard-restriction rejection completes without payment")
	check(WorkbenchSession.state.session.result.customer_receipt.status=="rejected" and SlotWallet.balance==rejected_balance,"rejected drink has explicit status and zero revenue")
	home.on_drink_served()
	await settle()
	var guest2:={"id":StoryDialogue.guest_id,"visit_id":home.reception_id,"visit":home.guest_count,"day":TimeManager.day}
	check(guest2.visit_id!=guest.visit_id,"new reception has distinct durable identity")
	var order2:=GuestService.make_order(guest2,"gin_and_tonic")
	op("select_recipe",{"recipe_id":"gin_and_tonic","guest":guest2,"order":order2})
	op("withdraw",{"material":"soda","ml":80,"vessel":"glass"})
	op("finish")
	var second: String=WorkbenchSession.state.session.result.drink_id
	var wallet_path: String=SlotWallet.save_path
	SlotWallet.save_path=wallet_path+"/blocked.json"
	balance=SlotWallet.balance
	check(not GuestService.deliver(second) and SlotWallet.balance==balance,"failed wallet write rolls back cash and leaves durable intent")
	SlotWallet.save_path=wallet_path
	var supplies_path: String=Supplies.save_path
	Supplies.save_path=supplies_path+"/blocked.json"
	check(not GuestService.deliver(second),"receipt failure after payment remains recoverable")
	Supplies.save_path=supplies_path
	check(GuestService.ledger().deliveries[second].phase=="pending","pending marker retained until receipt commits")
	var expected:=FileAccess.open(Supplies.save_path+".service-expected",FileAccess.WRITE)
	expected.store_string(JSON.stringify({"balance":SlotWallet.balance,"drink_id":second,"visit_id":guest2.visit_id,"stock":Supplies.inventory.serialize()}))
	expected.close()
	GameSession.save_game()
	print("GUEST SERVICE: %d checks, %d failures" % [count,failures.size()])
	home.queue_free()
	await settle()
	get_tree().quit(0 if failures.is_empty() else 1)

func resume_service() -> void:
	await settle()
	var expected: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(Supplies.save_path+".service-expected"))
	check(GuestService.recover_pending(),"restart recovers incomplete delivery")
	check(SlotWallet.balance==expected.balance,"recovery never duplicates already-paid credit")
	check(GuestService.ledger().deliveries[expected.drink_id].phase=="complete","recovered receipt and completion persist together")
	check(WorkbenchSession.state.session.result.has("customer_receipt"),"recovered customer receipt appears on cup")
	check(same(Supplies.inventory.serialize(),expected.stock),"restart recovery preserves stock")
	check(GuestService.deliver(expected.drink_id) and SlotWallet.balance==expected.balance,"recovered transaction remains idempotent")
	print("GUEST SERVICE RESTORE: %d checks, %d failures" % [count,failures.size()])
	get_tree().quit(0 if failures.is_empty() else 1)
