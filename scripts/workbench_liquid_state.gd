extends RefCounted
## Authoritative liquid amounts, bottom-to-top layers. No inventory or rendering writes.
const VERSION="layers-v1"
const DEFAULT_MODEL={"version":VERSION,"stir_rate":.8,"shake_rate":1.4,"uniform_tolerance":.015}

static func config() -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string("res://data/workbench/liquid.json"))

static func volume(contents: Dictionary) -> float:
	var result:=0.0
	for value in contents.values(): result+=float(value)
	return result

static func layers(vessel: Dictionary) -> Array:
	if vessel.has("layers"): return vessel.layers.duplicate(true)
	var contents: Dictionary=vessel.get("contents",{})
	return [{"contents":contents.duplicate(true)}] if volume(contents)>0 else []

static func ensure(vessel: Dictionary) -> void:
	if not vessel.has("layers"): vessel.layers=layers(vessel)

static func aggregate(stack: Array) -> Dictionary:
	var result: Dictionary={}
	for layer in stack:
		for id in layer.contents:
			result[id]=float(result.get(id,0))+float(layer.contents[id])
	return result

static func distance(a: Dictionary,b: Dictionary) -> float:
	var av:=maxf(.000000001,volume(a))
	var bv:=maxf(.000000001,volume(b))
	var keys:=a.duplicate()
	keys.merge(b)
	var result:=0.0
	for id in keys: result+=absf(float(a.get(id,0))/av-float(b.get(id,0))/bv)
	return result*.5

static func grouped(contents: Dictionary,groups: Dictionary) -> Dictionary:
	var result: Dictionary={}
	for id in contents:
		var key: String=groups.get(id,id)
		result[key]=float(result.get(key,0))+float(contents[id])
	return result

static func add(vessel: Dictionary,contents: Dictionary,groups: Dictionary={}) -> void:
	ensure(vessel)
	if volume(contents)<=0: return
	if not vessel.layers.is_empty() and distance(grouped(vessel.layers.back().contents,groups),grouped(contents,groups))<.000000001:
		var combined:=aggregate([vessel.layers.back(),{"contents":contents}])
		vessel.layers.back().contents=combined
	else: vessel.layers.append({"contents":contents.duplicate(true)})
	vessel.contents=aggregate(vessel.layers)

static func mix(vessel: Dictionary,seconds: float,kind: String,control: float,model: Dictionary=DEFAULT_MODEL,groups: Dictionary={}) -> void:
	ensure(vessel)
	if vessel.layers.size()<2 or seconds<=0: return
	var all: Dictionary=vessel.contents
	var total:=volume(all)
	if total<=0: return
	var rate:=float(model.get(kind+"_rate",0))
	var fraction:=1-exp(-rate*seconds*clampf(control,0,1))
	if fraction<=0: return
	var largest:=0.0
	for layer in vessel.layers:
		var size:=volume(layer.contents)
		var next: Dictionary={}
		for id in all:
			next[id]=lerpf(float(layer.contents.get(id,0)),size*float(all[id])/total,fraction)
		layer.contents=next
		largest=maxf(largest,distance(grouped(next,groups),grouped(all,groups)))
	if largest<=float(model.get("uniform_tolerance",.015)):
		vessel.layers=[{"contents":all.duplicate(true)}]
	vessel.contents=aggregate(vessel.layers)

static func take(vessel: Dictionary,ml: float) -> Array:
	ensure(vessel)
	var stream: Array=[]
	var remaining:=minf(maxf(0,ml),volume(vessel.contents))
	while remaining>0 and not vessel.layers.is_empty():
		var top: Dictionary=vessel.layers.back().contents
		var total:=volume(top)
		if total<=0:
			vessel.layers.pop_back()
			continue
		var amount:=minf(remaining,total)
		var moved: Dictionary={}
		if amount>=total:
			moved=top.duplicate(true)
			vessel.layers.pop_back()
		else:
			for id in top:
				moved[id]=float(top[id])*amount/total
				top[id]=float(top[id])-float(moved[id])
		stream.append({"contents":moved})
		remaining=maxf(0,remaining-amount)
	vessel.contents=aggregate(vessel.layers)
	return stream

static func valid(vessel: Dictionary) -> bool:
	if not vessel.has("layers"): return true # Legacy: unknown history becomes one mixed layer.
	if not vessel.layers is Array: return false
	for layer in vessel.layers:
		if not layer is Dictionary or not layer.get("contents") is Dictionary or layer.contents.is_empty(): return false
		for id in layer.contents:
			var value: Variant=layer.contents[id]
			if not id is String or not (value is int or value is float) or not is_finite(float(value)) or value<0: return false
		if volume(layer.contents)<=0: return false
	var all:=aggregate(vessel.layers)
	var keys: Dictionary=vessel.contents.duplicate()
	keys.merge(all)
	for id in keys:
		if absf(float(all.get(id,0))-float(vessel.contents.get(id,0)))>.00001: return false
	return true

static func description(vessel: Dictionary) -> String:
	var stack:=layers(vessel)
	if stack.is_empty(): return "尚无酒液"
	if stack.size()==1: return "已混匀 · 品质另评"
	var difference:=0.0
	for layer in stack: difference=maxf(difference,distance(layer.contents,vessel.contents))
	return "%d 层 · %s" % [stack.size(),"正在融合" if difference<.35 else "分层明显"]

static func valid_model(value: Variant) -> bool:
	if not value is Dictionary or value.get("version")!=VERSION: return false
	for key in ["stir_rate","shake_rate","uniform_tolerance"]:
		var n: Variant=value.get(key)
		if not (n is int or n is float) or not is_finite(float(n)) or n<0 or n>10: return false
	return float(value.uniform_tolerance)<=1
