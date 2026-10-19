extends Node
## Observed conversations and durable service events; purchases never grant affinity.
signal changed
const CONFIG_PATH := "res://data/relationships.json"
var config: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(CONFIG_PATH))
var state: Dictionary = fresh()
var save_path := ""
var writable := true
var last_error := ""
var queued := false

static func fresh() -> Dictionary:
	return {"version":1,"events":{},"heard":{},"cursors":{},"flags":{}}

func _ready() -> void:
	save_path = GameSession.save_path + ".relationships"
	load_state()
	StoryDialogue.changed.connect(_queue)
	CustomerService.changed.connect(_queue)
	GuestService.changed.connect(_queue)
	OpeningFlow.changed.connect(_queue)
	_queue()

func valid(value: Variant) -> bool:
	if not value is Dictionary or value.get("version")!=1: return false
	for key in ["events","heard","cursors","flags"]:
		if not value.get(key) is Dictionary: return false
	for id in value.events:
		var event: Variant = value.events[id]
		if not id is String or not event is Dictionary or not event.get("person") is String or not event.get("reason") is String: return false
		if not (event.get("delta") is int or event.get("delta") is float) or not is_finite(float(event.delta)) or absf(float(event.delta))>1000: return false
	for id in value.heard:
		var line: Variant = value.heard[id]
		if not line is Dictionary or not line.get("text") is String or not line.get("speaker") is String or not line.get("topic") is String: return false
	for topic in value.cursors:
		var cursor: Variant = value.cursors[topic]
		if not config.topics.has(topic) or not (cursor is int or cursor is float) or cursor!=floor(cursor) or cursor<0 or cursor>config.topics[topic].size(): return false
	for flag in value.flags:
		if not value.flags[flag] is bool: return false
	return true

func load_state() -> bool:
	if not FileAccess.file_exists(save_path): return true
	var loaded: Variant = JSON.parse_string(FileAccess.get_file_as_string(save_path))
	if not valid(loaded):
		writable=false
		last_error="关系记录无法读取，原文件已保留。"
		return false
	state=loaded
	return true

func _commit(next: Dictionary) -> bool:
	if not writable or OpeningFlow.replaying or not valid(next): return false
	var file := FileAccess.open(save_path+".tmp",FileAccess.WRITE)
	if file==null:
		last_error="手帐暂时无法保存，请重试。"
		return false
	file.store_string(JSON.stringify(next))
	file.flush()
	var ok := file.get_error()==OK
	file.close()
	if not ok or DirAccess.rename_absolute(ProjectSettings.globalize_path(save_path+".tmp"),ProjectSettings.globalize_path(save_path))!=OK:
		last_error="手帐暂时无法保存，尚未推进这段对话。"
		return false
	# Keep nested numeric types identical before and after process recovery.
	state=JSON.parse_string(JSON.stringify(next))
	last_error=""
	changed.emit()
	return true

func reset_game() -> bool:
	writable=true
	return _commit(fresh())

func _queue() -> void:
	if queued: return
	queued=true
	call_deferred("reconcile")

func _event(next: Dictionary, id: String, person: String, reason: String, points: int) -> void:
	if not next.events.has(id): next.events[id]={"person":person,"reason":reason,"delta":points,"rule_version":config.version}

func reconcile() -> bool:
	queued=false
	if OpeningFlow.replaying or GameSession.resetting or not writable or not StoryDialogue.writable or not StoryDialogue.last_error.is_empty(): return false
	var next := state.duplicate(true)
	for person: String in StoryDialogue.progress:
		if StoryDialogue.is_known(person): _event(next,"met:"+person,person,"已经互相介绍",0)
		for i in range(int(StoryDialogue.progress[person].get("completed",0))):
			_event(next,"chapter:%s:%d" % [person,i+1],person,"听完了第 %d 段故事" % (i+1),int(config.chapter_points))
	for record: Dictionary in CustomerService.state.deliveries.values():
		if record.status!="settled" or record.get("play_mode","story")=="mixing": continue
		next.flags["formal_visit"]=true
		_event(next,"met:"+str(record.guest_id),str(record.guest_id),"已经相识",0)
		var score: Variant=record.review.get("satisfaction")
		if record.review.status=="scored" and score!=null and float(score)>=float(config.satisfied_minimum):
			_event(next,"service:"+str(record.visit_id),str(record.guest_id),"认真照顾了这次口味",int(config.satisfied_points))
	for tx: Dictionary in GuestService.ledger().deliveries.values():
		if tx.phase!="complete": continue
		next.flags["formal_visit"]=true
		_event(next,"met:"+str(tx.order.guest_id),str(tx.order.guest_id),"已经相识",0)
		if tx.receipt.status=="accepted" and float(tx.receipt.score)>=float(config.satisfied_minimum):
			_event(next,"service:"+str(tx.order.visit_id),str(tx.order.guest_id),"认真照顾了这次口味",int(config.satisfied_points))
	if next==state: return true
	return _commit(next)

func known(person: String) -> bool:
	return state.events.has("met:"+person) or StoryDialogue.is_known(person)

func summary(person: String) -> Dictionary:
	var points := 0
	var reasons: Array[String] = []
	for event: Dictionary in state.events.values():
		if event.person!=person: continue
		points+=int(event.delta)
		if not reasons.has(str(event.reason)): reasons.append(str(event.reason))
	var stage := "尚未相识"
	if known(person):
		for row: Dictionary in config.stages:
			if points>=int(row.minimum): stage=row.name
	return {"stage":stage,"points":points,"reasons":reasons}

func topic_available(topic: String) -> bool:
	if not config.topics.has(topic) or state.flags.get("done:"+topic,false): return false
	match topic:
		"merchant_intro": return true
		"merchant_seed": return state.flags.get("done:merchant_intro",false)
		"merchant_return": return state.flags.get("done:merchant_seed",false) and state.flags.get("formal_visit",false)
		"old_invoice": return state.flags.get("done:merchant_return",false) and summary("harbor_merchant").points>=int(config.old_invoice_minimum)
	return false

func next_merchant_topic() -> String:
	for topic in ["merchant_intro","merchant_seed","merchant_return","old_invoice"]:
		if topic_available(topic): return topic
	return ""

func observe_line(topic: String, index: int) -> bool:
	if not topic_available(topic) or index!=int(state.cursors.get(topic,0)) or index>=config.topics[topic].size(): return false
	var next := state.duplicate(true)
	var id := "%s:%d" % [topic,index]
	if next.heard.has(id): return true
	var line: Dictionary=config.topics[topic][index].duplicate(true)
	line.topic=topic
	next.heard[id]=line
	if topic=="merchant_intro" and index>=2: _event(next,"met:harbor_merchant","harbor_merchant","已经互相认识",0)
	if topic=="merchant_seed" and index>=2: next.flags["invoice_heard"]=true
	if line.get("evidence",false): next.flags["invoice_seen"]=true
	return _commit(next)

func advance_topic(topic: String, expected_index: int) -> bool:
	if not topic_available(topic) or expected_index!=int(state.cursors.get(topic,0)) or not state.heard.has("%s:%d" % [topic,expected_index]): return false
	var next := state.duplicate(true)
	next.cursors[topic]=expected_index+1
	if next.cursors[topic]>=config.topics[topic].size():
		next.flags["done:"+topic]=true
		if topic=="merchant_return": _event(next,"merchant:return","harbor_merchant","回来聊了聊第一晚的经历",int(config.merchant_return_points))
	return _commit(next)

func mark_guide_seen() -> bool:
	if state.flags.get("guide_seen",false): return true
	var next := state.duplicate(true)
	next.flags["guide_seen"]=true
	return _commit(next)

func guide_pending() -> bool:
	return not OpeningFlow.state.get("legacy",false) and OpeningFlow.state.get("departure",{}).get("opened",false) and state.flags.get("formal_visit",false) and not state.flags.get("guide_seen",false)

func merchant_history() -> Array:
	var groups: Array=[]
	for topic: String in config.topics:
		var lines: Array=[]
		for i in range(config.topics[topic].size()):
			var id:="%s:%d" % [topic,i]
			if state.heard.has(id):
				var row: Dictionary=state.heard[id]
				lines.append({"speaker":"player" if str(row.speaker).begins_with("我") else "guest","text":row.text,"key":id})
		if not lines.is_empty(): groups.append({"id":topic,"title":{"merchant_intro":"第一次认门","merchant_seed":"未完的话","merchant_return":"再来坐坐","old_invoice":"旧单背面"}[topic],"lines":lines})
	return groups
