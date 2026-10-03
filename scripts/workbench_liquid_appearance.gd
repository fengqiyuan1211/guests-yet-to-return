extends RefCounted
## Art-directed approximation. RGB is sRGB; strength is pigment contribution, not ABV.
const ALIASES={"gin":"sku_gin_london_dry","rum":"sku_white_rum","vodka":"sku_vodka","lime":"sku_lime_juice","syrup":"sku_simple_syrup","soda":"sku_soda_water"}
const State=preload("res://scripts/workbench_liquid_state.gd")
static var cached: Dictionary={}

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
	var tint:=Color(.90,.95,.97) # Small neutral water/glass visibility cue, never white pigment.
	if pigment>0:
		rgb/=pigment
		tint=Color(rgb.x,rgb.y,rgb.z).linear_to_srgb()
	# Weak tint fades through alpha; opaque juice gets a separate scattering cue.
	tint=tint.lerp(Color(.95,.94,.85),cloud*.16)
	tint.a=clampf(.12+.64*(1-exp(-strength*1.8))+.32*cloud,.12,.92)
	return {"color":tint,"strength":strength,"turbidity":cloud}

static func valid_snapshot(value: Variant) -> bool:
	if not value is Dictionary or value.is_empty(): return false
	for id in value:
		var p: Variant=value[id]
		if not id is String or not p is Dictionary or not p.get("version") is String or not p.get("rgb") is Array or p.rgb.size()!=3: return false
		for channel in p.rgb:
			if not _number(channel,255): return false
		if not _number(p.get("strength"),100) or not _number(p.get("turbidity"),1): return false
	return true

static func _number(value: Variant,maximum: float) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and value>=0 and value<=maximum
