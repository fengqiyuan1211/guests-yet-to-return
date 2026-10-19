extends Node
## Activity progress and research rewards share the stock ledger's atomic write.
signal changed
const Rules=preload("res://scripts/guest_activity_rules.gd")
var active: Dictionary={}
var last_error:=""
var _reconciling:=false
var migration_notice:=""

func _ready() -> void:
	StoryDialogue.changed.connect(_queue_reconcile)
	GuestService.changed.connect(_queue_reconcile)
	CustomerService.changed.connect(_queue_reconcile)
	call_deferred("reconcile")
	call_deferred("migrate_legacy_ski_spoon")

func _queue_reconcile() -> void:
	if not _reconciling: call_deferred("reconcile")

func config(id: String) -> Dictionary:
	var data: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://data/guest_activities.json"))
	for guest in data:
		if data[guest].has(id): return data[guest][id].duplicate(true)
	return {}

func book() -> Dictionary:
	return WorkbenchSession.state.get("activities",Rules.fresh_book()).duplicate(true)

func satisfied_count(guest: String) -> int:
	var visits: Dictionary={}
	for tx: Dictionary in GuestService.ledger().deliveries.values():
		if tx.phase=="complete" and tx.order.guest_id==guest and tx.receipt.status=="accepted" and float(tx.receipt.score)>=70:
			visits[tx.order.visit_id]=true
	for record: Dictionary in CustomerService.state.deliveries.values():
		if record.status=="settled" and record.guest_id==guest and record.get("play_mode","story")!="mixing" and record.review.status=="scored" and record.review.get("satisfaction")!=null and float(record.review.satisfaction)>=70:
			visits[record.visit_id]=true
	return visits.size()

func progress(id: String) -> Dictionary:
	var c:=config(id); var guest:=str(c.get("guest_id","")); var b:=book()
	var gate=preload("res://scripts/story_activity_gate.gd")
	var summary: Dictionary=gate.summarize(guest,StoryDialogue.progress.get(guest,{}),StoryDialogue.catalog.get(guest,[]),CustomerService.state.deliveries,GuestService.ledger().deliveries)
	return {"chapters":summary.story_completed,"satisfied":satisfied_count(guest),"required_chapters":summary.required_scores,"required_satisfied":0,
		"eligible":not c.is_empty() and summary.eligible,"unlocked":b.unlocks.has(id),"reward":b.rewards.get(id,{}),
		"keepsake":c.get("keepsake",{}) if b.unlocks.has(id) else {},"summary":summary}

func requirement_text(id: String, show_progress:=false) -> String:
	var p:=progress(id); var summary: Dictionary=p.summary
	if not show_progress: return "讲完全部 %d 次来访故事，送酒平均总分高于 %.0f 分" % [p.required_chapters,summary.minimum_average]
	var average: String="待完成" if summary.average==null else "%.1f 分" % float(summary.average)
	return "故事 %d / %d · 已送酒 %d / %d · 均分 %s（需高于 %.0f）" % [mini(p.chapters,p.required_chapters),p.required_chapters,summary.score_count,summary.required_scores,average,summary.minimum_average]

func current_invitation() -> String:
	if PlayModes.mode!="story" or StoryDialogue.phase!="idle": return ""
	var guest:=str(CustomerService.state.active.get("guest_id",""))
	if guest!=StoryDialogue.guest_id: return ""
	var record:=CustomerService.current_record()
	var receipt_id:=""
	if not record.is_empty():
		if record.status!="settled" or not record.feedback.done or record.feedback.pending: return ""
		receipt_id=str(record.id)
	else:
		var receipt:=GuestService.visit_receipt(GuestService.current_visit())
		receipt_id=str(receipt.get("id",""))
	if receipt_id.is_empty(): return ""
	for id in Rules.INVITATION_IDS:
		if config(id).guest_id!=guest: continue
		var p:=progress(id)
		if p.unlocked and p.eligible and p.summary.final_delivery_id==receipt_id and not book().unlocks[id].get("invitation_seen",false): return id
	return ""

func acknowledge_invitation(id: String) -> bool:
	if current_invitation()!=id: return _error("这次邀请已变化，请返回酒馆查看。")
	var b:=book(); b.unlocks[id]["invitation_seen"]=true
	return _commit(b)

func _commit(b: Dictionary, research: Dictionary={}) -> bool:
	if not Rules.valid_book(b) or not WorkbenchSession.writable: return _error("活动记录暂时无法保存，请保留当前页面后重试。")
	var next:=WorkbenchSession.snapshot()
	next.activities=b
	if not research.is_empty(): next.research=research
	if not WorkbenchSession._commit(next): return _error(WorkbenchSession.last_error)
	last_error=""
	changed.emit()
	return true

func _error(message: String) -> bool:
	last_error=message
	return false

func reconcile() -> bool:
	if _reconciling or GameSession.resetting or not StoryDialogue.writable or not GameSession.writable or not WorkbenchSession.writable: return false
	_reconciling=true
	var ok:=true
	for id in Rules.INVITATION_IDS:
		var c:=config(id)
		var p:=progress(id)
		var b:=book()
		if not p.unlocked and p.eligible:
			b.unlocks[id]={"source":"character-invite:"+id,"day":TimeManager.day,"gate_version":1,"average_total":p.summary.average,"delivery_ids":p.summary.delivery_ids,"invitation_seen":false}
			if not _commit(b): ok=false; break
		if book().unlocks.has(id) and not StoryDialogue.unlock_activity(c.guest_id,id,str(book().unlocks[id].source)):
			ok=_error("邀请已保存，手帐同步暂未完成，下次打开会继续恢复。")
	_reconciling=false
	return ok

func begin(id: String, restart:=false) -> bool:
	migration_notice=""
	if id not in Rules.IDS: return _error("活动尚未登记。")
	var c:=config(id)
	var b:=book()
	var normal: bool=b.unlocks.has(id)
	if not normal and not c.get("demo_unlocked",false): return _error("请先收到客人的邀请。")
	active={"id":"activity-"+Crypto.new().generate_random_bytes(12).hex_encode(),"activity_id":id,"version":1,"state":Rules.fresh(id),"mode":"normal" if normal else "demo"}
	if normal:
		if not restart and b.runs.has(id) and (not b.runs[id].state.won or not b.rewards.has(id)): active=b.runs[id].duplicate(true); active.mode="normal"
		if id=="ada_watch_memory" and active.state.get("model",1)!=2 and not active.state.won:
			active.state=Rules.fresh(id)
			migration_notice="旧版听音练习已更新为机芯复位，本局从第一段开始；邀请和已领取奖励保留。"
		if id=="hank_lantern" and active.state.get("model",1)!=2 and not active.state.won:
			active.state=Rules.fresh(id)
			migration_notice="移灯影戏已更新为推箱子备货，本局从第一关开始；邀请与已领取奖励保留。"
		if id=="hank_lantern" and active.state.get("model")==2 and Rules.Crates.edition(active.state)==1:
			migration_notice="正在继续旧版三关进度；这局的位置和撤回记录保留。完成后再玩一局，将进入新版五关。"
		if id=="hank_lantern" and active.state.get("model")==2: active.state=Rules.Crates.normalized(active.state)
		b.runs[id]=active.duplicate(true)
		if not _commit(b): active={}; return false
	last_error=""
	return true

func action(kind: String, payload: Dictionary={}) -> bool:
	if active.is_empty(): return _error("请先开始游戏。")
	var result:=Rules.apply(active.activity_id,active.state,kind,payload)
	if not result.ok: return _error(result.message)
	var next:=active.duplicate(true)
	next.state=result.state
	# Continuous animation time stays in memory; checkpoint each target and on exit.
	var durable: bool=kind!="tick" or next.state.won or next.state.index!=active.state.index or next.state.misses!=active.state.misses
	if next.mode=="normal" and durable:
		var b:=book(); b.runs[next.activity_id]=next
		if not _commit(b): return false
	active=next
	last_error=""
	return true

func checkpoint() -> bool:
	if active.is_empty() or active.mode=="demo": return true
	var b:=book(); b.runs[active.activity_id]=active.duplicate(true)
	return _commit(b)

func claim() -> bool:
	if active.is_empty() or not active.state.won or not Rules.valid(active.activity_id,active.state): return _error("这一局还没有完成。")
	if active.mode=="demo": last_error=""; return true
	var b:=book()
	var id: String=active.activity_id
	if not b.unlocks.has(id) or not b.runs.has(id) or b.runs[id].id!=active.id or not b.runs[id].state.won: return _error("未找到本局正式完成记录。")
	if b.rewards.has(id): last_error=""; return true
	var c:=config(id)
	var recipe:=preload("res://scripts/research_data.gd").legendary(c.reward_recipe_id)
	if recipe.is_empty(): return _error("配方内容暂未读取，完成记录已保留，请稍后重试领取。")
	var r:=WorkbenchSession.research_state()
	var key:="first-clear:"+id
	r.acquired[c.reward_recipe_id]=key
	r.inspiration+=int(c.reward_inspiration)
	b.rewards[id]={"key":key,"recipe_id":c.reward_recipe_id,"inspiration":int(c.reward_inspiration),"day":TimeManager.day,"run_id":active.id}
	return _commit(b,r)

func end() -> bool:
	if not checkpoint(): return false
	active={}
	return true

func migrate_legacy_ski_spoon() -> bool:
	# One-time import only: all-time ski records must not regrant after a new game.
	var path := "user://yellow_ski.cfg"
	if not GameSession.save_path.begins_with("user://"):
		path=GameSession.save_path.get_base_dir().path_join("yellow_ski.cfg")
	var record:=ConfigFile.new()
	if FileAccess.file_exists(path) and record.load(path)!=OK: return false
	if record.get_value("legendary_spoon","migration_checked",false): return true
	if not Supplies.writable or not WorkbenchSession.writable or GameSession.resetting: return false
	if int(record.get_value("best","distance",0))>=2000 and book().unlocks.has("yellow_ski"):
		if not Supplies.grant_activity_equipment("tool_yellow_bar_spoon","yellow_ski"): return false
	record.set_value("legendary_spoon","migration_checked",true)
	if record.save(path+".tmp")!=OK: return false
	return DirAccess.rename_absolute(path+".tmp",path)==OK
