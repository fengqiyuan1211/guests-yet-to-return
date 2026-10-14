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
	var c:=config(id)
	var b:=book()
	var chapters:=int(StoryDialogue.progress.get(c.get("guest_id",""),{}).get("completed",0))
	var satisfied:=satisfied_count(str(c.get("guest_id","")))
	var required_chapters:=maxi(0,int(c.get("required_chapters",0)))
	var required_satisfied:=maxi(0,int(c.get("required_satisfied",0)))
	return {"chapters":chapters,"satisfied":satisfied,"required_chapters":required_chapters,"required_satisfied":required_satisfied,
		"eligible":not c.is_empty() and chapters>=required_chapters and satisfied>=required_satisfied,
		"unlocked":b.unlocks.has(id),"reward":b.rewards.get(id,{}),"keepsake":c.get("keepsake",{}) if b.unlocks.has(id) else {}}

func requirement_text(id: String, show_progress:=false) -> String:
	var p:=progress(id)
	var parts:=PackedStringArray()
	if p.required_chapters>0:
		parts.append("剧情 %d / %d 轮" % [mini(p.chapters,p.required_chapters),p.required_chapters] if show_progress else "完成第 %d 轮剧情" % p.required_chapters)
	if p.required_satisfied>0:
		parts.append("满意招待 %d / %d 次" % [mini(p.satisfied,p.required_satisfied),p.required_satisfied] if show_progress else "%d 次满意招待" % p.required_satisfied)
	return " · ".join(parts)

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
	for id in Rules.IDS:
		var c:=config(id)
		var p:=progress(id)
		var b:=book()
		if not p.unlocked and p.eligible:
			b.unlocks[id]={"source":"character-invite:"+id,"day":TimeManager.day}
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
