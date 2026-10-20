extends Control
## Reuses the production shop and workbench. Only lesson progress belongs here.
signal completed
const Prep=preload("res://scripts/opening_preparation.gd")
const UI=preload("res://scripts/opening_ui.gd")
var page: Control
var guide: Control
var message: Label
var busy:=false

func _ready() -> void:
	name="OpeningSupplyLesson"
	if not OpeningFlow.state.departure.has("lesson"):
		if not OpeningFlow.update_departure({"recipe":"gin_and_tonic","lesson":{"phase":"shop","accepted_drink":""}}):
			_error(OpeningFlow.last_error)
			return
	var phase: String=OpeningFlow.state.departure.lesson.phase
	if phase=="mixing": _mix.call_deferred()
	else: _shop.call_deferred()

func _clear() -> void:
	if is_instance_valid(page):
		remove_child(page)
		page.queue_free()
	page=null
	guide=null
	if is_instance_valid(message): message.queue_free()
	message=null

func _error(text: String) -> void:
	if not is_instance_valid(message):
		message=UI.label(self,Rect2(450,750,750,85),"",23,Color("fff0b5"))
		message.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
		message.z_index=100
	message.text=text

func _shop() -> void:
	if not OpeningFlow.update_departure({"lesson":{"phase":"shop","accepted_drink":OpeningFlow.state.departure.lesson.get("accepted_drink","")}}):
		_error(OpeningFlow.last_error)
		return
	_clear()
	page=load("res://scenes/harbor_shop.tscn").instantiate()
	page.opening_free_lesson=true
	page.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(page)
	page.close_requested.connect(_shop_back)
	var back: Button=page.find_child("BackButton",true,false)
	back.text="← 回工作台" if WorkbenchSession.state.session.get("opening_practice",false) else ("退出体验，返回开始" if OpeningFlow.replaying else "保存并返回开始")
	back.add_theme_font_size_override("font_size",18)
	guide=preload("res://scripts/opening_shop_guide.gd").new()
	guide.shop=page
	page.canvas.add_child(guide)
	guide.ready_to_mix.connect(_mix)

func _shop_back() -> void:
	var s: Dictionary=WorkbenchSession.state.session
	if s.get("opening_practice",false) or (guide.supply_report().ready and Relationships.state.flags.get("done:merchant_seed",false)):
		_mix()
	else:
		# Explicit exit only; purchases and dialogue cursors are already persisted.
		OpeningFlow.return_to_title()

func _mix() -> void:
	if busy: return
	var lesson: Dictionary=OpeningFlow.state.departure.lesson
	if not str(lesson.get("accepted_drink","")).is_empty():
		_complete()
		return
	var s: Dictionary=WorkbenchSession.state.session
	var ours: bool=s.get("opening_practice",false) and s.get("recipe",{}).get("id")=="gin_and_tonic"
	if not ours:
		if not Supplies.opening_purchase_report().ready:
			_shop()
			return
		if not s.is_empty() and s.status=="mixing" and not s.actions.is_empty():
			_clear()
			page=Control.new()
			page.size=size
			add_child(page)
			UI.backdrop(page)
			_error("桌上还有之前的半成品，已经为你保留。先完成它，再回来练金汤力。")
			var resume:=UI.button(page,Rect2(550,380,500,65),"继续之前的半成品",_resume_previous)
			resume.name="ResumePreviousCup"
			UI.button(page,Rect2(550,470,500,65),"保存并返回开始",OpeningFlow.return_to_title)
			return
		if not WorkbenchSession.command("opening-stock-select-"+str(WorkbenchSession.state.serial),str(s.get("id","")),"select_recipe",{"recipe_id":"gin_and_tonic","opening_practice":true}):
			_error(WorkbenchSession.last_error)
			return
	if not OpeningFlow.update_departure({"lesson":{"phase":"mixing","accepted_drink":""}}):
		_error(OpeningFlow.last_error)
		return
	_clear()
	page=load("res://scenes/workbench.tscn").instantiate()
	page.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(page)
	page.close_requested.connect(_shop)
	page.opening_practice_completed.connect(_accept)

func _resume_previous() -> void:
	_clear()
	page=load("res://scenes/workbench.tscn").instantiate()
	page.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(page)
	page.close_requested.connect(_shop)

func _accept() -> void:
	if busy: return
	var s: Dictionary=WorkbenchSession.state.session
	if not s.get("opening_practice",false) or s.status!="finished": return
	if not OpeningFlow.update_departure({"lesson":{"phase":"mixing","accepted_drink":str(s.result.drink_id)}}):
		_error(OpeningFlow.last_error)
		return
	_complete()

func _complete() -> void:
	if busy: return
	if not Prep.report("gin_and_tonic").ready:
		_shop()
		_error("这杯已确认。营业还需要再留一杯材料，跟着提示补齐后即可开业，无需重做。")
		return
	if not Prep.publish("gin_and_tonic"):
		_error(MenuCatalog.last_error)
		return
	if not OpeningFlow.update_departure({"node":"ready","recipe":"gin_and_tonic","merchant_met":true,"seed_heard":true,"lesson":{"phase":"complete","accepted_drink":OpeningFlow.state.departure.lesson.accepted_drink}}):
		_error(OpeningFlow.last_error)
		return
	busy=true
	completed.emit()
