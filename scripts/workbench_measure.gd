extends Control
signal decided(ml: float, golden: bool)
const Evaluation=preload("res://scripts/workbench_evaluation.gd")
var recommended_ratio: float=Evaluation.config().dose_bands.recommended
var target := 30.0
var reference := true
var precise := true
var max_ml := 0.0
var progress := 0.0
var active := true
var _resume_processing:=false
var seconds := 4.0 # Practice tuning only, not final balancing.
var _font: Font = preload("res://assets/fonts/NotoSerifSC.ttf")

func _process(delta: float) -> void:
	if not active:
		return
	progress = minf(progress + delta / seconds, 1)
	queue_redraw()
	if progress >= 1:
		confirm()

func volume_limit() -> float:
	return max_ml if max_ml>0 else target*1.5

func current_ml() -> float:
	return clampf(snappedf(progress*volume_limit(),.1),0.0,volume_limit())

func confirm() -> void:
	if not active:
		return
	active = false
	var ml:=maxf(minf(.1,volume_limit()),current_ml())
	var golden := precise and target<=volume_limit() and absf(ml-target)<=target*recommended_ratio+.001
	decided.emit(ml,golden)

func _draw() -> void:
	if not precise:
		draw_string(_font,Vector2(25,40),"观察酒流与杯内液面，凭感觉停止",HORIZONTAL_ALIGNMENT_LEFT,-1,26,Color("352416"))
		draw_string(_font,Vector2(25,82),"直倒不显示刻度 · 停止后记录实际用量",HORIZONTAL_ALIGNMENT_LEFT,-1,21,Color("573c28"))
		return
	var r := Rect2(25,38,size.x-50,23)
	draw_rect(r,Color("3f3227"))
	if target<=volume_limit():
		var start:=maxf(0,target*(1-recommended_ratio)/volume_limit())
		var end:=minf(1,target*(1+recommended_ratio)/volume_limit())
		draw_rect(Rect2(r.position+Vector2(r.size.x*start,0),Vector2(r.size.x*(end-start),r.size.y)),Color("d4ad57"))
	for ml in range(0,ceili(volume_limit())+1,5):
		var x := r.position.x+r.size.x*ml/volume_limit()
		draw_line(Vector2(x,63),Vector2(x,75 if ml%10==0 else 69),Color("a88b60"),2)
		if ml%10==0: draw_string(_font,Vector2(x-9,94),str(ml),HORIZONTAL_ALIGNMENT_LEFT,-1,16,Color("573c28"))
	var needle := r.position.x+r.size.x*progress
	draw_line(Vector2(needle,27),Vector2(needle,64),Color("472d18"),4,true)
	draw_colored_polygon(PackedVector2Array([Vector2(needle-8,20),Vector2(needle+8,20),Vector2(needle,30)]),Color("472d18"))
	if target<=volume_limit():
		var goal:=r.position.x+r.size.x*target/volume_limit()
		draw_line(Vector2(goal,32),Vector2(goal,76),Color("af392e"),2.5,true)
	draw_string(_font,Vector2(25,22),"量酒器刻度 · 当前 %s ml" % WorkbenchSession.format_amount(current_ml()),HORIZONTAL_ALIGNMENT_LEFT,-1,21,Color("352416"))

	draw_string(_font,Vector2(size.x-260,22),("红线目标  %s ml" if reference else "自定目标  %s ml") % WorkbenchSession.format_amount(target),HORIZONTAL_ALIGNMENT_LEFT,-1,20,Color("573c28"))

func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		_resume_processing=is_processing()
		set_process(false)
	elif what == NOTIFICATION_APPLICATION_FOCUS_IN and active and _resume_processing:
		_resume_processing=false
		set_process(true)
