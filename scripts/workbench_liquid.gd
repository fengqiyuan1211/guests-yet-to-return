extends RefCounted
## Visual recipe only; neither flavour scores nor alcohol content are inferred here.
const COLORS := {
	"gin": Color(.86,.94,.94,.28), "vodka": Color(.90,.96,1.0,.25),
	"rum": Color(.94,.95,.83,.32), "lime": Color(.64,.79,.26,.80),
	"syrup": Color(.91,.65,.22,.66), "soda": Color(.74,.90,.97,.24)
}

static func volume(contents: Dictionary) -> float:
	var total := 0.0
	for amount in contents.values(): total += float(amount)
	return total

static func color(contents: Dictionary) -> Color:
	var total := volume(contents)
	if total <= 0: return Color.TRANSPARENT
	var weighted := Vector4.ZERO
	for id in contents:
		var c: Color = COLORS.get(id, Color(.9,.9,.85,.3))
		weighted += Vector4(c.r,c.g,c.b,c.a) * float(contents[id]) / total
	return Color(weighted.x,weighted.y,weighted.z,weighted.w)

static func interpolate(before: Dictionary, after: Dictionary, fraction: float) -> Dictionary:
	var result := {}
	for id in before:
		result[id] = lerpf(float(before[id]),float(after.get(id,0)),fraction)
	for id in after:
		if not result.has(id): result[id] = float(after[id])*fraction
	return result

static func _fill(canvas: CanvasItem, points: PackedVector2Array, tint: Color, top: float, bottom: float) -> void:
	var colors := PackedColorArray()
	for point in points:
		var depth := clampf((point.y-top)/maxf(1,bottom-top),0,1)
		var shaded := tint.lightened(.08).lerp(tint.darkened(.18),depth)
		shaded.a = tint.a * lerpf(.80,1.0,depth)
		colors.append(shaded)
	canvas.draw_polygon(points,colors)

static func surface_fraction(qty: float, capacity: float, coupe: bool, ice: bool, mixing := false) -> float:
	var level := clampf((qty + (40.0 if ice else 0.0))/capacity,.04,.94)
	if coupe: level=sqrt(level)
	if mixing: return .80-.69*level
	return (.34 if coupe else .89)-(.29 if coupe else .77)*level

static func draw(canvas: CanvasItem, rect: Rect2, contents: Dictionary, capacity: float, coupe: bool, ripple: float, ice: bool, phase := 0.0, mixing := false) -> void:
	var qty := volume(contents)
	if qty < .05: return
	var level := clampf((qty + (40.0 if ice else 0.0))/capacity,.04,.94)
	if coupe: level = sqrt(level)
	var bottom := .80 if mixing else (.34 if coupe else .89)
	var top := surface_fraction(qty,capacity,coupe,ice,mixing)
	var half_width := .46*sqrt(level) if coupe else lerpf(.31,.35,level)
	var center_x := .435 if mixing else .5
	if mixing: half_width=lerpf(.255,.36,level)
	var center := rect.position+rect.size*Vector2(center_x,top)
	var radii := Vector2(rect.size.x*half_width,maxf(2.2,rect.size.y*.024))
	var body := PackedVector2Array()
	# Curved rear meniscus connects to the rounded vessel wall, without a flat chord.
	for i in range(33):
		var angle := PI+i*PI/32.0
		body.append(center+Vector2(cos(angle)*radii.x,sin(angle)*radii.y))
	if coupe:
		for i in range(1,33):
			var h := level*(1.0-i/32.0)
			body.append(rect.position+rect.size*Vector2(.5+.46*sqrt(h),bottom-.29*h))
		for i in range(1,33):
			var h := level*i/32.0
			body.append(rect.position+rect.size*Vector2(.5-.46*sqrt(h),bottom-.29*h))
	else:
		for i in range(25):
			var angle := i*PI/24.0
			body.append(rect.position+rect.size*Vector2(center_x+(.25 if mixing else .30)*cos(angle),bottom+.022*sin(angle)))
	var tint := color(contents)
	if mixing: tint.a=maxf(tint.a,.42)
	_fill(canvas,body,tint,center.y,rect.position.y+rect.size.y*bottom)
	var surface := PackedVector2Array()
	for i in range(64):
		var angle := i*TAU/64.0
		var wave := sin(angle*3+phase*3)*.4 + sin(angle*5-phase*2)*ripple*.6
		surface.append(center+Vector2(cos(angle)*radii.x,sin(angle)*(radii.y+wave)))
	# Several translucent, rounded edges soften the silhouette at small game sizes.
	for pass_index in range(3,0,-1):
		var soft := PackedVector2Array()
		for point in surface:
			soft.append(center+(point-center)*Vector2(1+pass_index*.008,1+pass_index*.12))
		canvas.draw_colored_polygon(soft,Color(tint.r,tint.g,tint.b,.035))
	_fill(canvas,surface,Color(tint.r,tint.g,tint.b,minf(.84,tint.a+.06)),center.y-radii.y,center.y+radii.y)
	for band in range(2):
		var glint := PackedVector2Array()
		for i in range(25):
			var angle := lerpf(.14,.87,i/24.0)*PI
			glint.append(center+Vector2(cos(angle)*radii.x*(.89-band*.20),sin(angle)*radii.y*(.85-band*.25)))
		canvas.draw_polyline(glint,Color(.97,.96,.80,.24-band*.10),1.0,true)

static func stream(canvas: CanvasItem, start: Vector2, end: Vector2, tint: Color, phase: float) -> void:
	var centers := PackedVector2Array()
	var widths := PackedFloat32Array()
	# A tapered quadratic arc with small uneven edges gives a painted ribbon of liquid.
	var control := Vector2(lerpf(start.x,end.x,.8),start.y+12)
	for i in range(33):
		var t := i/32.0
		var point := start*(1-t)*(1-t)+control*2*(1-t)*t+end*t*t
		point.x += sin(t*13-phase*9)*.8*sin(t*PI)
		centers.append(point)
		widths.append(lerpf(2.6,1.1,t)+sin(t*17+phase*7)*.25)
	var left := PackedVector2Array()
	var right := PackedVector2Array()
	for i in range(centers.size()):
		var tangent := centers[mini(i+1,32)]-centers[maxi(i-1,0)]
		var normal := Vector2(-tangent.y,tangent.x).normalized()
		left.append(centers[i]+normal*widths[i])
		right.append(centers[i]-normal*widths[i])
	right.reverse()
	left.append_array(right)
	canvas.draw_colored_polygon(left,Color(tint.r,tint.g,tint.b,maxf(.42,tint.a)))
	canvas.draw_polyline(centers,Color(.97,.97,.88,.40),1.0,true)
	# A small curved impact ring ties the stream to the receiving vessel.
	canvas.draw_set_transform(end,0,Vector2(1,.28))
	canvas.draw_arc(Vector2.ZERO,5+sin(phase*9)*1.5,0,TAU,28,Color(tint.r,tint.g,tint.b,.34),1.3,true)
	canvas.draw_set_transform(Vector2.ZERO)
