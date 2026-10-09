extends RefCounted
const Journal=preload("res://scripts/guest_journal_data.gd")
const ATTRS=["alcohol_intensity","sweetness","sourness","bitterness"]
static func number(v: Variant, low: float, high: float) -> bool:
	return (v is int or v is float) and is_finite(float(v)) and v>=low and v<=high
static func valid_demand(value: Variant) -> bool:
	if not value is Dictionary or not value.get("version") is String: return false
	for field in ["targets","weights","tolerance"]:
		if not value.get(field) is Dictionary: return false
		for attr in ATTRS:
			if not number(value[field].get(attr),0,100): return false
	if not number(value.get("penalty_scale"),0,10) or not number(value.get("satisfied_min"),0,100): return false
	var sum:=0.0
	for attr in ATTRS: sum+=float(value.weights[attr])
	if sum<=0 or not value.get("restrictions") is Array or not value.get("tip_tiers") is Array: return false
	for item in value.restrictions:
		if item not in ["alcohol","dairy","mint","extra_syrup","pulp"]: return false
	for tier in value.tip_tiers:
		if not tier is Dictionary or not number(tier.get("min"),0,100) or not number(tier.get("rate"),0,1): return false
	return true
static func valid_order(value: Variant) -> bool:
	if not value is Dictionary: return false
	for field in ["id","visit_id","guest_id","recipe_id"]:
		if not value.get(field) is String or value[field].is_empty(): return false
	return number(value.get("price"),1,9999) and value.price==floor(value.price) and valid_demand(value.get("demand"))
static func fresh() -> Dictionary:
	return {"version":1,"demands":{},"deliveries":{}}
static func valid(value: Variant) -> bool:
	if not value is Dictionary or value.get("version")!=1: return false
	if not value.get("demands") is Dictionary or not value.get("deliveries") is Dictionary: return false
	for id in value.demands:
		if not id is String or not valid_demand(value.demands[id]): return false
	var visits: Dictionary={}
	for id in value.deliveries:
		var tx: Variant=value.deliveries[id]
		if not id is String or not tx is Dictionary or tx.get("drink_id")!=id or tx.get("phase") not in ["pending","complete"]: return false
		if not valid_order(tx.get("order")) or not Journal.valid_receipt(tx.get("receipt")): return false
		if tx.receipt.id!="sale-"+id or visits.has(tx.order.visit_id): return false
		visits[tx.order.visit_id]=true
	return true
