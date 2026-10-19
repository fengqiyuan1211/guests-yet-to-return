extends Control
signal close_requested
const Model := preload("res://scripts/yellow_ski_model.gd")
const Canvas := preload("res://scripts/yellow_ski_canvas.gd")
const FONT := preload("res://assets/fonts/NotoSerifSC.ttf")
const STEP := 1.0/120.0

class SkiBar extends Control:
	var value := 0.0:
		set(next): value=next; queue_redraw()
	var fill_color := Color("d5a747")
	func _draw() -> void:
		var back:=StyleBoxFlat.new(); back.bg_color=Color("c8dcd6"); back.set_corner_radius_all(4)
		draw_style_box(back,Rect2(Vector2.ZERO,size))
		if value>0:
			var fill:=StyleBoxFlat.new(); fill.bg_color=fill_color; fill.set_corner_radius_all(4)
			draw_style_box(fill,Rect2(Vector2.ZERO,Vector2(size.x*clampf(value/100.0,0,1),size.y)))
var model := Model.new()
var world: Control
var surface: Control
var overlay: Panel
var distance_label: Label
var detail_label: Label
var notice_label: Label
var snow_label: Label
var score_label: Label
var trick_label: Label
var speed_label: Label
var help_label: Label
var boost_bar: SkiBar
var snow_bar: SkiBar
var course_bar: SkiBar
var pause_button: Button
var jump_button: Button
var sound: AudioStreamPlayer
var elapsed_bank := 0.0
var paused := false
var held_sources: Dictionary = {}
var queued_jump := false
var previous_running := true
var clock_restored := false
var best_distance := 0
var best_score := 0
var best_flips := 0
var record_saved := false
var record_error := ""
var save_path := "user://yellow_ski.cfg"
var heard_event := -1
var clips: Dictionary = {}
var closing := false

func _ready() -> void:
	previous_running=TimeManager.running
	TimeManager.set_running(false)
	SaloonAudio.acquire_scene(self,"yellow_ski")
	# Keep isolated test / demo saves alongside their explicitly selected session file.
	if not GameSession.save_path.begins_with("user://"):
		save_path=GameSession.save_path.get_base_dir().path_join("yellow_ski.cfg")
	_load_record()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter=Control.MOUSE_FILTER_STOP
	surface=Control.new(); surface.mouse_filter=Control.MOUSE_FILTER_IGNORE; add_child(surface)
	world=Canvas.new(); world.size=Vector2(1600,900); world.model=model; surface.add_child(world)
	model.reset(); world.reset_camera()
	var plate:=Panel.new(); plate.position=Vector2(24,24); plate.size=Vector2(345,116)
	plate.mouse_filter=Control.MOUSE_FILTER_IGNORE; plate.add_theme_stylebox_override("panel",_style(Color("f6efd8"),Color("c6b68c"))); surface.add_child(plate)
	_label(surface,Rect2(46,34,290,25),"雪 原 旅 途",16,Color("8e805c"))
	distance_label=_label(surface,Rect2(46,58,300,43),"",32,Color("27474c"))
	detail_label=_label(surface,Rect2(46,104,300,25),"",17,Color("60716a"))
	var stats:=Panel.new(); stats.position=Vector2(386,24); stats.size=Vector2(230,116)
	stats.mouse_filter=Control.MOUSE_FILTER_IGNORE; stats.add_theme_stylebox_override("panel",_style(Color("294d52"),Color("73928c"))); surface.add_child(stats)
	_label(surface,Rect2(408,35,188,25),"本次得分",16,Color("c0d2c6"))
	score_label=_label(surface,Rect2(408,59,188,39),"0",31,Color("ffdc8d"))
	trick_label=_label(surface,Rect2(408,103,188,26),"",17,Color("d7e6d7"))
	snow_label=_label(surface,Rect2(650,33,410,30),"",19,Color("294c52"))
	snow_bar=_bar(Rect2(650,73,350,10),Color("66968d"))
	speed_label=_label(surface,Rect2(650,96,390,27),"",17,Color("42676b"))
	boost_bar=_bar(Rect2(650,127,350,4),Color("e1ad51"))
	course_bar=_bar(Rect2(24,155,1552,5),Color("c89d4c"))
	pause_button=_button(surface,Rect2(1220,27,150,53),"暂停 Ⅱ",_toggle_pause)
	_button(surface,Rect2(1386,27,190,53),"返回手帐",_leave)
	jump_button=_button(surface,Rect2(1310,749,266,120),"轻点跳跃",func(): pass)
	jump_button.add_theme_font_size_override("font_size",27)
	jump_button.button_down.connect(func(): _hold("button",true))
	jump_button.button_up.connect(func(): _hold("button",false))
	help_label=_label(surface,Rect2(32,830,1170,38),"轻点跳跃  /  空中按住翻滚  /  松手收势    ·    空格 / 点击 / 触摸",20,Color("42666b"))
	notice_label=_label(surface,Rect2(440,192,720,60),"",30,Color("294c52"))
	notice_label.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
	sound=AudioStreamPlayer.new(); sound.bus=&"SFX" if AudioServer.get_bus_index(&"SFX")>=0 else &"Master"; sound.volume_db=-15; add_child(sound)
	for entry in [["jump",420.0],["star",890.0],["flip",680.0],["crash",135.0],["won",1040.0],["lost",180.0]]: clips[entry[0]]=_tone(entry[1])
	resized.connect(_fit); _fit(); _sync(); _intro()

func _fit() -> void:
	if not is_instance_valid(surface): return
	var factor:=minf(size.x/1600,size.y/900)
	surface.scale=Vector2.ONE*factor
	surface.position=(size-Vector2(1600,900)*factor)*0.5

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO,size),Color("315e6b"))

func _style(fill: Color,border:=Color("9e7947")) -> StyleBoxFlat:
	var s:=StyleBoxFlat.new(); s.bg_color=fill; s.border_color=border
	s.set_border_width_all(2); s.set_corner_radius_all(14)
	s.shadow_color=Color(0.08,0.15,0.17,0.18); s.shadow_size=7; s.shadow_offset=Vector2(0,4)
	return s

func _label(parent: Node,rect: Rect2,text: String,px: int,color:=Color("354d53")) -> Label:
	var l:=Label.new(); l.position=rect.position; l.size=rect.size; l.text=text
	l.add_theme_font_override("font",FONT); l.add_theme_font_size_override("font_size",px); l.add_theme_color_override("font_color",color)
	l.mouse_filter=Control.MOUSE_FILTER_IGNORE; parent.add_child(l); return l

func _button(parent: Node,rect: Rect2,text: String,action: Callable) -> Button:
	var b:=Button.new(); b.position=rect.position; b.size=rect.size; b.text=text
	b.add_theme_font_override("font",FONT); b.add_theme_font_size_override("font_size",22)
	b.add_theme_color_override("font_color",Color("f9efd9")); b.add_theme_color_override("font_hover_color",Color.WHITE)
	for pair in [["normal","375b5b"],["hover","537b6f"],["pressed","243f46"],["disabled","899b94"]]: b.add_theme_stylebox_override(pair[0],_style(Color(pair[1])))
	b.add_theme_stylebox_override("focus",StyleBoxEmpty.new()); b.focus_mode=Control.FOCUS_NONE
	b.mouse_default_cursor_shape=Control.CURSOR_POINTING_HAND; b.pressed.connect(action); parent.add_child(b)
	return b

func _bar(rect: Rect2,color: Color) -> SkiBar:
	var bar:=SkiBar.new(); bar.position=rect.position; bar.size=rect.size; bar.fill_color=color
	bar.mouse_filter=Control.MOUSE_FILTER_IGNORE
	surface.add_child(bar); return bar

func _panel(title: String,body: String,width:=880.0,height:=540.0) -> void:
	_clear_overlay()
	overlay=Panel.new(); overlay.position=Vector2((1600-width)*.5,(900-height)*.5); overlay.size=Vector2(width,height)
	overlay.add_theme_stylebox_override("panel",_style(Color("f8efd8"),Color("ba9b62")))
	surface.add_child(overlay)
	_label(overlay,Rect2(38,24,width-76,24),"SNOWBOUND  /  山 下 有 间 酒 馆",15,Color("9b8052"))
	_label(overlay,Rect2(38,62,width-76,64),title,42,Color("2e5153"))
	var rule:=ColorRect.new(); rule.position=Vector2(38,142); rule.size=Vector2(width-76,2); rule.color=Color("cfbc91"); overlay.add_child(rule)
	var description:=_label(overlay,Rect2(38,166,width-76,height-265),body,23,Color("63736c"))
	description.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	jump_button.disabled=true; jump_button.hide()

func _intro() -> void:
	pause_button.disabled=true
	_panel("奶龙大冒险","趴好，牛来。我们下山。

01   轻点起跳，越过石头和倒木
02   腾空后按住，慢慢转过一整圈
03   松手收稳，漂亮落地就能加速

山下的酒馆，还有 2,000 米。",660,570)
	overlay.position=Vector2(880,205)
	_button(overlay,Rect2(38,466,584,68),"出发，去山下！    →",_start)
	help_label.text="最远 %d 米   ·   最高 %d 分" % [best_distance,best_score]

func _clear_overlay() -> void:
	if is_instance_valid(overlay): overlay.hide(); overlay.queue_free()
	overlay=null
	if is_instance_valid(jump_button): jump_button.show()

func _start() -> void:
	if model.state=="won" and GuestActivities.book().unlocks.has("yellow_ski") and not _claim_spoon():
		_finish()
		return
	_clear_overlay(); model.reset(); model.start(); world.reset_camera()
	paused=false; record_saved=false; heard_event=-1; elapsed_bank=0
	held_sources.clear(); queued_jump=false; jump_button.disabled=false; pause_button.disabled=false; pause_button.text="暂停 Ⅱ"
	_sync()

func _hold(source: String,pressed: bool) -> void:
	if not pressed:
		held_sources.erase(source); return
	if paused or model.state!="running" or is_instance_valid(overlay): return
	if held_sources.has(source): return
	if held_sources.is_empty(): queued_jump=true
	held_sources[source]=true

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index==MOUSE_BUTTON_LEFT:
		_hold("mouse",event.pressed); get_viewport().set_input_as_handled()
	elif event is InputEventScreenTouch:
		_hold("touch"+str(event.index),event.pressed); get_viewport().set_input_as_handled()

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index==MOUSE_BUTTON_LEFT:
		_hold("mouse",event.pressed); accept_event()
	elif event is InputEventScreenTouch:
		_hold("touch"+str(event.index),event.pressed); accept_event()

func _input(event: InputEvent) -> void:
	# Consume before Home's _unhandled_key_input so Escape pauses instead of leaving.
	if event is InputEventKey:
		if event.echo: return
		if event.pressed and event.keycode==KEY_ESCAPE:
			_toggle_pause(); get_viewport().set_input_as_handled(); return
		if event.keycode in [KEY_SPACE,KEY_UP,KEY_W]:
			_hold("key"+str(event.keycode),event.pressed); get_viewport().set_input_as_handled()
	# Releases must reach us even when the pointer has moved onto another UI control.
	if event is InputEventMouseButton and event.button_index==MOUSE_BUTTON_LEFT and not event.pressed:
		held_sources.erase("mouse"); held_sources.erase("button")
	elif event is InputEventScreenTouch and not event.pressed:
		held_sources.erase("touch"+str(event.index))

func _process(delta: float) -> void:
	if not is_instance_valid(world) or paused: return
	if model.state=="running":
		elapsed_bank+=minf(delta,0.1)
		while elapsed_bank>=STEP and model.state=="running":
			model.step(STEP,not held_sources.is_empty(),queued_jump)
			queued_jump=false; elapsed_bank-=STEP
		world.advance(minf(delta,.1)); _sync(); _sound_event()
		if model.state in ["won","lost"]: _finish()
	elif model.state=="ready": world.advance(minf(delta,.1))

func _sync() -> void:
	distance_label.text="%d  /  2,000 米" % model.distance()
	detail_label.text="雪星 %d    ·    最远 %d 米" % [model.stars,best_distance]
	score_label.text=str(model.score+model.distance())
	trick_label.text="连贯落地 ×%d" % model.combo if model.combo>0 else "翻滚 %d 次" % model.flips
	var gap: float=model.gap()
	snow_label.text="雪崩逼近  ·  越过障碍！" if gap<400 else "身后还有 %d 米" % maxi(0,int(gap/30))
	snow_label.add_theme_color_override("font_color",Color("a64736") if gap<400 else Color("294c52"))
	snow_bar.value=clampf(gap/1500.0*100,0,100)
	snow_bar.modulate=Color("edaa88") if gap<400 else Color.WHITE
	speed_label.text="顺风加速  ·  %d 米/秒" % int(model.speed/30) if model.boost>0 else "滑行 %d 米/秒" % int(model.speed/30)
	boost_bar.value=model.boost/3.1*100
	course_bar.value=model.x/model.LENGTH*100
	notice_label.text=model.notice if model.notice_time>0 else ""
	if model.state=="running":
		if model.grounded: jump_button.text="轻点跳跃
SPACE / 点击"
		elif not held_sources.is_empty(): jump_button.text="松手收势
准备落地"
		else: jump_button.text="按住翻滚
空中继续按住"
		help_label.text="轻点跳跃  /  空中按住翻滚  /  松手收势    ·    Esc 暂停"
		if not model.grounded and model.pending_turns>0:
			help_label.text="已经翻过 %d 圈，松手收稳后落地才计分。" % model.pending_turns

func _toggle_pause() -> void:
	if model.state!="running": return
	if paused: _resume(); return
	paused=true; held_sources.clear(); queued_jump=false; elapsed_bank=0; sound.stop()
	_panel("在雪地里歇一会儿","雪崩也会等你。\n\n松一松手，准备好后再出发。\n\n轻点跳跃 · 按住翻滚 · 松手收势",800,500)
	_button(overlay,Rect2(38,400,348,66),"继续滑",_resume)
	_button(overlay,Rect2(414,400,348,66),"从山顶重新出发",_start)
	pause_button.text="继续 ▶"

func _resume() -> void:
	_clear_overlay(); paused=false; elapsed_bank=0; held_sources.clear(); queued_jump=false
	jump_button.disabled=false; pause_button.text="暂停 Ⅱ"

func _finish() -> void:
	held_sources.clear(); queued_jump=false; elapsed_bank=0; pause_button.disabled=true
	_save_record()
	var total:=model.score+model.distance()
	var title:="到酒馆了！" if model.state=="won" else "它从雪里探出了头"
	var body:="我是奶龙。" if model.state=="won" else "牛还在。抖掉身上的雪，再来一次。"
	if model.state=="won":
		var already_owned := Supplies.is_owned("tool_yellow_bar_spoon")
		if _claim_spoon():
			body+="\n（它把一把长得像自己的吧勺塞给你。）\n传说吧勺「我是奶龙」"+("已在背包里。" if already_owned else "已收入背包。")
		else:
			body+="\n"+Supplies.last_error+" 返回时会再次尝试。"
	_panel(title,body+"\n\n"+record_error,880,550)
	if model.state=="won" and Supplies.is_owned("tool_yellow_bar_spoon"):
		var gift:=Sprite2D.new()
		gift.texture=Supplies.catalog.get_texture("tool_yellow_bar_spoon")
		gift.position=Vector2(785,78)
		gift.scale=Vector2.ONE*(125.0/gift.texture.get_height())
		overlay.add_child(gift)
	var metrics: Array=[["滑行距离",str(model.distance())+" 米"],["本次得分",str(total)],["翻滚落地",str(model.flips)+" 次"],["最长连续",str(model.max_combo)+" 次"]]
	for i in range(metrics.size()):
		var card:=Panel.new(); card.position=Vector2(38+i*204,280); card.size=Vector2(192,95)
		card.mouse_filter=Control.MOUSE_FILTER_IGNORE
		card.add_theme_stylebox_override("panel",_style(Color("e9dfc5"),Color("d2c19c"))); overlay.add_child(card)
		_label(card,Rect2(16,17,160,25),metrics[i][0],18,Color("758174"))
		_label(card,Rect2(16,48,160,39),metrics[i][1],28,Color("345b58"))
	_label(overlay,Rect2(38,392,800,29),"最佳 %d 分   ·   最远 %d 米" % [best_score,best_distance],20,Color("9a7542"))
	_button(overlay,Rect2(38,452,390,65),"再滑一次",_start)
	_button(overlay,Rect2(452,452,390,65),"返回手帐",_leave)

func _load_record() -> void:
	var file:=ConfigFile.new()
	if file.load(save_path)!=OK: return
	best_distance=clampi(int(file.get_value("best","distance",0)),0,2000)
	best_score=clampi(int(file.get_value("best","score",0)),0,1000000)
	best_flips=clampi(int(file.get_value("best","flips",0)),0,10000)

func _save_record() -> void:
	if record_saved: return
	record_saved=true
	best_distance=maxi(best_distance,model.distance()); best_score=maxi(best_score,model.score+model.distance()); best_flips=maxi(best_flips,model.flips)
	var file:=ConfigFile.new()
	file.load(save_path)
	file.set_value("legendary_spoon","migration_checked",true)
	file.set_value("best","distance",best_distance); file.set_value("best","score",best_score); file.set_value("best","flips",best_flips)
	var error:=file.save(save_path+".tmp")
	if error==OK: error=DirAccess.rename_absolute(save_path+".tmp",save_path)
	record_error="" if error==OK else "这次纪录没能保存，还可以继续玩。"

func _tone(hz: float) -> AudioStreamWAV:
	var wav:=AudioStreamWAV.new(); wav.format=AudioStreamWAV.FORMAT_16_BITS; wav.mix_rate=22050
	var bytes:=PackedByteArray(); var samples:=2205; bytes.resize(samples*2)
	for i in range(samples):
		var envelope:=sin(PI*i/samples)*pow(1-float(i)/samples,2)
		bytes.encode_s16(i*2,int(sin(TAU*hz*i/22050.0)*envelope*7000))
	wav.data=bytes; return wav

func _sound_event() -> void:
	if heard_event==model.event_serial: return
	heard_event=model.event_serial
	if clips.has(model.last_event): sound.stream=clips[model.last_event]; sound.play()

func _restore_clock() -> void:
	if clock_restored: return
	clock_restored=true; TimeManager.set_running(previous_running)

func _claim_spoon() -> bool:
	if model.state!="won" or model.distance()<2000: return false
	if not GuestActivities.book().unlocks.has("yellow_ski"):
		Supplies.last_error="收到它的正式邀请后通关，即可获得吧勺。"
		return false
	return Supplies.grant_activity_equipment("tool_yellow_bar_spoon","yellow_ski")

func _leave() -> void:
	if closing: return
	if model.state=="won" and GuestActivities.book().unlocks.has("yellow_ski") and not _claim_spoon():
		_finish()
		return
	closing=true; _restore_clock()
	if close_requested.get_connections().is_empty(): get_tree().change_scene_to_file("res://scenes/home.tscn")
	else: close_requested.emit()

func _exit_tree() -> void:
	_restore_clock()

func _notification(what: int) -> void:
	if what==NOTIFICATION_APPLICATION_FOCUS_OUT and is_inside_tree() and model.state=="running" and not paused: _toggle_pause()
