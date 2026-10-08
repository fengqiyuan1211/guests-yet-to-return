extends Node
## One durable switch intent; money, stock, research and all delivery receipts remain shared.
var mode := "story"
var contexts: Dictionary={}
var pending: Dictionary={}
var path := "user://play_modes.json"
var busy := false
var last_error := ""
var writable := true

func _ready() -> void:
	path=GameSession.save_path+".modes"
	if FileAccess.file_exists(path):
		var value: Variant=JSON.parse_string(FileAccess.get_file_as_string(path))
		if not value is Dictionary or value.get("mode") not in ["story","mixing"] or not value.get("contexts") is Dictionary or not value.get("pending",{}) is Dictionary:
			writable=false
			last_error="模式进度未能读取，请保留存档。"
			return
		mode=value.mode
		contexts=value.contexts
		pending=value.get("pending",{})
		for key in contexts:
			if key not in ["story","mixing"] or not _valid_context(contexts[key]):
				writable=false
				last_error="模式进度不完整，请保留存档。"
				return
		if not pending.is_empty():
			if pending.get("target") not in ["story","mixing"] or not _valid_context(pending.get("context")):
				writable=false
				last_error="切换记录不完整，请保留存档。"
				return
			if not _apply_pending(): writable=false

func _valid_context(value: Variant) -> bool:
	if not value is Dictionary: return false
	for key in ["clock","story","visit","customer","workbench"]:
		if not value.get(key) is Dictionary: return false
	if not WorkbenchSession._valid_session(value.workbench) or not WorkbenchSession._valid_table_materials(value.get("table_materials",[])): return false
	if not GameSession._valid({"version":1,"clock":value.clock,"active":value.story,"visit":value.visit,"story":{"version":1,"guests":StoryDialogue.progress}}): return false
	var customer: Dictionary=CustomerService.state.duplicate(true)
	customer.active=value.customer
	return CustomerService._valid_saved_state(customer)

func _write() -> bool:
	var f:=FileAccess.open(path+".tmp",FileAccess.WRITE)
	if f==null: return false
	f.store_string(JSON.stringify({"version":1,"mode":mode,"contexts":contexts,"pending":pending}))
	f.flush()
	var ok:=f.get_error()==OK
	f.close()
	return ok and DirAccess.rename_absolute(ProjectSettings.globalize_path(path+".tmp"),ProjectSettings.globalize_path(path))==OK

func _capture() -> Dictionary:
	return {"clock":TimeManager.snapshot(),"story":StoryDialogue.session_snapshot(),"visit":GameSession.visit.duplicate(true),"customer":CustomerService.state.active.duplicate(true),"workbench":WorkbenchSession.state.session.duplicate(true),"table_materials":WorkbenchSession.state.get("table_materials",[]).duplicate()}

func switch_to(target: String) -> bool:
	if busy or not writable or target not in ["story","mixing"] or target==mode: return false
	if not GameSession.writable or not CustomerService.writable or not WorkbenchSession.writable:
		last_error="进度暂时无法保存，请稍后再切换。"
		return false
	if target=="mixing" and not contexts.has(target):
		if MenuCatalog.entries.is_empty():
			last_error="先挂好一份营业酒单，再开始调酒模式。"
			return false
		var known:=false
		for id in StoryDialogue.catalog:
			if StoryDialogue.is_known(id) and (id!="stick" or not WorkbenchSession.research_state().get("story_items",{}).get("item_recipe_after_school",{}).get("owned",false)): known=true
		if not known:
			last_error="先在剧情模式认识一位客人，再邀请他来点酒。"
			return false
	if not SlotWallet.pending.is_empty():
		last_error="等老虎机这一轮结束后再切换。"
		return false
	if not GameSession.save_game():
		last_error="进度暂时无法保存，请稍后再切换。"
		return false
	busy=true
	var previous:=contexts.duplicate(true)
	contexts[mode]=_capture()
	var destination: Dictionary=contexts.get(target,{"clock":TimeManager.snapshot(),"story":{"phase":"none","guest_id":""},"visit":{},"customer":{},"workbench":{},"table_materials":[]}).duplicate(true)
	if not contexts.has(target) and destination.clock.get("closing_pending",false):
		destination.clock.closing_pending=false
		destination.clock.minutes=TimeManager.OPEN_MINUTE
	pending={"target":target,"context":destination}
	if not _write():
		contexts=previous
		pending={}
		busy=false
		last_error="模式进度未能保存，请重试。"
		return false
	if not _apply_pending():
		busy=false
		writable=false
		last_error="切换尚未完成，请重新打开游戏恢复进度。"
		return false
	busy=false
	Navigation.current_route=&"home"
	get_tree().change_scene_to_file("res://scenes/home.tscn")
	return true

func _apply_pending() -> bool:
	var context: Dictionary=pending.context
	CustomerService._cancel_request()
	var next: Dictionary=WorkbenchSession.state.duplicate(true)
	next.session=context.workbench.duplicate(true)
	next.table_materials=context.get("table_materials",[]).duplicate()
	if not WorkbenchSession._commit(next): return false
	CustomerService.state.active=context.customer.duplicate(true)
	if not CustomerService._write(): return false
	GameSession.home=null
	StoryDialogue.restore_session(context.story)
	TimeManager.restore(context.clock)
	GameSession.visit=context.visit.duplicate(true)
	if not GameSession.save_game(): return false
	mode=pending.target
	var intent:=pending.duplicate(true)
	pending={}
	if not _write():
		pending=intent
		return false
	last_error=""
	return true

func reset_game() -> bool:
	mode="story"
	contexts={}
	pending={}
	writable=true
	return _write()
