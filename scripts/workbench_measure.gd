extends Control
signal decided(ml: int, golden: bool)
var target := 30
var progress := 0.0
var active := true
var seconds := 4.0 # Practice tuning only, not final balancing.
var _font: Font = preload("res://assets/fonts/NotoSerifSC.ttf")

func _process(delta: float) -> void:
	if not active:
		return
	progress = minf(progress + delta / seconds, 1)
	queue_redraw()
	if progress >= 1:
		confirm()

func confirm() -> void:
	if not active:
		return
	active = false
	var golden := progress >= .62 and progress <= .72
	var ml := target if golden else maxi(1,roundi(progress * target * 1.5))
	decided.emit(ml,golden)

func _draw() -> void:
	var r := Rect2(25,38,size.x-50,23)
	draw_rect(r,Color("3f3227"))
	draw_rect(Rect2(r.position+Vector2(r.size.x*.62,0),Vector2(r.size.x*.1,r.size.y)),Color("d4ad57"))
	for i in range(16):
		var x := r.position.x+r.size.x*i/15.0
		draw_line(Vector2(x,63),Vector2(x,72 if i%5==0 else 68),Color("a88b60"),2)
	var needle := r.position.x+r.size.x*progress
	draw_line(Vector2(needle,27),Vector2(needle,64),Color("f9e8ba"),4,true)
	draw_colored_polygon(PackedVector2Array([Vector2(needle-8,20),Vector2(needle+8,20),Vector2(needle,30)]),Color("f9e8ba"))
	draw_string(_font,Vector2(25,95),"少量",HORIZONTAL_ALIGNMENT_LEFT,-1,20,Color("d1b994"))
	draw_string(_font,Vector2(size.x-140,95),"过量 %d ml" % roundi(target*1.5),HORIZONTAL_ALIGNMENT_LEFT,-1,20,Color("d1b994"))
	draw_string(_font,Vector2(size.x*.5-90,22),"黄金用量  %d ml" % target,HORIZONTAL_ALIGNMENT_LEFT,-1,20,Color("f0d69c"))

func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		set_process(false)
	elif what == NOTIFICATION_APPLICATION_FOCUS_IN and active:
		set_process(true)
