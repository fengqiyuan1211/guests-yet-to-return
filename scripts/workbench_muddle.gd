extends RefCounted
## Per-leaf, persisted processing facts. Visual fragments never become extra inventory.
const LEAF="sku_mint_leaf"
const MAX_WORK=30.0
const READY_MIN=2.0
const READY_MAX=4.0
const TORN_AT=3.0
const FRAGMENTS_AT=9.0

static func leaves(v: Dictionary) -> Array:
	if v.has("mint_processing"): return v.mint_processing.duplicate(true)
	var result: Array=[]
	for i in range(int(v.get("solids",{}).get(LEAF,0))): result.append({"seconds":0.0,"work":0.0})
	return result

static func add(v: Dictionary) -> void:
	var rows:=leaves(v)
	while rows.size()<int(v.get("solids",{}).get(LEAF,0)): rows.append({"seconds":0.0,"work":0.0})
	v.mint_processing=rows

static func press(v: Dictionary,seconds: float,pressure: float) -> void:
	var rows:=leaves(v)
	for row in rows:
		row.seconds=minf(300,float(row.seconds)+seconds)
		row.work=minf(MAX_WORK,float(row.work)+seconds*lerpf(.65,2.0,clampf(pressure,0,1)))
	v.mint_processing=rows

static func transfer(source: Dictionary,target: Dictionary,count: int) -> void:
	var a:=leaves(source)
	var b:=leaves(target)
	for i in range(mini(count,a.size())): b.append(a.pop_front())
	source.mint_processing=a
	target.mint_processing=b

static func summary(v: Dictionary) -> Dictionary:
	var rows:=leaves(v)
	var low:=MAX_WORK
	var high:=0.0
	var seconds:=300.0
	for row in rows:
		low=minf(low,float(row.work))
		high=maxf(high,float(row.work))
		seconds=minf(seconds,float(row.seconds))
	return {"count":rows.size(),"min_work":low if not rows.is_empty() else 0.0,"max_work":high,"seconds":seconds if not rows.is_empty() else 0.0}

static func valid(v: Dictionary) -> bool:
	if not v.has("mint_processing"): return true
	if not v.mint_processing is Array or v.mint_processing.size()!=int(v.get("solids",{}).get(LEAF,0)): return false
	for row in v.mint_processing:
		if not row is Dictionary: return false
		for key in ["seconds","work"]:
			var n: Variant=row.get(key)
			if not (n is float or n is int) or not is_finite(float(n)) or n<0 or n>(300 if key=="seconds" else MAX_WORK): return false
	return true
