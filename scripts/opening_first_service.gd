extends Control
## A small cue on the normal home screen; real dialogue, ordering and settlement stay intact.
const UI=preload("res://scripts/opening_ui.gd")
var home: Control
var line: Label
var target: Control
var clock := 0.0

func _ready() -> void:
	name="FirstServiceGuide"
	size=Vector2(1600,900)
	mouse_filter=Control.MOUSE_FILTER_IGNORE
	z_index=50
	var panel:=UI.panel(self,Rect2(218,130,330,122))
	panel.mouse_filter=Control.MOUSE_FILTER_IGNORE
	line=UI.label(panel,Rect2(14,12,302,98),"",20,Color("f0dfb5"))
	line.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART

func _process(delta: float) -> void:
	clock+=delta
	visible=not home.arrival_presenting and Navigation.current_route==&"home" and (OpeningFlow.first_service_pending() or OpeningFlow.replay_world.active)
	target=null
	if not visible: return
	var prefix := "独立体验 · " if OpeningFlow.replay_world.active else ""
	if not OpeningFlow.first_service_pending():
		line.text=prefix+"可继续营业；设置中返回开始即可恢复原来的进度。"
	elif StoryDialogue.guest_id!="milo":
		line.text=prefix+"开业了。接下来，亲手为米洛做一杯酒。"
	elif StoryDialogue.phase=="story":
		line.text=prefix+"第一位客人 · 点击下方对话，听听他想喝什么。"
	else:
		line.text=prefix+"招待米洛 · 前往调酒台，选金汤力 → 制作 → 交给客人。"
		target=home.get_node("%OpenButton")
	queue_redraw()

func _draw() -> void:
	if not is_instance_valid(target) or not target.is_visible_in_tree(): return
	var rect: Rect2=get_global_transform_with_canvas().affine_inverse()*target.get_global_transform_with_canvas()*Rect2(Vector2.ZERO,target.size)
	var alpha:=.65 if OpeningFlow.reduced_motion else .55+.2*sin(clock*3)
	draw_rect(rect.grow(4),Color(1,.82,.45,alpha),false,3)
	var tip:=Vector2(rect.get_center().x,rect.position.y-5)
	draw_colored_polygon(PackedVector2Array([tip,tip+Vector2(-9,-14),tip+Vector2(9,-14)]),Color("dfbe7e"))
