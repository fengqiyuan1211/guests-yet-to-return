extends RefCounted
## Frozen menu and one explicit request. Tags are recipe tags, not perfect-craft buffs.
static func create(menu: Array, rng: RandomNumberGenerator) -> Dictionary:
	if menu.is_empty(): return {}
	var chosen: Dictionary=menu[rng.randi_range(0,menu.size()-1)]
	var tags: Array=chosen.get("tags",[])
	var indirect:=rng.randf()<0.5 and not tags.is_empty()
	var tag:=str(tags[rng.randi_range(0,tags.size()-1)]) if indirect else ""
	var line:="请给我一杯[b]%s[/b]。" % chosen.name
	if indirect: line="我想喝一杯[b]%s[/b]的酒，你帮我挑一杯吧。" % tag
	return {"kind":"tag" if indirect else "named","recipe_id":chosen.id,"tag":tag,"speech":line,"menu":menu.duplicate(true)}

static func settle(order: Dictionary, recipe_id: String, score: float) -> Dictionary:
	var served: Dictionary={}
	for entry: Dictionary in order.get("menu",[]):
		if entry.id==recipe_id: served=entry; break
	var matched: bool=not served.is_empty() and (recipe_id==order.get("recipe_id") if order.get("kind")=="named" else served.get("tags",[]).has(order.get("tag")))
	var price:=int(served.get("price",0))
	return {"matched":matched,"full_price":price,"craft_score":clampf(score,0,100),"amount":(price if score>=60 else floori(price*0.5)) if matched else 0,"tier":("full" if score>=60 else "half") if matched else "wrong"}
