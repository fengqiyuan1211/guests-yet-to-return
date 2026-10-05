extends RefCounted
## Art-directed approximation. RGB is sRGB; strength is pigment contribution, not ABV.
const ALIASES={"gin":"sku_gin_london_dry","rum":"sku_white_rum","vodka":"sku_vodka","lime":"sku_lime_juice","syrup":"sku_simple_syrup","soda":"sku_soda_water"}
const State=preload("res://scripts/workbench_liquid_state.gd")
static var cached: Dictionary={}
static var render_cached: Dictionary={}

static func rendering() -> Dictionary:
	if render_cached.is_empty(): render_cached=JSON.parse_string(FileAccess.get_file_as_string("res://data/workbench/appearance_rendering.json"))
	return render_cached.duplicate(true)

static func profiles() -> Dictionary:
	if cached.is_empty():
		var catalog: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://data/supplies/catalog.json"))
		for item in catalog.items:
			if item.get("measurement_unit")=="ml":
				cached[item.id]=item.get("liquid_appearance",{"version":"missing","rgb":[255,0,255],"strength":1.0,"turbidity":0.0}).duplicate(true)
	return cached.duplicate(true)

static func sample(contents: Dictionary,snapshot: Dictionary={}) -> Dictionary:
	var source:=snapshot if not snapshot.is_empty() else profiles()
	var total:=State.volume(contents)
	if total<=0: return {"color":Color.TRANSPARENT,"strength":0.0,"turbidity":0.0}
	var rgb:=Vector3.ZERO
	var pigment:=0.0
	var cloud:=0.0
	for id in contents:
		var key: String=ALIASES.get(id,id)
		var p: Dictionary=source.get(key,{"rgb":[255,0,255],"strength":1.0,"turbidity":0.0})
		var values: Array=p.rgb
		var c:=Color(float(values[0])/255,float(values[1])/255,float(values[2])/255).srgb_to_linear()
		var weight:=float(contents[id])*float(p.strength)
		rgb+=Vector3(c.r,c.g,c.b)*weight
		pigment+=weight
		cloud+=float(contents[id])*float(p.turbidity)/total
	var strength:=pigment/total
	var render:=rendering()
	var clear: Array=render.clear_rgb
	var tint:=Color(float(clear[0])/255,float(clear[1])/255,float(clear[2])/255) # Visibility cue, never white pigment.
	if pigment>0:
		rgb/=pigment
		tint=Color(rgb.x,rgb.y,rgb.z).linear_to_srgb()
	# Weak tint fades through alpha; opaque juice gets a separate scattering cue.
	tint=tint.lerp(Color(.99,.98,.91),cloud*float(render.cloud_warmth))
	tint.a=clampf(float(render.opacity_base)+float(render.opacity_pigment)*(1-exp(-strength*float(render.pigment_response)))+float(render.opacity_cloud)*cloud,float(render.opacity_base),float(render.opacity_max))
	return {"color":tint,"strength":strength,"turbidity":cloud}

## Visual carbonation strength only; no inventory, flavour or pressure simulation.
static func carbonation(contents: Dictionary,snapshot: Dictionary={}) -> float:
	var total:=State.volume(contents)
	if total<=0: return 0.0
	var source:=snapshot if not snapshot.is_empty() else profiles()
	var legacy={"sku_soda_water":1.0,"sku_tonic_water":.9,"sku_cola":.8}
	var amount:=0.0
	for id in contents:
		var key: String=ALIASES.get(id,id)
		amount+=float(contents[id])*float(source.get(key,{}).get("carbonation",legacy.get(key,0.0)))
	return clampf(amount/total,0,1)

static func valid_snapshot(value: Variant) -> bool:
	if not value is Dictionary or value.is_empty(): return false
	for id in value:
		var p: Variant=value[id]
		if not id is String or not p is Dictionary or not p.get("version") is String or not p.get("rgb") is Array or p.rgb.size()!=3: return false
		for channel in p.rgb:
			if not _number(channel,255): return false
		if p.has("carbonation") and not _number(p.carbonation,1): return false
		if not _number(p.get("strength"),100) or not _number(p.get("turbidity"),1): return false
	return true

static func _number(value: Variant,maximum: float) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and value>=0 and value<=maximum
