extends Control
signal close_requested
const Rules=preload("res://scripts/guest_activity_rules.gd")
const CrateBoard=preload("res://scripts/hank_crate_board.gd")
const Board=preload("res://scripts/guest_activity_board.gd")
const FONT=preload("res://assets/fonts/NotoSerifSC.ttf")
const PAPER=preload("res://assets/codex/journal-paper-v1.png")
var activity_id: String
var config: Dictionary
var surface: Control
var board: Control
var hint_label: Label
var progress_label: Label
var mode_label: Label
var overlay: Panel
var playing:=false
var paused:=false
var previous_running:=true
var clock_restored:=false
var selection: Array=[0,0]
var sailing:=0.0
var sail_from:=0
var sail_load: Array=[0,0]
var own_run:=""
var audio: Node
var ambient_time:=0.0
var tick_time:=0.0
var end_pending:=false
var failure_outcome: Dictionary={}
var failure_shown:=false
var crate_queue: Array=[]
var crate_queued_direction:=""
var crate_hint_search: Dictionary={}
var crate_hint_key:=""
var crate_story_active:=false
var crate_story_remaining:=0.0
var crate_story_caption: Label
var application_focused:=true

func state() -> Dictionary:
	return GuestActivities.active.get("state",Rules.fresh(activity_id))

func _ready() -> void:
	activity_id=str(Navigation.current_route)
	config=GuestActivities.config(activity_id)
	previous_running=TimeManager.running
	TimeManager.set_running(false)
	surface=Control.new(); add_child(surface)
	board=CrateBoard.new() if activity_id=="hank_lantern" else Board.new(); board.game=self; board.size=Vector2(1600,900); surface.add_child(board)
	var title:=Panel.new(); title.position=Vector2(26,18); title.size=Vector2(535,111); title.mouse_filter=Control.MOUSE_FILTER_IGNORE; title.add_theme_stylebox_override("panel",_style(Color("f3dfb6"))); surface.add_child(title)
	_label(title,Rect2(18,9,510,48),str(config.get("name","客人的小游戏")),30)
	progress_label=_label(title,Rect2(18,60,510,36),"",22)
	_button(surface,Rect2(1210,24,156,48),"暂停 Esc",_pause)
	_button(surface,Rect2(1380,24,190,48),"返回手帐",_close)
	if activity_id in Rules.IDS:
		_button(surface,Rect2(1210,84,156,45),"提示 H",_hint)
		_button(surface,Rect2(1380,84,190,45),"撤回 Z",_undo)
	else: _button(surface,Rect2(1300,84,270,45),"慢速辅助",_assist)
	var ribbon:=Panel.new(); ribbon.position=Vector2(32,778); ribbon.size=Vector2(1280,97); ribbon.add_theme_stylebox_override("panel",_style(Color("fff0ce"))); surface.add_child(ribbon)
	hint_label=_label(ribbon,Rect2(18,6,1245,61),"",21)
	mode_label=_label(ribbon,Rect2(18,75,1245,21),"",14)
	var portrait:=Panel.new(); portrait.position=Vector2(1350,735); portrait.size=Vector2(220,145); portrait.mouse_filter=Control.MOUSE_FILTER_IGNORE; portrait.add_theme_stylebox_override("panel",_style(Color("4a3424"))); surface.add_child(portrait)
	var art:=TextureRect.new(); var atlas:=AtlasTexture.new()
	for profile in preload("res://scripts/guest_journal_data.gd").profiles():
		if profile.id==config.get("guest_id"):
			atlas.atlas=load(profile.texture); var region: Array=profile.portrait; atlas.region=Rect2(region[0],region[1],region[2],region[3])
	art.expand_mode=TextureRect.EXPAND_IGNORE_SIZE; art.texture=atlas; art.position=Vector2(4,4); art.size=Vector2(132,137); art.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED; art.mouse_filter=Control.MOUSE_FILTER_IGNORE; portrait.add_child(art)
	var quote:=_label(portrait,Rect2(140,22,76,113),{"milo_ferry":"别忘了
回来的
那一趟。","ada_watch_memory":"今天，
有时间
慢慢调。","hank_lantern":"这回，
把名字
也带上。"}[activity_id],19); quote.add_theme_color_override("font_color",Color("ffe9b7"))
	audio=preload("res://scripts/guest_activity_audio.gd").new(); add_child(audio)
	SaloonAudio.acquire_scene(self,"research" if activity_id=="ada_watch_memory" else "shop")
	resized.connect(_fit); _fit()
	if not GuestActivities.begin(activity_id):
		_modal("暂时无法进入",GuestActivities.last_error,[["返回手帐",_close]])
		return
	own_run=GuestActivities.active.id
	_update()
	if state().won: _result()
	else: _modal("一起试试看",GuestActivities.migration_notice+"\n"+_intro(),[["开始演示" if GuestActivities.active.mode=="demo" else "开始游戏",_start],["返回手帐",_close]])

func _rules_text() -> String:
	match activity_id:
		"milo_ferry": return "小船坐 1–2 人，不空船。\n有警察的一岸：\n警察人数 ≥ 囚犯人数。\n六人到对岸即可完成。"
		"ada_watch_memory": return "拖动组件入槽，空格旋转。\n把左侧发条接到右侧目标。\n铆钉件固定，Z 撤回，H 提示。"
	return "把货箱推到黄铜备货位。\n一次只能推一箱，不能拉。\n方向键移动，Z 撤回，H 提示。"

func _intro() -> String:
	var lines: Dictionary={"milo_ferry":"雨后旧桥停用。三名警察和三名囚犯都要去对岸。\n陪米洛用木偶复核渡河安排：拖动上船，空格开船。\n有警察的一岸，警察少于囚犯会发生暴动；无警察的一岸不判暴动。\n失败后可重试这一趟；Z 撤回，H 提示。", "ada_watch_memory":"艾达终于给自己留了一个下午。\n用组件把发条接到右侧目标，让怀表重新走起来。\n拖动组件，选中或拖着时空格旋转；Z 撤回，H 提示。\n三段拼图，不限时，最后按空格或拖表冠上弦。", "hank_lantern":"报纸从我出门那儿写起，可灯不是自己亮的。\n陪老霍克把灯、油和绳的货箱推到黄铜备货位。\n五关逐渐增加绕行与挪箱顺序，不限时。\n方向键 / WASD 移动，只能推一箱、不能拉箱。\n也可点击地面走路、拖箱推一格；Z 撤回，H 提示，R 重来。"}
	return str(lines[activity_id])+ ("\n\n当前为演示：不推进剧情、不发放奖励。" if GuestActivities.active.mode=="demo" else "\n\n正式首通：专属配方＋3 点研发灵感。")

func _style(fill: Color) -> StyleBoxFlat:
	var s:=StyleBoxFlat.new(); s.bg_color=fill; s.border_color=Color("98713d"); s.set_border_width_all(2); s.set_corner_radius_all(10); return s

func _label(parent: Node, rect: Rect2, text: String, px: int) -> Label:
	var l:=Label.new(); l.position=rect.position; l.size=rect.size; l.text=text; l.add_theme_font_override("font",FONT); l.add_theme_font_size_override("font_size",px); l.add_theme_color_override("font_color",Color("49321f")); l.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART; l.mouse_filter=Control.MOUSE_FILTER_IGNORE; parent.add_child(l); return l

func _button(parent: Node, rect: Rect2, text: String, action: Callable) -> Button:
	var b:=Button.new(); b.position=rect.position; b.size=rect.size; b.text=text; b.focus_mode=Control.FOCUS_NONE; b.add_theme_font_override("font",FONT); b.add_theme_font_size_override("font_size",22)
	for mode in ["normal","hover","pressed"]: b.add_theme_stylebox_override(mode,_style(Color("63462e") if mode=="normal" else Color("977444")))
	b.add_theme_color_override("font_color",Color("fff0cf")); b.pressed.connect(action); parent.add_child(b); return b

func _fit() -> void:
	var factor:=minf(size.x/1600,size.y/900); surface.scale=Vector2.ONE*factor; surface.position=(size-Vector2(1600,900)*factor)*.5

func _clear_modal() -> void:
	if is_instance_valid(overlay): surface.remove_child(overlay); overlay.queue_free(); overlay=null

func _modal(title: String, body: String, buttons: Array) -> void:
	_clear_modal()
	overlay=Panel.new(); overlay.size=Vector2(1600,900); overlay.add_theme_stylebox_override("panel",_style(Color(0.12,.07,.03,.72))); surface.add_child(overlay)
	var p:=Panel.new(); p.position=Vector2(335,205); p.size=Vector2(930,480); p.add_theme_stylebox_override("panel",_style(Color("f5e5c7"))); overlay.add_child(p)
	_label(p,Rect2(38,25,850,60),title,34); _label(p,Rect2(38,100,850,273),body,24)
	for i in range(buttons.size()): _button(p,Rect2(38+i*420,397,390,56),buttons[i][0],buttons[i][1])

func _start() -> void:
	_clear_modal(); playing=true; paused=false
	audio.suspend(false)
	_update()

func _update() -> void:
	if GuestActivities.active.is_empty(): return
	var s:=state()
	mode_label.text=("演示模式 · 不发奖" if GuestActivities.active.mode=="demo" else "正式邀请 · 首通获得专属配方与灵感")+"   /   酒馆时间暂停，半成品保留"
	match activity_id:
		"milo_ferry":
			progress_label.text="航行 %d 趟 · 对岸 %d / 6 人" % [s.moves.size(),6-int(s.left_p)-int(s.left_d)-(int(sail_load[0])+int(sail_load[1]) if sailing>0 and failure_outcome.is_empty() and int(s.side)==1 else 0)]
			hint_label.text="拖动或点击人物上船 · 空格开船 · 右键／Z 撤回一趟 · H 提示"
		"ada_watch_memory":
			if s.get("model")!=2: return
			progress_label.text="第 %d / 3 段 · %s" % [int(s.stage)+1,Rules.Watch.level(int(s.stage)).name]
			if Rules.Watch.solved(int(s.stage),s.pieces):
				hint_label.text="机芯接通了 · 空格进入下一段" if s.stage<2 else "秒针与摆轮已接通 · 拖动表冠或按空格上弦 %d / 4" % s.wind
			else: hint_label.text="拖动组件入槽 · 点击选中 / 拖着时空格旋转 · Z 撤回 · H 提示\n把左侧发条接到右侧目标，带铆钉的组件不可移动。"
		"hank_lantern":
			if s.get("model")!=2: return
			progress_label.text="第 %d / %d 关 · 备妥 %d / %d · 推动 %d 次" % [int(s.stage)+1,Rules.Crates.stage_count(s),Rules.Crates.filled(s),s.boxes.size(),s.pushes]
			if Rules.Crates.solved(s): hint_label.text="物资备妥了，听老霍克说几句……随后自动继续。"
			elif Rules.Crates.cornered(s): hint_label.text="这只箱子进入了送不到备货位的角落。按 Z 撤回几步，还来得及。"
			else: hint_label.text="方向键 / WASD 移动 · 点击空地走过去 · 拖箱推一格 · Z 撤回 · H 提示 · R 重来\n一次只推一箱，不能拉；把物资送到黄铜备货位。"
	board.queue_redraw()

func act(kind: String, payload: Dictionary={}) -> bool:
	if not playing or paused or is_instance_valid(overlay): return false
	if not GuestActivities.action(kind,payload): hint_label.text=GuestActivities.last_error; audio.cue("reject"); board.reject_time=.2; return false
	_update()
	if state().won:
		if activity_id=="milo_ferry": end_pending=true
		else: audio.cue("success"); _result()
	return true

func select_person(kind: int) -> void:
	if not playing or paused or is_instance_valid(overlay) or sailing>0: return
	var s:=state(); var available:=int(s.left_p if kind==0 else s.left_d)
	if s.side==1: available=3-available
	if selection[0]+selection[1]>=2: hint_label.text="两个载位已经坐满，点击船上人物可下船。"; return
	if selection[kind]>=available: return
	selection[kind]+=1; audio.cue("place"); board.landing=.28; board.queue_redraw()

func remove_person(kind: int) -> void:
	if sailing<=0 and selection[kind]>0: selection[kind]-=1; audio.cue("place"); board.queue_redraw()

func _cross() -> void:
	if sailing>0 or not playing or paused or is_instance_valid(overlay): return
	var side:=int(state().side); var load_pair:=selection.duplicate()
	failure_outcome=Rules.crossing_failure(state(),int(selection[0]),int(selection[1]))
	if not failure_outcome.is_empty():
		selection=[0,0]; sail_from=side; sail_load=load_pair; sailing=.85; audio.cue("water")
		hint_label.text="船离开了码头……看看这趟安排会发生什么。"
		return
	if act("cross",{"p":selection[0],"d":selection[1]}):
		selection=[0,0]; sail_from=side; sail_load=load_pair; sailing=.85; audio.cue("water"); _update()

func _undo() -> void:
	if sailing>0: return
	if activity_id=="hank_lantern":
		crate_queue=[]; crate_queued_direction=""; board.finish_motion(); board.clear_feedback(); crate_hint_search={}
	if act("undo"): selection=[0,0]; board.selected=-1; audio.cue("place"); board.queue_redraw()

func _hint() -> void:
	if not act("hint"): return
	if activity_id=="ada_watch_memory":
		var next:=Rules.Watch.hint(state()); board.selected=int(next.get("piece",-1))
		if next.action=="move": hint_label.text="已圈出组件 %d：%s" % [board.selected+1,"先放回右侧零件盘，腾出目标槽。" if next.cell<0 else "放入第 %d 行、第 %d 列。" % [int(next.cell)/int(Rules.Watch.level(int(state().stage)).width)+1,int(next.cell)%int(Rules.Watch.level(int(state().stage)).width)+1]]
		elif next.action=="rotate": hint_label.text="已圈出组件 %d，按空格转一档，观察边缘接点。" % [board.selected+1]
		else: hint_label.text="接通了，松开组件后按空格继续。"
		return
	if activity_id=="hank_lantern":
		crate_queue=[]; crate_queued_direction=""
		crate_hint_key=_crate_position_key()
		crate_hint_search=Rules.Crates.hint_search(state())
		hint_label.text="老霍克正在看看哪条路能腾出来……你仍可继续移动，换位后会取消这次提示。"
		return

	var pair:=Rules.hint(state())
	if not pair.is_empty(): hint_label.text="可以试试这趟：%d 名警察＋%d 名囚犯。记得安排回船。" % [pair[0],pair[1]]

func _assist() -> void:
	if activity_id=="milo_ferry": return
	if act("assist"): hint_label.text="辅助已开启，正式首通奖励不受影响。"

func watch_space() -> void:
	if activity_id!="ada_watch_memory" or state().get("model")!=2: return
	var s:=state()
	if board.held>=0:
		if act("rotate",{"piece":board.held}): audio.cue("rotate")
	elif Rules.Watch.solved(int(s.stage),s.pieces):
		if act("next" if s.stage<2 else "wind"):
			board.selected=-1; audio.cue("rotate"); board.pulse=.4
	elif board.selected>=0:
		if act("rotate",{"piece":board.selected}): audio.cue("rotate")
	else: hint_label.text="先点选组件，再按空格旋转；也可以拖着组件旋转。"

func _process(delta: float) -> void:
	if not is_instance_valid(board): return
	if crate_story_active:
		if playing and application_focused and not paused:
			crate_story_remaining=maxf(0,crate_story_remaining-delta)
			crate_story_caption.text="%d 秒后自动%s" % [ceili(crate_story_remaining),"收好清单" if int(state().stage)==Rules.Crates.stage_count(state())-1 else "进入下一关"]
			if crate_story_remaining<=0: _complete_crate_story()
		board.queue_redraw(); return
	if not playing or paused or is_instance_valid(overlay): board.queue_redraw(); return
	board.advance(delta)
	if sailing>0:
		sailing=maxf(0,sailing-delta)
		if sailing==0:
			if not failure_outcome.is_empty(): _ferry_failure(); return
			audio.cue("dock"); board.landing=.3; _update()
			if end_pending: end_pending=false; audio.cue("success"); _result(); return
	if activity_id=="hank_lantern":
		if board.travel<=0 and Rules.Crates.solved(state()):
			_show_crate_story(); return
		_advance_crate_hint()
		if board.travel<=0:
			if not crate_queued_direction.is_empty():
				var d:=crate_queued_direction; crate_queued_direction=""; crate_move(d)
			elif not crate_queue.is_empty(): crate_move(str(crate_queue.pop_front()),false)
	elif activity_id=="ada_watch_memory" and state().get("model")==2:
		if not Rules.Watch.connected(int(state().stage),state().pieces).is_empty():
			tick_time+=delta
			if tick_time>.55: tick_time=0; audio.cue("tick")
	ambient_time+=delta
	if ambient_time>4:
		ambient_time=0
		if activity_id!="ada_watch_memory": audio.cue("water" if activity_id=="milo_ferry" else "wind")
	board.queue_redraw()

func _crate_position_key() -> String:
	return str(state().get("layout_version",1))+":"+str(state().stage)+":"+Rules.Crates.key(int(state().player),state().boxes)
func _advance_crate_hint() -> void:
	if crate_hint_search.is_empty(): return
	if crate_hint_key!=_crate_position_key(): crate_hint_search={}; return
	if not Rules.Crates.advance_hint(crate_hint_search): return
	var direction: String=crate_hint_search.answer
	crate_hint_search={}
	if direction=="undo": hint_label.text="这条路已经堵住了。试试 Z 撤回最近几步，或 R 重来本关。"
	elif direction=="next": hint_label.text="已备妥，按空格继续。"
	elif direction=="unknown": hint_label.text="这次暂时没找到完整路线。先给箱后留出通道，必要时 Z 撤回；并不代表这一局无解。"
	else:
		hint_label.text="脚下已标出方向：先向%s走一格，再观察从哪侧推。" % {"U":"上","D":"下","L":"左","R":"右"}[direction]
		board.hint_direction=direction; board.hint_life=6
		board.queue_redraw()

func crate_move(direction: String, manual:=true) -> void:
	if activity_id!="hank_lantern" or not playing or paused or is_instance_valid(overlay): return
	if manual: crate_queue=[]
	if board.travel>0:
		if manual: crate_queued_direction=direction
		return
	var before:=state().duplicate(true)
	if act("move",{"direction":direction}):
		board.animate_move(before,state())
		audio.cue("place" if state().pushes>before.pushes else "step")
		if state().pushes>before.pushes:
			for i in range(state().boxes.size()):
				if state().boxes[i]!=before.boxes[i]: audio.cue(["crate_lamp","crate_oil","crate_rope"][i%3])
		if Rules.Crates.filled(state())>Rules.Crates.filled(before): audio.cue("crate_ready")
	else: crate_queue=[]; crate_queued_direction=""

func crate_walk_to(cell: int) -> void:
	if board.travel>0 or not playing or paused or is_instance_valid(overlay): return
	crate_queued_direction=""; crate_queue=Rules.Crates.walk_path(state(),cell)
	if crate_queue.is_empty() and cell!=int(state().player): hint_label.text="到不了那里，先把挡路的货箱挪开。"

func crate_drag_push(index: int, direction: String) -> void:
	if board.travel>0 or not playing or paused or is_instance_valid(overlay): return
	var cfg:=Rules.Crates.config_for(state()); var dir: Vector2i=Rules.Crates.DIRS[direction]
	var cell:=int(state().boxes[index]); var behind: int=cell-dir.y*cfg.width-dir.x
	var path:=Rules.Crates.walk_path(state(),behind)
	if behind!=int(state().player) and path.is_empty(): hint_label.text="需要先绕到箱子的另一侧，不能隔墙推箱。"; audio.cue("reject"); return
	var attempt:=Rules.Crates.step(cfg,behind,state().boxes,direction)
	if not attempt.ok: hint_label.text=attempt.message; audio.cue("reject"); return
	crate_queue=path; crate_queue.append(direction); crate_queued_direction=""

func _show_crate_story() -> void:
	if crate_story_active or state().won: return
	crate_queue=[]; crate_queued_direction=""; crate_hint_search={}; board.cancel_drag()
	var line: String=Rules.Crates.LINES[int(state().stage)]
	crate_story_remaining=clampf(float(line.length())*.13,4.5,8.0)
	_modal("老霍克 · 这一趟备妥了",line,[])
	crate_story_caption=_label(overlay.get_child(0),Rect2(38,397,850,56),"稍后自动继续",22)
	crate_story_active=true

func _complete_crate_story() -> void:
	crate_story_active=false; _clear_modal()
	if not crate_next():
		# Keep the completed, saved board intact if advancing cannot be saved.
		_modal("这关已完成，进度暂未保存",GuestActivities.last_error,[["重试保存并继续",_complete_crate_story],["返回手帐",_close]])

func crate_next() -> bool:
	if board.travel>0: return false
	crate_queue=[]; crate_queued_direction=""
	if not act("next"): return false
	board.finish_motion(); board.clear_feedback(); crate_hint_search={}
	return true

func crate_reset_prompt() -> void:
	if not playing or paused or is_instance_valid(overlay) or state().moves.is_empty(): return
	crate_queue=[]; crate_queued_direction=""; board.finish_motion(); paused=true
	_modal("重新整理这一关？","前面完成的关卡会保留；当前关的人物和货箱回到起点。",[["重来本关",_crate_reset],["继续整理",_resume]])

func _crate_reset() -> void:
	_resume(); act("reset"); board.finish_motion(); board.clear_feedback(); crate_hint_search={}

func _ferry_failure() -> void:
	playing=false; failure_shown=true; _clear_modal(); audio.cue("reject")
	overlay=Panel.new(); overlay.size=Vector2(1600,900); overlay.add_theme_stylebox_override("panel",_style(Color("1e1712"))); surface.add_child(overlay)
	var cg:=TextureRect.new(); cg.expand_mode=TextureRect.EXPAND_IGNORE_SIZE; cg.texture=load("res://assets/activities/v3/milo-riot.png"); cg.size=Vector2(1600,900); cg.mouse_filter=Control.MOUSE_FILTER_IGNORE; overlay.add_child(cg)
	cg.modulate.a=0; create_tween().tween_property(cg,"modulate:a",1.0,.3)
	var paper:=Panel.new(); paper.position=Vector2(120,606); paper.size=Vector2(1360,260); paper.add_theme_stylebox_override("panel",_style(Color("f5e5c7"))); overlay.add_child(paper)
	_label(paper,Rect2(28,12,1260,46),"囚犯暴动了",34)
	_label(paper,Rect2(28,69,1300,91),str(failure_outcome.message)+"\n米洛：别急，把木偶放回去。我们从这一趟重新安排。",23)
	_button(paper,Rect2(28,183,615,55),"重试这一趟 · 空格",_retry_ferry)
	_button(paper,Rect2(673,183,650,55),"返回手帐",_close)

func _retry_ferry() -> void:
	if not failure_shown: return
	failure_outcome={}; failure_shown=false; selection=[0,0]; sailing=0; board.cancel_drag(); _clear_modal(); playing=true; paused=false; audio.suspend(false); _update()
	hint_label.text="已回到出发前这一趟 · 重新选人上船，或按 H 看提示。"

func _result() -> void:
	playing=false
	var granted:=GuestActivities.claim()
	var demo: bool=GuestActivities.active.mode=="demo"
	var text: String={"milo_ferry":"三名警察与三名囚犯都安全到了对岸。米洛把回船的安排也写进了夹页。","ada_watch_memory":"怀表又走了起来。艾达笑了：今天还有时间慢慢调。","hank_lantern":"物资都备齐了。玛莎的灯与绳、齐恩的账本、车夫认出的路，还有霍克的接应。\n“这回，把名字也带上。”"}[activity_id]
	if demo: text+="\n\n演示完成，不改变剧情与奖励。正式条件："+GuestActivities.requirement_text(activity_id)+"。"
	elif granted:
		var recipe:=preload("res://scripts/research_data.gd").legendary(config.reward_recipe_id)
		text+="\n\n已收录配方《%s》＋%d 点研发灵感。\n可在图鉴查看、研发试调，再自行加入酒单。\n每个小游戏的首次通关奖励只领取一次。" % [recipe.name,int(config.reward_inspiration)]
	else: text+="\n\n"+GuestActivities.last_error
	_modal("一起完成了",text,[["返回手帐",_close],["再玩一局" if granted else "重试领取",_restart if granted else _result]])

func _restart() -> void:
	if not GuestActivities.begin(activity_id,true): hint_label.text=GuestActivities.last_error; return
	own_run=GuestActivities.active.id; selection=[0,0]; sailing=0; end_pending=false; failure_outcome={}; failure_shown=false; board.selected=-1; board.held=-1; board.watch_motion.reset(); board.angles.clear(); crate_queue=[]; crate_queued_direction=""
	if activity_id=="hank_lantern": board.finish_motion(); board.clear_feedback(); crate_hint_search={}
	_start()

func _pause() -> void:
	if not playing or is_instance_valid(overlay): return
	paused=true; crate_queue=[]; crate_queued_direction=""; board.cancel_drag(); audio.suspend(true)
	_modal("休息一下","酒馆时间保持暂停。返回手帐会保存正式局的当前进度。",[["继续",_resume],["返回手帐",_close]])

func _resume() -> void:
	_clear_modal(); paused=false; audio.suspend(false)

func _restore_clock() -> void:
	if not clock_restored: TimeManager.set_running(previous_running); clock_restored=true

func can_close() -> bool:
	if not GuestActivities.end(): hint_label.text=GuestActivities.last_error; return false
	_restore_clock(); return true

func _close() -> void:
	if can_close():
		crate_story_active=false; playing=false; close_requested.emit()

func _exit_tree() -> void:
	if GuestActivities.active.get("id","")==own_run: GuestActivities.checkpoint()
	_restore_clock()

func _unhandled_key_input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed: return
	if event.echo and (activity_id!="hank_lantern" or event.keycode not in [KEY_UP,KEY_DOWN,KEY_LEFT,KEY_RIGHT,KEY_W,KEY_A,KEY_S,KEY_D]): return
	if failure_shown:
		if event.keycode==KEY_SPACE: _retry_ferry()
		elif event.keycode==KEY_ESCAPE: _close()
		get_viewport().set_input_as_handled(); return
	if event.keycode==KEY_ESCAPE:
		if paused: _resume()
		else: _pause()
	elif playing and not paused and not is_instance_valid(overlay):
		if activity_id=="milo_ferry":
			match event.keycode:
				KEY_SPACE: _cross()
				KEY_Z: _undo()
				KEY_H: _hint()
				KEY_1: select_person(0)
				KEY_2: select_person(1)
		elif activity_id=="ada_watch_memory":
			if event.keycode==KEY_SPACE: watch_space()
			elif event.keycode==KEY_Z: _undo()
			elif event.keycode==KEY_H: _hint()
			elif event.keycode==KEY_R: act("reset"); board.selected=-1
		elif activity_id=="hank_lantern":
			match event.keycode:
				KEY_UP,KEY_W: crate_move("U")
				KEY_DOWN,KEY_S: crate_move("D")
				KEY_LEFT,KEY_A: crate_move("L")
				KEY_RIGHT,KEY_D: crate_move("R")
				KEY_Z: _undo()
				KEY_H: _hint()
				KEY_R: crate_reset_prompt()
	get_viewport().set_input_as_handled()


func _notification(what: int) -> void:
	if what==NOTIFICATION_APPLICATION_FOCUS_IN:
		application_focused=true
		if crate_story_active and is_instance_valid(audio): audio.suspend(false)
	if what==NOTIFICATION_APPLICATION_FOCUS_OUT and is_instance_valid(audio):
		application_focused=false
		_pause()
		audio.suspend(true)
