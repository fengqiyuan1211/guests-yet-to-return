extends Node
## Durable intent in the stock/workbench ledger, idempotent wallet credit, then receipt.
signal changed
const Data=preload("res://scripts/guest_service_data.gd")
const Judge=preload("res://scripts/guest_evaluation.gd")
var last_error:=""

func _ready() -> void:
	call_deferred("recover_pending")

func ledger() -> Dictionary:
	return WorkbenchSession.state.get("service",Data.fresh()).duplicate(true)

func _error(message: String) -> bool:
	last_error=message
	return false

func serving_now() -> bool:
	return is_instance_valid(GameSession.home) and GameSession.home.service_started and (TimeManager.is_open or GameSession.home.closing_pending)

func current_visit() -> String:
	return GameSession.home.reception_id if is_instance_valid(GameSession.home) else ""

func visit_receipt(visit_id: String) -> Dictionary:
	for tx: Dictionary in ledger().deliveries.values():
		if tx.order.visit_id==visit_id and tx.phase=="complete": return tx.receipt.duplicate(true)
	return {}

func ensure_demand(guest: Dictionary) -> Dictionary:
	var visit_id:=str(guest.get("visit_id",""))
	if visit_id.is_empty() or visit_id!=current_visit() or guest.get("id")!=StoryDialogue.guest_id or not serving_now():
		_error("当前接待已结束，请重新选择客人。")
		return {}
	var book:=ledger()
	if book.demands.has(visit_id): return book.demands[visit_id].duplicate(true)
	var target:=Judge.demand(str(guest.id),StoryDialogue.taste_event_id)
	if not Data.valid_demand(target):
		_error("客人的口味资料不完整。")
		return {}
	book.demands[visit_id]=target
	var next:=WorkbenchSession.snapshot()
	next.service=book
	if not WorkbenchSession._commit(next):
		_error(WorkbenchSession.last_error)
		return {}
	return target

func make_order(guest: Dictionary, recipe_id: String) -> Dictionary:
	if not GameSession.save_game():
		_error(GameSession.last_error)
		return {}
	var demand:=ensure_demand(guest)
	if demand.is_empty(): return {}
	for tx: Dictionary in ledger().deliveries.values():
		if tx.order.visit_id==guest.visit_id:
			_error("这次接待已经交付过，请先查看评价并迎接下一位客人。")
			return {}
	for entry in MenuCatalog.entries:
		if entry.id==recipe_id:
			return {"id":"order-"+guest.visit_id+"-"+recipe_id,"visit_id":guest.visit_id,"guest_id":guest.id,"recipe_id":recipe_id,"price":roundi(entry.price),"demand":demand}
	_error("这款酒已下架，请重新选择。")
	return {}

func find_cup(drink_id: String) -> Dictionary:
	var cups: Array=WorkbenchSession.state.get("history",[]).duplicate()
	cups.append(WorkbenchSession.state.get("session",{}))
	for cup: Dictionary in cups:
		if cup.get("result",{}).get("drink_id")==drink_id: return cup.duplicate(true)
	return {}

func deliver(drink_id: String) -> bool:
	last_error=""
	if not WorkbenchSession.writable or not SlotWallet.writable: return _error("存档不可写，请保留当前杯并重试。")
	var book:=ledger()
	if book.deliveries.has(drink_id): return _settle(drink_id)
	var cup:=find_cup(drink_id)
	if cup.is_empty() or cup.get("status")!="finished" or WorkbenchSession.is_research(cup): return _error("请先完成营业酒品。")
	if not cup.has("order"):
		var ok: bool=CustomerService.deliver(cup.result)
		last_error=CustomerService.last_error
		return ok
	var order: Dictionary=cup.get("order",{})
	if not Data.valid_order(order): return _error("这杯没有营业订单，请从客人选酒页重新开工。")
	if order.recipe_id!=cup.recipe.id or order.guest_id!=cup.guest.get("id") or order.visit_id!=cup.guest.get("visit_id"): return _error("这杯与原订单的关联不一致，请保留记录。")
	if order.visit_id!=current_visit() or order.guest_id!=StoryDialogue.guest_id or not serving_now():
		return _error("原客人已经离店，这杯不能再交给新客人。")
	for tx: Dictionary in book.deliveries.values():
		if tx.order.visit_id==order.visit_id: return _error("这位客人本次已交付，不能重复结算。")
	var definitions:=WorkbenchSession.MATERIALS.duplicate(true)
	definitions.merge(WorkbenchSession.SOLIDS)
	definitions.merge(WorkbenchSession.GARNISHES)
	var evaluation:=Judge.evaluate(cup,order.demand,definitions)
	if not evaluation.ok: return _error(evaluation.message)
	var base:=int(order.price) if evaluation.status=="accepted" else 0
	var tip:=0
	if evaluation.status=="accepted":
		for tier in order.demand.tip_tiers:
			if evaluation.score>=tier.min:
				tip=roundi(base*float(tier.rate))
				break
	var receipt:={"id":"sale-"+drink_id,"delivered":true,"paid":true,"status":evaluation.status,"score":evaluation.score,"satisfaction":evaluation.satisfaction,"base_paid":base,"tip":tip,"total_paid":base+tip,"evaluation":evaluation,"reaction":evaluation.reaction,"order_id":order.id,"visit_id":order.visit_id,"model_version":order.demand.version}
	book.deliveries[drink_id]={"drink_id":drink_id,"order":order,"receipt":receipt,"phase":"pending","play_mode":PlayModes.mode}
	var next:=WorkbenchSession.snapshot()
	next.service=book
	if not WorkbenchSession._commit(next): return _error(WorkbenchSession.last_error)
	return _settle(drink_id)

func _settle(drink_id: String) -> bool:
	var tx: Dictionary=ledger().deliveries.get(drink_id,{})
	if tx.is_empty(): return _error("交付记录不存在。")
	if tx.phase=="complete": return true
	if not SlotWallet.receive_sale(tx.receipt.id,int(tx.receipt.total_paid)): return _error(SlotWallet.last_error)
	# Both the cup receipt and completed marker are persisted in one stock-ledger write.
	if not WorkbenchSession.record_guest_settlement(drink_id,tx.receipt): return _error(WorkbenchSession.last_error)
	changed.emit()
	return true

func recover_pending() -> bool:
	if not WorkbenchSession.writable: return false
	for id in ledger().deliveries:
		if ledger().deliveries[id].phase=="pending" and not _settle(id): return false
	return true
