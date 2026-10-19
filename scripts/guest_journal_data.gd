extends RefCounted
## Read-only projection of existing story and cup saves. No wallet/inventory writes.

static func profiles() -> Array:
	var rows: Array=JSON.parse_string(FileAccess.get_file_as_string("res://data/guests.json"))
	rows.append({"id":"harbor_merchant","name":"老板娘","role":"港口货栈的经营者","bio":"船到港时，她会清点货物，也记得一些旧日的来客。","texture":"res://assets/art/shop/harbor-merchant.png","portrait":[0,0,600,850],"preferences":[],"avoid":[]})
	return rows

static func conversations(id: String, progress: Dictionary, catalog: Dictionary, workbench: Dictionary={}) -> Array:
	if id=="harbor_merchant": return Relationships.merchant_history()
	var state: Dictionary = progress.get(id, {})
	var groups: Array = []
	var seen: Dictionary = {}
	var by_chapter: Dictionary = {}
	# Import existing observed histories, including unfinished conversations.
	for chapter in catalog.get(id, []):
		var rows: Array = state.get("heard", {}).get(chapter.id, []).duplicate(true)
		if state.get("pending", {}).get("episode_id") == chapter.id:
			rows.append_array(state.pending.get("history", []))
		for line in rows:
			_append_line(groups, by_chapter, seen, chapter.id, str(chapter.title), line)
	for line in state.get("archive", []):
		var chapter_id := str(line.get("chapter_id", "smalltalk"))
		var title := "闲谈"
		for chapter in catalog.get(id, []):
			if chapter.id == chapter_id: title = str(chapter.title)
		_append_line(groups, by_chapter, seen, chapter_id, title, line)
	for cup in drinks(id,workbench):
		var reaction:=str(cup.result.get("customer_receipt",{}).get("reaction",""))
		if not reaction.is_empty():
			_append_line(groups,by_chapter,seen,"service","饮后评价",{"speaker":"guest","node":reaction.sha256_text(),"text":reaction})
	for record: Dictionary in CustomerService.state.deliveries.values():
		if record.guest_id!=id or record.status!="settled": continue
		for line in record.get("story",[]): _append_line(groups,by_chapter,seen,str(record.get("story_episode_id","service")),"来访对话",line)
		for line in record.feedback.get("messages",[]):
			_append_line(groups,by_chapter,seen,"service","饮后评价",{"speaker":line.speaker,"node":str(line.text).sha256_text(),"text":line.text})
	return groups

static func _append_line(groups: Array, by_chapter: Dictionary, seen: Dictionary, chapter: String, title: String, line: Variant) -> void:
	if not line is Dictionary or not line.get("text") is String or str(line.text).is_empty(): return
	var speaker := str(line.get("speaker", "guest"))
	var key := chapter + ":" + speaker + ":" + str(line.get("choice_id", line.get("node", line.text)))
	if seen.has(key): return
	seen[key] = true
	if not by_chapter.has(chapter):
		var group := {"id":chapter, "title":title, "lines":[]}
		by_chapter[chapter] = group
		groups.append(group)
	by_chapter[chapter].lines.append({"speaker":speaker, "text":str(line.text), "key":key})

static func drinks(id: String, workbench: Dictionary) -> Array:
	var cups: Array = workbench.get("history", []).duplicate()
	cups.append(workbench.get("session", {}))
	var rows: Array = []
	var seen: Dictionary = {}
	for cup in cups:
		if cup.get("status") != "finished" or str(cup.get("mode", "")).begins_with("research"): continue
		var result: Dictionary = cup.get("result", {})
		var guest: Dictionary = result.get("guest", cup.get("guest", {}))
		var key := str(result.get("drink_id", ""))
		if guest.get("id") != id or key.is_empty() or seen.has(key): continue
		seen[key] = true
		rows.append({"id":key, "guest":guest.duplicate(true), "result":result.duplicate(true)})
	for record: Dictionary in CustomerService.state.deliveries.values():
		if record.guest_id!=id or record.status!="settled": continue
		var row: Dictionary={}
		for existing in rows:
			if existing.id==record.drink_id: row=existing; break
		if row.is_empty():
			var result: Dictionary=record.get("cup",{}).duplicate(true)
			if result.is_empty(): result={"drink_id":record.drink_id,"recipe":{"id":record.recipe_id,"name":record.recipe_name},"evaluation":record.get("craft",{}).duplicate(true),"completed_at":{"day":record.day},"contents":{"contents":{}},"guest":{"id":id}}
			row={"id":record.drink_id,"guest":{"id":id},"result":result}; rows.append(row)
		var rejected: bool=record.review.status=="rejected"
		var score: Variant=record.review.get("satisfaction")
		var lines: Array=[]
		for message in record.feedback.get("messages",[]):
			if message.speaker=="guest": lines.append(message.text)
		row.result.customer_receipt={"id":record.id,"delivered":true,"paid":true,"status":"rejected" if rejected else "accepted","score":score,"satisfaction":"拒收" if rejected else ("满意" if score!=null and float(score)>=70 else "一般"),"base_paid":record.get("base_paid",record.amount),"tip":record.get("tip",0),"total_paid":record.amount,"reaction":"\n".join(lines),"evaluation":{"attributes":record.actual.get("attributes",{}),"reasons":record.review.get("reasons",[])}}
	rows.reverse() # Session serial / archive insertion order, newest first.
	return rows

static func activities(id: String, progress: Dictionary) -> Array:
	var config: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/guest_activities.json"))
	var rows: Array = []
	for key in config.get(id, {}):
		var item: Dictionary = config[id][key].duplicate(true)
		item.id = key
		item.unlocked = progress.get(id, {}).get("activity_unlocks", {}).has(key)
		if key=="stick_minigame": item.unlocked = item.unlocked or CustomerService.memory_summary().eligible
		item.demo = item.get("demo_unlocked", false) == true
		item.accessible = item.unlocked or item.demo
		rows.append(item)
	return rows

static func valid_receipt(receipt: Variant) -> bool:
	if not receipt is Dictionary: return false
	for key in ["id", "satisfaction"]:
		if not receipt.get(key) is String or receipt[key].is_empty() or receipt[key].length() > 128: return false
	if receipt.get("delivered") != true or receipt.get("paid") != true: return false
	var score: Variant = receipt.get("score")
	if receipt.get("status")=="rejected":
		if score!=null or receipt.get("total_paid")!=0: return false
	elif not (score is int or score is float) or not is_finite(float(score)) or score < 0 or score > 1000: return false
	for key in ["base_paid", "tip", "total_paid"]:
		var value: Variant = receipt.get(key)
		if not (value is int or value is float) or not is_finite(float(value)) or value != floor(value) or value < 0 or value > 1000000000: return false
	return receipt.total_paid == receipt.base_paid + receipt.tip
