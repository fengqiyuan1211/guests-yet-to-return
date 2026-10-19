extends RefCounted
const Sensory=preload("res://scripts/research_data.gd")
const Quality=preload("res://scripts/workbench_evaluation.gd")
const Catalog=preload("res://scripts/supply_catalog.gd")

static func config() -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string("res://data/guest_service.json"))

static func demand(guest_id: String, episode: String) -> Dictionary:
	var cfg:=config()
	if not cfg.profiles.has(guest_id): return {}
	var result: Dictionary=cfg.profiles[guest_id].duplicate(true)
	result.version=cfg.version
	result.status=cfg.status
	result.penalty_scale=cfg.penalty_scale
	result.satisfied_min=cfg.satisfied_min
	result.tip_tiers=cfg.tip_tiers.duplicate(true)
	result.recipe_buffs=cfg.recipe_buffs.duplicate(true)
	var event: Dictionary=cfg.events.get(episode,{})
	if event.get("guest_id",guest_id)!=guest_id: event={}
	result.event_id=episode if not event.is_empty() else ""
	if not event.is_empty(): result.request_text=event.get("request_text",result.get("request_text",""))
	for attr in event.get("delta",{}):
		result.targets[attr]=clampf(float(result.targets[attr])+float(event.delta[attr]),0,100)
	return result

static func evaluate(cup: Dictionary, target: Dictionary, definitions: Dictionary) -> Dictionary:
	var sensory:=Sensory.attributes(cup,definitions)
	if not sensory.missing.is_empty() or Quality.total(cup.vessels.glass.contents)<=0:
		return {"ok":false,"message":"成品为空或原料感官数据不完整，无法交付。"}
	var actual:=Quality.canonical(cup.vessels.glass.contents,definitions)
	var solids:=Quality.canonical(cup.vessels.glass.get("solids",{}),definitions)
	var included:=actual.duplicate(true)
	included.merge(solids)
	for id in Quality.decoration_ids(cup.vessels.glass): included[Quality.sku(id,definitions)]=1
	var violations: Array=[]
	var catalog:=Catalog.new()
	for restriction in target.restrictions:
		if restriction=="alcohol":
			var unknown:=false
			var found:=false
			for sku in included:
				var alcohol: Variant=catalog.get_item(sku).get("contains_alcohol")
				if alcohol==true: found=true
				elif alcohol==null: unknown=true
			if found: violations.append("这次要求无酒精，但杯中含有酒精原料。")
			elif unknown: return {"ok":false,"message":"部分原料的含酒信息不明确，无法确认符合无酒精要求。"}
		elif restriction=="mint" and (included.has("sku_mint_leaf") or included.has("sku_mint_sprig")):
			violations.append("这次不接受薄荷。")
		elif restriction=="pulp" and (solids.has("sku_mint_leaf") or included.has("sku_lime_wedge") or included.has("sku_lemon_slice")):
			violations.append("这次希望没有果肉或固体配料。")
		elif restriction=="dairy":
			for sku in included:
				if catalog.get_item(sku).get("dietary_tags",[]).has("dairy"): violations.append("这次不接受奶制品。")
		elif restriction=="extra_syrup":
			var expected:=Quality.canonical(cup.recipe.ingredients,definitions)
			if float(actual.get("sku_simple_syrup",0))>float(expected.get("sku_simple_syrup",0))+.001:
				violations.append("这次不接受配方之外额外加入的糖浆。")
	if not violations.is_empty():
		return {"ok":true,"status":"rejected","score":null,"satisfaction":"拒收","attributes":sensory.attributes,"reasons":violations,"reaction":"这一杯我不能喝。"+str(violations[0]),"base_score":null,"bonus":0.0,"soft_penalty":0.0}
	var error:=0.0
	var weights:=0.0
	var largest:=0.0
	var direction:=""
	for attr in Sensory.ATTRS:
		var delta:=float(sensory.attributes[attr])-float(target.targets[attr])
		var offset:=maxf(0,absf(delta)-float(target.tolerance[attr]))
		error+=offset*float(target.weights[attr])
		weights+=float(target.weights[attr])
		if offset>largest:
			largest=offset
			direction={"alcohol_intensity":"酒感", "sweetness":"甜味", "sourness":"酸味", "bitterness":"苦味"}[attr]+("偏重" if delta>0 else "偏轻")
	var base:=clampf(100-float(target.penalty_scale)*error/maxf(weights,.001),0,100)
	var soft:=0.0
	if target.get("no_bubbles",false):
		var trace:=Quality.replay(cup.get("actions",[]),{},definitions)
		if float(trace.carbonated)-float(trace.flat)>.001: soft=10.0
	var bonus:=0.0
	var quality: Dictionary=cup.result.get("evaluation",{})
	var buff: Dictionary=target.get("recipe_buffs",{}).get(cup.recipe.id,{})
	if not buff.is_empty() and quality.get("tier")=="perfect" and buff.get("version")==cup.recipe.version:
		bonus=clampf(float(buff.get("bonus",0)),0,10)
	var score:=clampf(base+bonus-soft,0,100)
	var satisfied:=score>=float(target.satisfied_min)
	var label:="非常满意" if score>=90 else ("满意" if satisfied else ("不太满意" if score>=40 else "不满意"))
	var reasons: Array=[]
	if not direction.is_empty(): reasons.append("对这次的口味来说，"+direction+"。")
	if soft>0: reasons.append("这次更想喝没有气泡的酒。")
	if reasons.is_empty(): reasons.append("这杯的口味落在这次想喝的范围内。")
	return {"ok":true,"status":"accepted","score":score,"satisfaction":label,"attributes":sensory.attributes,"reasons":reasons,"base_score":base,"bonus":bonus,"soft_penalty":soft,"reaction":("这杯很合我的口味，谢谢。" if satisfied else "谢谢，不过这次的口味和我想要的有些不同。")+str(reasons[0])}
