extends RefCounted
## Pure, deterministic evaluator. Never writes inventory, recipes, or customer settlement.
const LiquidState=preload("res://scripts/workbench_liquid_state.gd")
const Research=preload("res://scripts/research_data.gd")
const Sensory=preload("res://scripts/sensory_model.gd")
const CONFIG_PATH := "res://data/workbench/evaluation.json"
const ATTRS := ["alcohol_intensity","sweetness","sourness","bitterness"]
const CARBONATED := ["sku_soda_water","sku_tonic_water","sku_cola"]

static func config() -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string(CONFIG_PATH))

static func sku(id: String, definitions: Dictionary) -> String:
	return str(definitions.get(id,{}).get("sku_id",id))

static func canonical(contents: Dictionary, definitions: Dictionary) -> Dictionary:
	var result: Dictionary={}
	for id in contents:
		var key:=sku(id,definitions)
		result[key]=float(result.get(key,0))+float(contents[id])
	return result

static func total(contents: Dictionary) -> float:
	var result:=0.0
	for value in contents.values(): result+=float(value)
	return result

static func average(contents: Dictionary, profiles: Dictionary) -> Array:
	var result: Array=[0.0,0.0,0.0,0.0]
	var amount:=maxf(total(contents),.001)
	for id in contents:
		var profile: Array=profiles.get(id,[0,0,0,0])
		for i in range(4): result[i]+=float(profile[i])*float(contents[id])/amount
	return result

static func ice_types(v: Dictionary) -> Array:
	var types: Array=[]
	for batch in v.get("ice_batches",[]): types.append(batch.kind)
	if types.is_empty() and v.get("ice","none")!="none": types.append(v.ice)
	return types

static func decoration_ids(v: Dictionary) -> Array:
	if v.has("garnishes"): return v.garnishes
	return [v.get("garnish_id","garnish")] if v.get("garnish",false) else []

static func replay(actions: Array, rule: Dictionary, definitions: Dictionary, vessel_id: String="glass") -> Dictionary:
	var vessels: Dictionary={}
	for id in ["jigger","mixing","shaker","glass"]:
		vessels[id]={"lots":[],"liquid":{"contents":{},"layers":[]},"solids":{},"ice":false,"herb":false}
	var lot_serial:=0
	var lot_groups: Dictionary={}
	for action in actions:
		var p: Dictionary=action.payload
		var id:=str(p.get("vessel","jigger" if action.kind=="withdraw" else "glass"))
		if not vessels.has(id): continue
		var v: Dictionary=vessels[id]
		match action.kind:
			"withdraw":
				lot_serial+=1
				var lot_key:=str(lot_serial)
				lot_groups[lot_key]=sku(str(p.material),definitions)
				v.lots.append({"key":lot_key,"sku":sku(str(p.material),definitions),"ml":float(action.get("actual_ml",p.ml)),"seconds":0.0,"controlled":0.0,"mixed":false,"iced":false,"filtered":false,"herb":v.herb,"flat":false})
				LiquidState.add(v.liquid,{lot_key:float(action.get("actual_ml",p.ml))},lot_groups)
				if not action.get("liquid_layered",false): v.liquid.layers=[{"contents":v.liquid.contents.duplicate(true)}]
			"add_solid":
				var material:=sku(str(p.material),definitions)
				v.solids[material]=float(v.solids.get(material,0))+1
			"ice": v.ice=true
			"muddle":
				if v.solids.has(str(rule.get("muddle","sku_mint_leaf"))):
					v.herb=true
					for lot in v.lots: lot.herb=true
			"shake", "stir":
				if float(p.get("seconds",0))<=0: continue
				if action.has("liquid_model"): LiquidState.mix(v.liquid,float(p.seconds),action.kind,float(p.get("control",1)),action.liquid_model,lot_groups)
				for lot in v.lots:
					if action.kind==rule.get("mix",""):
						lot.seconds+=float(p.seconds)
						lot.controlled+=float(p.seconds)*float(p.get("control",1))
						lot.mixed=true
						lot.iced=v.ice
						lot.filtered=false
					if action.kind=="shake" and lot.sku in CARBONATED: lot.flat=true
			"transfer", "filter":
				var source: Dictionary=vessels.get(str(p.get("source","")),{})
				if source.is_empty(): continue
				var pour: Dictionary=action.get("pour",{})
				var fraction:=float(pour.get("fraction",1.0))
				var retained: Array=[]
				var moved_lots: Dictionary={}
				var stream: Array=[]
				var remap: Dictionary={}
				if pour.has("layers"):
					stream=LiquidState.take(source.liquid,float(pour.ml))
					moved_lots=LiquidState.aggregate(stream)
				else:
					# Legacy transfers mixed every ingredient proportionally.
					for key in source.liquid.contents.keys():
						moved_lots[key]=float(source.liquid.contents[key])*fraction
						source.liquid.contents[key]*=1-fraction
						if source.liquid.contents[key]<=0: source.liquid.contents.erase(key)
					source.liquid.layers=[{"contents":source.liquid.contents.duplicate(true)}] if not source.liquid.contents.is_empty() else []
					stream=[{"contents":moved_lots}]
				for lot in source.lots:
					var share:=clampf(float(moved_lots.get(lot.key,0))/maxf(.000001,float(lot.ml)),0,1)
					var moved: Dictionary=lot.duplicate(true)
					moved.ml=float(lot.ml)*share
					if action.kind=="filter": moved.filtered=true
					if moved.ml>.000001:
						lot_serial+=1
						moved.key=str(lot_serial)
						remap[lot.key]=moved.key
						lot_groups[moved.key]=lot.sku
						v.herb=v.herb or moved.herb
						v.lots.append(moved)
					lot.ml=float(lot.ml)*(1-share)
					if lot.ml>.000001: retained.append(lot)
				source.lots=retained
				for layer in stream:
					var incoming: Dictionary={}
					for key in layer.contents:
						if remap.has(key): incoming[remap[key]]=layer.contents[key]
					LiquidState.add(v.liquid,incoming,lot_groups)
				if not pour.has("layers"):
					v.liquid.layers=[{"contents":v.liquid.contents.duplicate(true)}] if not v.liquid.contents.is_empty() else []
				if action.kind=="transfer":
					if not pour.is_empty():
						v.ice=v.ice or float(pour.ice_g)>0
						source.ice=pour.source_ice_left
					elif action.get("transfers_ice",false):
						v.ice=v.ice or source.ice
						source.ice=false
					var solids: Dictionary=pour.get("solids",source.solids).duplicate(true)
					for material in solids:
						v.solids[material]=float(v.solids.get(material,0))+float(solids[material])
						source.solids[material]=float(source.solids.get(material,0))-float(solids[material])
						if source.solids[material]<=.000001: source.solids.erase(material)
					if source.solids.is_empty() and source.lots.is_empty(): source.herb=false
			"empty":
				v.lots=[]
				v.liquid={"contents":{},"layers":[]}
				v.solids={}
				v.ice=false
				v.herb=false

	var result: Dictionary={"traced":0.0,"mixed":0.0,"iced":0.0,"filtered":0.0,"herb":0.0,"flat":0.0,"carbonated":0.0,"readiness":0.0,"min_seconds":INF,"max_seconds":0.0}
	for lot in vessels.get(vessel_id,vessels.glass).lots:
		result.min_seconds=minf(result.min_seconds,lot.seconds)
		result.max_seconds=maxf(result.max_seconds,lot.seconds)
		var window: Array=rule.get("time_window",[0,100000])
		var timing:=clampf(lot.seconds/maxf(.001,float(window[0])),0,1)
		if lot.seconds>float(window[1]): timing=maxf(.7,1-(lot.seconds-float(window[1]))*.025)
		result.readiness+=lot.ml*timing*(.85+.15*lot.controlled/maxf(.001,lot.seconds))
		result.traced+=lot.ml
		for key in ["mixed","iced","filtered","herb","flat"]:
			if lot[key]: result[key]+=lot.ml
		if lot.sku in CARBONATED: result.carbonated+=lot.ml
	if not is_finite(result.min_seconds): result.min_seconds=0.0
	return result

static func evaluate(session: Dictionary, definitions: Dictionary) -> Dictionary:
	if session.get("mode")=="research_diy": return Research.trial(session,definitions)
	var model: Dictionary=session.get("quality_model",config())
	var recipe: Dictionary=session.recipe
	var serving: Dictionary=session.vessels.glass
	var actual:=canonical(serving.contents,definitions)
	var expected:=canonical(recipe.ingredients,definitions)
	var actual_volume:=total(actual)
	var expected_volume:=total(expected)
	var rule: Dictionary=recipe.get("quality_rule",model.rules.get(str(recipe.get("id","")),{}))
	var trace:=replay(session.get("actions",[]),rule,definitions)
	var reasons: Array=[]
	var notes: Array=["试玩评分；酒感不等于 ABV。有效混合时长与节奏采用试玩范围；融水与温度未计分。"]
	var uncertain:=rule.is_empty()
	if uncertain: notes.append("此配方的制作规则尚未配置，暂不评操作和出品要求。")
	var unquantified: Array=[]
	for row in recipe.get("ingredient_rows",[]):
		if row.get("inventory_unit")=="ml" and row.get("inventory_amount")==null:
			unquantified.append(str(row.sku_id))
			notes.append(str(row.name)+"的定量换算未定，仅检查有无加入。")
			uncertain=true
	var known_actual:=actual.duplicate(true)
	for id in unquantified: known_actual.erase(id)
	var known_volume:=maxf(.001,total(known_actual))
	var ratio_error:=0.0
	var all_ids: Dictionary=expected.duplicate()
	all_ids.merge(known_actual)
	for id in all_ids:
		ratio_error+=absf(float(expected.get(id,0))/maxf(.001,expected_volume)-float(known_actual.get(id,0))/known_volume)
	var ratio_score:=clampf(100*(1-ratio_error*.5),0,100)
	var volume_score:=100*minf(known_volume/maxf(.001,expected_volume),expected_volume/known_volume)
	var recipe_score:=ratio_score*.75+volume_score*.25
	var expected_solids: Dictionary={}
	for row in recipe.get("ingredient_rows",[]):
		if row.get("sku_id") in ["sku_mint_leaf","sku_white_cane_sugar"] and row.get("inventory_amount")!=null:
			expected_solids[row.sku_id]=float(row.inventory_amount)
	var actual_solids:=canonical(serving.get("solids",{}),definitions)
	for id in expected_solids:
		var wanted:=float(expected_solids[id])
		var found:=float(actual_solids.get(id,0))
		var deviation:=absf(found-wanted)/maxf(1,wanted)
		recipe_score=maxf(0,recipe_score-minf(20,deviation*20))
		if deviation>.1: reasons.append(_name(id,definitions)+"的份数与配方不同。")
	for id in actual_solids:
		if not expected_solids.has(id):
			recipe_score=maxf(0,recipe_score-minf(40,float(actual_solids[id])*2))
			reasons.append("加入了配方外的"+_name(id,definitions)+"，会影响这杯的风味。")
	var max_dose_error:=0.0
	var missing_major:=false
	for id in expected:
		var amount:=float(actual.get(id,0))
		max_dose_error=maxf(max_dose_error,absf(amount-float(expected[id]))/maxf(.1,float(expected[id])))
		if amount<=0:
			reasons.append("缺少"+_name(id,definitions)+"，配方结构发生了变化。")
			if float(expected[id])/maxf(.001,expected_volume)>=.14: missing_major=true
		elif absf(amount-float(expected[id]))>maxf(1,float(expected[id])*.10):
			reasons.append("%s比配方%s %s ml。" % [_name(id,definitions),"多了" if amount>expected[id] else "少了",_amount(absf(amount-float(expected[id])))])
	for id in actual:
		if not expected.has(id) and id not in unquantified: reasons.append("加入了配方外的"+_name(id,definitions)+"，风味随之改变。")
	for id in unquantified:
		if not actual.has(id):
			reasons.append("尚未加入配方中的"+_name(id,definitions)+"。")
			recipe_score=minf(recipe_score,79)
	var blend:=clampf(float(trace.readiness)/maxf(.001,actual_volume),0,1)
	var coverage:=clampf(float(trace.mixed)/maxf(.001,actual_volume),0,1)
	var iced:=clampf(float(trace.iced)/maxf(.001,actual_volume),0,1)
	var filtered:=clampf(float(trace.filtered)/maxf(.001,actual_volume),0,1)
	var process_score:=100.0
	if rule.has("mix"):
		process_score=clampf(float(trace.readiness)/maxf(.001,actual_volume),0,1)*100
		if float(trace.min_seconds)<float(rule.time_window[0]): reasons.append("有效混合不足：最新加入的材料仅处理 %.1f 秒，建议 %s–%s 秒。" % [trace.min_seconds,rule.time_window[0],rule.time_window[1]])
		elif float(trace.max_seconds)>float(rule.time_window[1]): reasons.append("混合时间偏长，达到推荐范围后即可停手。")
		if coverage<.98: reasons.append("部分酒液未完成%s；后加的材料也需要参与混合。" % ("摇和" if rule.mix=="shake" else "搅拌"))
		if rule.get("mix_ice",false):
			process_score=process_score*.75+iced*25
			if iced<.98: reasons.append("有酒液未经过带冰处理，冷却步骤尚未完成。")
	if rule.has("muddle") and float(trace.herb)<actual_volume*.98:
		process_score*=.75
		reasons.append("薄荷未与酒液完成轻压处理，草本释放不足。")
	if float(trace.flat)>0:
		process_score*=.85
		reasons.append("含气材料参与了摇和，按试玩规则记为气泡流失。")
	var finish_checks: Array=[]
	if rule.has("cup"):
		var correct: bool=session.cup==rule.cup or (rule.cup=="highball" and session.cup=="rocks")
		finish_checks.append(1.0 if correct else 0.0)
		if not correct: reasons.append("使用的杯型与这款酒的推荐杯型不同。")
	if rule.get("filter",false):
		finish_checks.append(filtered)
		if filtered<.98: reasons.append("部分酒液没有在混合后完成过滤。")
		finish_checks.append(1.0 if ice_types(serving).is_empty() else 0.0)
		if not ice_types(serving).is_empty(): reasons.append("这款短饮的制作冰应留在源容器，成品中另加了冰。")
	if rule.has("serving_ice"):
		var correct: bool=ice_types(serving).has(rule.serving_ice)
		finish_checks.append(1.0 if correct else 0.0)
		if not correct: reasons.append("缺少配方要求的出品冰型。")
	var decorations: Dictionary={}
	for id in decoration_ids(serving):
		var key:=sku(str(id),definitions)
		decorations[key]=int(decorations.get(key,0))+1
	for id in rule.get("garnishes",{}):
		var correct: bool=int(decorations.get(id,0))>=int(rule.garnishes[id])
		finish_checks.append(1.0 if correct else 0.0)
		if not correct: reasons.append("还缺少装饰："+_name(id,definitions)+"。")
	var finish_score:=100.0
	if not finish_checks.is_empty():
		finish_score=0
		for value in finish_checks: finish_score+=float(value)*100/finish_checks.size()
	var targets: Dictionary={}
	var attributes: Dictionary={}
	var deltas: Dictionary={}
	var sensory_model: Dictionary=session.get("sensory_model",model.get("sensory_model",{}))
	var sensory_result: Dictionary={}
	var standard_result: Dictionary={}
	if Sensory.valid_model(sensory_model):
		sensory_result=Sensory.evaluate(serving.contents,serving.get("solids",{}),definitions,sensory_model)
		standard_result=Sensory.standard(recipe,sensory_model)
		attributes=sensory_result.attributes.duplicate(true)
		targets=standard_result.attributes.duplicate(true)
		for key in ATTRS: deltas[key]=float(attributes[key])-float(targets[key])
		if not sensory_result.data_complete or not standard_result.data_complete:
			uncertain=true
			notes.append("部分材料的感官数据或用量未配置，暂不评为完美。")
	else:
		# Legacy cups keep their frozen calculation until this cup is finished.
		# Unknown-dose ingredients anchor at the actual amount; never invent a dash-to-ml conversion.
		var attribute_reference:=expected.duplicate(true)
		for id in unquantified:
			if actual.has(id): attribute_reference[id]=actual[id]
		var ideal:=average(attribute_reference,model.profiles)
		var observed:=average(actual,model.profiles)
		for id in actual:
			if not model.profiles.has(id):
				uncertain=true
				notes.append(_name(id,definitions)+"的属性模型尚未配置。")
		for i in range(4):
			var key: String=ATTRS[i]
			var target:=float(recipe.get(key,ideal[i]))
			var value:=target+(float(observed[i])-float(ideal[i]))*float(model.attribute_gain)
			# Configured sensory imbalance only; does not fabricate liquid or change ABV.
			if rule.has("mix") and key in ["sweetness","sourness","bitterness"]:
				value+=(1-blend)*[0,3,5,2][i]
			targets[key]=roundi(target)
			attributes[key]=roundi(clampf(value,0,100))
			deltas[key]=attributes[key]-targets[key]
		# Dissolved solid sugar can affect taste; rim decorations never enter the liquid model.
		var sugar:=float(serving.get("solids",{}).get("sku_white_cane_sugar",0))
		if sugar>0:
			attributes.sweetness=mini(100,int(attributes.sweetness)+roundi(100*sugar/maxf(20,actual_volume)))
			deltas.sweetness=attributes.sweetness-targets.sweetness
	var tags: Array=[]
	if deltas.sweetness>=22: tags.append({"text":"齁甜的","color":"c88449"})
	elif deltas.sweetness>=10: tags.append({"text":"甜味突出","color":"c99a55"})
	if deltas.sourness>=18: tags.append({"text":"尖酸的","color":"8da74a"})
	elif deltas.sourness>=8: tags.append({"text":"清酸的","color":"a0b875"})
	if deltas.bitterness>=12: tags.append({"text":"苦重的","color":"84624d"})
	if deltas.alcohol_intensity>=12: tags.append({"text":"酒感强烈","color":"bc7652"})
	elif deltas.alcohol_intensity<=-12: tags.append({"text":"寡淡的","color":"879ea2"})
	if rule.has("mix") and blend<.80: tags.append({"text":"融合不足","color":"ab8d83"})
	if rule.has("muddle") and float(trace.herb)<actual_volume*.8: tags.append({"text":"草本不足","color":"78946d"})
	if float(trace.flat)>0: tags.append({"text":"气泡不足","color":"8c9b91"})
	elif float(trace.carbonated)>0 and tags.size()<2: tags.append({"text":"清爽的","color":"74a995"})
	if tags.size()<2 and attributes.sweetness>=40 and absf(deltas.sweetness)<10: tags.append({"text":"甜润的","color":"bd985d"})
	if tags.size()<2 and attributes.alcohol_intensity>=60 and absf(deltas.alcohol_intensity)<12: tags.append({"text":"醇厚的","color":"a97c4e"})
	if tags.is_empty(): tags.append({"text":"平衡的","color":"8ca27d"})
	var weights: Array=model.weights
	var score:=recipe_score*float(weights[0])+process_score*float(weights[1])+finish_score*float(weights[2])
	if missing_major or (rule.has("mix") and coverage<.2): score=minf(score,59)
	if recipe_score<35: score=minf(score,34)
	if minf(recipe_score,minf(process_score,finish_score))<95: score=minf(score,94)
	if max_dose_error>float(model.dose_bands.perfect)+.0001:
		score=minf(score,94)
		if max_dose_error<=float(model.dose_bands.recommended)+.0001: reasons.append("用量在推荐范围内，存在小幅偏差，保留良好品质但未达完美。")
	if uncertain: score=minf(score,89)
	var tier: Dictionary=model.tiers.back()
	for candidate in model.tiers:
		if score>=float(candidate.minimum): tier=candidate; break
	var research: bool=session.get("mode","") in ["research","development"] or recipe.get("source_kind","")=="diy"
	if research:
		tier={"id":"trial","title":"试调完成","color":"78a99b"}
	if session.get("sensory_model",{}).get("version")=="research-sensory-2":
		attributes=Research.attributes(session,definitions).attributes
		targets=Research.standard(recipe,session.sensory_model).attributes
	if session.get("mode")=="research_legendary":
		attributes=Research.attributes(session,definitions).attributes
	reasons.sort_custom(func(a,b): return _reason_priority(str(a))<_reason_priority(str(b)))
	if reasons.is_empty(): reasons.append("用料贴合目标，关键操作和出品要求均已完成。")
	return {"version":model.version,"draft":true,"tier":tier.id,"title":tier.title,"color":tier.color,"score":null if research else roundi(score),"attributes":attributes,"targets":targets,"tags":tags,"reasons":reasons,"notes":notes,"subscores":{"recipe":roundi(recipe_score),"process":roundi(process_score),"finish":roundi(finish_score)},"trace":trace,"recipe_version":recipe.get("version",1),"sensory_model_version":str(sensory_model.get("version","legacy-quality")),"data_complete":sensory_result.get("data_complete",not uncertain) and standard_result.get("data_complete",not uncertain),"missing_profiles":sensory_result.get("missing",[])}

static func _name(id: String, definitions: Dictionary) -> String:
	for key in definitions:
		if sku(key,definitions)==id: return str(definitions[key].get("name",id))
	return id

static func _amount(value: float) -> String:
	return ("%.2f" % value).trim_suffix("0").trim_suffix("0").trim_suffix(".")

static func _reason_priority(reason: String) -> int:
	if reason.contains("未完成") or reason.begins_with("缺少"): return 0
	if reason.contains("比配方") or reason.contains("配方外"): return 1
	return 2

static func valid(value: Variant) -> bool:
	if not value is Dictionary: return false
	for key in ["version","tier","title","color"]:
		if not value.get(key) is String: return false
	if not Color.html_is_valid(value.color): return false
	if value.get("score")!=null and not _score(value.score): return false
	for field in ["attributes","targets","subscores"]:
		if not value.get(field) is Dictionary: return false
		for key in (["recipe","process","finish"] if field=="subscores" else ATTRS):
			if not _score(value[field].get(key)): return false
	for field in ["reasons","notes"]:
		if not value.get(field) is Array: return false
		for line in value[field]:
			if not line is String: return false
	if not value.get("tags") is Array: return false
	for tag in value.tags:
		if not tag is Dictionary or not tag.get("text") is String or not tag.get("color") is String or not Color.html_is_valid(tag.color): return false
	return true

static func _score(value: Variant) -> bool:
	return (value is float or value is int) and is_finite(float(value)) and value>=0 and value<=100
