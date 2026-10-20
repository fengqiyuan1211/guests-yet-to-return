extends Control
## Real story scenes on an isolated profile, with convenient jump controls.
const UI = preload("res://scripts/opening_ui.gd")
var page: Control
var toolbar: Control
var switching := false

func _ready() -> void:
	if not GameSession.save_path.begins_with("/tmp/prologue-cast-demo-"):
		push_error("Launch with tools/play_opening_characters.py to protect your save.")
		get_tree().quit(2)
		return
	DisplayServer.window_set_title("致未归的客人 · 序章立绘演示（独立存档）")
	var layer := CanvasLayer.new()
	layer.layer = 50
	add_child(layer)
	toolbar = Control.new()
	toolbar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(toolbar)
	var entries := [["从头播放","s01_00"],["同事甲","s01_young_01"],["同事乙","s01_young_03"],["年轻同事","s01_young_05"],["那位客人","s02_02"],["调酒师","s02_10"],["老管家","s06_00"],["投递员","recipient"],["老板娘","merchant"]]
	for i in entries.size():
		var target: String = entries[i][1]
		var button := UI.button(toolbar,Rect2(30+i*172,864,164,32),entries[i][0],func(): _jump(target),true)
		button.focus_mode=Control.FOCUS_NONE
		button.add_theme_font_size_override("font_size",18)
	resized.connect(_fit)
	_fit()
	_jump("merchant" if "--merchant" in OS.get_cmdline_user_args() else "s02_02")

func _fit() -> void:
	var factor := minf(size.x/1600.0,size.y/900.0)
	toolbar.scale=Vector2.ONE*factor
	toolbar.position=(size-Vector2(1600,900)*factor)*.5

func _jump(target: String) -> void:
	if switching: return
	switching=true
	if is_instance_valid(page):
		remove_child(page)
		page.queue_free()
	OpeningFlow.begin_story()
	if target in ["recipient","merchant"]:
		OpeningFlow.begin_tutorial()
		OpeningFlow.finish_tutorial(true)
		OpeningFlow.begin_departure()
		OpeningFlow.update_departure({"node":"recipient"})
		page=preload("res://scenes/opening_departure.tscn").instantiate()
	else:
		var index := OpeningFlow.node_index(target)
		OpeningFlow.advance(maxi(index,0))
		page=preload("res://scenes/opening_story.tscn").instantiate()
	add_child(page)
	if target=="merchant": page._start_conversation("merchant_intro",func(): pass)
	switching=false
