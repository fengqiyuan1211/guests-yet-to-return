extends RefCounted
## Visual recipe only; neither flavour scores nor alcohol content are inferred here.
const Shape=preload("res://scripts/workbench_vessel_shape.gd")
const Appearance=preload("res://scripts/workbench_liquid_appearance.gd")
const State=preload("res://scripts/workbench_liquid_state.gd")

static func volume(contents: Dictionary) -> float:
	var total := 0.0
	for amount in contents.values(): total += float(amount)
	return total

static func color(contents: Dictionary,profiles: Dictionary={}) -> Color:
	return Appearance.sample(contents,profiles).color

static func interpolate(before: Dictionary, after: Dictionary, fraction: float) -> Dictionary:
	var result := {}
	for id in before:
		result[id] = lerpf(float(before[id]),float(after.get(id,0)),fraction)
	for id in after:
		if not result.has(id): result[id] = float(after[id])*fraction
	return result

static func _fill(canvas: CanvasItem, points: PackedVector2Array, tint: Color, top: float, bottom: float, mask:=PackedVector2Array()) -> void:
	if not mask.is_empty():
		for clipped in Geometry2D.intersect_polygons(points,mask): _fill(canvas,clipped,tint,top,bottom)
		return
	if points.size()<3: return
	var colors := PackedColorArray()
	for point in points:
		var depth := clampf((point.y-top)/maxf(1,bottom-top),0,1)
		var shaded := tint.lightened(.08).lerp(tint.darkened(.18),depth)
		shaded.a = tint.a * lerpf(.80,1.0,depth)
		colors.append(shaded)
	var local:=PackedVector2Array()
	for point in points: local.append(point-points[0])
	var indices:=Geometry2D.triangulate_polygon(local)
	for i in range(0,indices.size(),3):
		var triangle:=PackedVector2Array()
		var shades:=PackedColorArray()
		for j in range(3):
			triangle.append(points[indices[i+j]])
			shades.append(colors[indices[i+j]])
		canvas.draw_primitive(triangle,shades,PackedVector2Array())

static func surface_fraction(qty: float, capacity: float, coupe: bool, ice: bool, mixing := false, ice_fraction := 1.0, shape := "") -> float:
	if not shape.is_empty(): return Shape.surface(shape,(qty+(40.0*ice_fraction if ice else 0.0))/maxf(1,capacity))
	var level := clampf((qty + (40.0*ice_fraction if ice else 0.0))/capacity,.04,.94)
	if coupe: level=sqrt(level)
	if mixing: return .80-.69*level
	return (.34 if coupe else .89)-(.29 if coupe else .77)*level

static func draw(canvas: CanvasItem, rect: Rect2, contents: Dictionary, capacity: float, coupe: bool, ripple: float, ice: bool, phase := 0.0, mixing := false, ice_fraction := 1.0, shape := "", layers: Array=[], profiles: Dictionary={}) -> void:
	var qty := volume(contents)
	if qty < .05: return
	var level := clampf((qty + (40.0*ice_fraction if ice else 0.0))/capacity,.04,.94)
	if coupe: level = sqrt(level)
	var bottom := .80 if mixing else (.34 if coupe else .89)
	var top := surface_fraction(qty,capacity,coupe,ice,mixing,ice_fraction,shape)
	var half_width := .46*sqrt(level) if coupe else lerpf(.31,.35,level)
	var center_x := .435 if mixing else .5
	if mixing: half_width=lerpf(.255,.36,level)
	if not shape.is_empty():
		bottom=float(Shape.profile(shape).walls.back().x)
		center_x=float(Shape.profile(shape).center)
		half_width=Shape.radius(shape,top)
	var center := rect.position+rect.size*Vector2(center_x,top)
	var radii := Vector2(rect.size.x*half_width,maxf(2.2,rect.size.y*.024))
	if not shape.is_empty(): radii.y=rect.size.y*Shape.depth(shape,top)
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
	if not shape.is_empty(): body=Shape.body(rect,shape,top)
	var mask:=Shape.cavity(rect,shape) if not shape.is_empty() else PackedVector2Array()
	var tint := color(contents,profiles)
	var layer_total:=State.volume(State.aggregate(layers))
	if layers.size()<2 or layer_total<=0:
		_fill(canvas,body,tint,center.y,rect.position.y+rect.size.y*bottom)
	else:
		var cumulative:=0.0
		var lower:=rect.end.y
		for i in range(layers.size()):
			cumulative+=State.volume(layers[i].contents)
			var share:=cumulative/layer_total
			var boundary:=surface_fraction(qty*share,capacity,coupe,ice,mixing,ice_fraction*share,shape)
			var upper:=rect.position.y+rect.size.y*boundary
			if i==layers.size()-1: upper=rect.position.y # Includes the curved meniscus.
			var band:=PackedVector2Array([Vector2(rect.position.x,upper),Vector2(rect.end.x,upper),Vector2(rect.end.x,lower),Vector2(rect.position.x,lower)])
			_fill(canvas,band,color(layers[i].contents,profiles),center.y,rect.position.y+rect.size.y*bottom,body)
			lower=upper
		tint=color(layers.back().contents,profiles)
	var surface := PackedVector2Array()
	for i in range(64):
		var angle := i*TAU/64.0
		var wave := (sin(angle*3+phase*3)*.4 + sin(angle*5-phase*2)*ripple*.6)*minf(1,radii.y*.25)
		surface.append(center+Vector2(cos(angle)*radii.x,sin(angle)*(radii.y+wave)))
	# Several translucent, rounded edges soften the silhouette at small game sizes.
	for pass_index in range(3,0,-1):
		var soft := PackedVector2Array()
		for point in surface:
			soft.append(center+(point-center)*Vector2(1+pass_index*.008,1+pass_index*.12))
		_fill(canvas,soft,Color(tint.r,tint.g,tint.b,.035),center.y-radii.y,center.y+radii.y,mask)
	_fill(canvas,surface,Color(tint.r,tint.g,tint.b,minf(.84,tint.a+.06)),center.y-radii.y,center.y+radii.y,mask)
	for band in range(2):
		var glint := PackedVector2Array()
		for i in range(25):
			var angle := lerpf(.14,.87,i/24.0)*PI
			glint.append(center+Vector2(cos(angle)*radii.x*(.89-band*.20),sin(angle)*radii.y*(.85-band*.25)))
		if mask.is_empty(): canvas.draw_polyline(glint,Color(.97,.96,.80,.24-band*.10),1.0,true)
		else:
			for segment in Geometry2D.intersect_polyline_with_polygon(glint,mask):
				if segment.size()>1: canvas.draw_polyline(segment,Color(.97,.96,.80,.24-band*.10),1.0,true)

static func _stream_point(start: Vector2, end: Vector2, t: float, phase: float) -> Vector2:
	# Horizontal momentum loses influence as gravity pulls the stream into the cup.
	var control:=Vector2(lerpf(start.x,end.x,.78),start.y+maxf(6,(end.y-start.y)*.06))
	var point:=start*(1-t)*(1-t)+control*2*(1-t)*t+end*t*t
	point.x+=sin(t*17-phase*8)*1.1*sin(PI*t)+sin(t*31-phase*13)*.35*sin(PI*t)
	return point

static func stream(canvas: CanvasItem, start: Vector2, end: Vector2, tint: Color, phase: float, flow:=1.0, tail:=0.0) -> void:
	var strength:=clampf(flow,0,1)
	var centers:=PackedVector2Array()
	var normals:=PackedVector2Array()
	var widths:=PackedFloat32Array()
	for i in range(49):
		var t:=i/48.0
		var point:=_stream_point(start,end,t,phase)
		var tangent:=_stream_point(start,end,minf(1,t+.01),phase)-_stream_point(start,end,maxf(0,t-.01),phase)
		centers.append(point)
		normals.append(Vector2(-tangent.y,tangent.x).normalized())
		# Uneven moving bulges, a broad throat and a gravity-thinned lower stream.
		var pulse:=.65*sin(t*24-phase*11)+.36*sin(t*43-phase*17)
		widths.append(maxf(.5,(lerpf(6.2,3.1,sqrt(t))+pulse)*sqrt(strength)))
	if strength>.015:
		var bands: Array=[-1.0,-.48,.12,.56,1.0]
		var shades: Array[Color]=[tint.darkened(.24),tint.lightened(.04),tint.lightened(.30),tint.lightened(.08),tint.darkened(.12)]
		for band in range(4):
			for index in range(48):
				var quad:=PackedVector2Array()
				var colors:=PackedColorArray()
				for corner in [Vector2i(index,band),Vector2i(index+1,band),Vector2i(index+1,band+1),Vector2i(index,band+1)]:
					quad.append(centers[corner.x]+normals[corner.x]*widths[corner.x]*float(bands[corner.y]))
					var c: Color=shades[corner.y]
					c.a=clampf(tint.a+.15,.32,.76)*strength
					colors.append(c)
				canvas.draw_primitive(quad,colors,PackedVector2Array())
		# Broken specular streaks travel down the ribbon instead of outlining a wire.
		for segment in range(4):
			var t:=fmod(phase*1.8+segment*.25,1.0)
			var shine:=PackedVector2Array()
			for j in range(5):
				var index:=clampi(roundi((t+j*.012)*48),0,48)
				shine.append(centers[index]+normals[index]*widths[index]*.2)
			canvas.draw_polyline(shine,Color(.98,.98,.88,.32*strength),.8,true)
	# The narrowing stream releases separate elongated drops when the vessel tips back.
	if tail>0:
		for i in range(4):
			var t:=tail*1.5-i*.14
			if t<=0 or t>=1: continue
			var point:=_stream_point(start,end,t,phase)
			var tangent:=(_stream_point(start,end,minf(1,t+.02),phase)-point).normalized()
			var across:=Vector2(-tangent.y,tangent.x)
			var drop:=PackedVector2Array()
			for j in range(20):
				var a:=j*TAU/20
				drop.append(point+across*cos(a)*1.5+tangent*sin(a)*(2.2+t*2.0))
			canvas.draw_colored_polygon(drop,Color(tint.r,tint.g,tint.b,.62))
	var impact:=maxf(strength,(1-tail)*.55 if tail>0 else 0)
	if impact<.02: return
	# Expanding ellipses, a small liquid mound and low ballistic splash droplets.
	for i in range(3):
		var age:=fmod(phase*2.1+i/3.0,1.0)
		var ring:=PackedVector2Array()
		for j in range(33):
			var a:=j*TAU/32
			ring.append(end+Vector2(cos(a),sin(a)*.26)*(3+age*14))
		canvas.draw_polyline(ring,Color(.94,.96,.84,(1-age)*.22*impact),1,true)
	for i in range(4):
		var t:=fmod(phase*2.6+i*.27,1.0)
		var side:=-1.0 if i%2==0 else 1.0
		var point:=end+Vector2(side*t*(6+i*1.4),-sin(t*PI)*(3+i*.7))
		canvas.draw_circle(point,.7+(1-t)*.65,Color(tint.lightened(.3),impact*(1-t)*.45),true,-1,true)

## Render-only interpolation; never feeds back into stock, cup amounts or saved layers.
static func display_layers(before: Array,after: Array,fraction: float) -> Array:
	if fraction>=1: return after.duplicate(true)
	if fraction<=0: return before.duplicate(true)
	var av:=State.volume(State.aggregate(before))
	var bv:=State.volume(State.aggregate(after))
	if av<=0: return after.duplicate(true)
	if bv<=0: return before.duplicate(true)
	var boundaries: Array[float]=[0.0,1.0]
	for stack in [before,after]:
		var total:=State.volume(State.aggregate(stack))
		var cumulative:=0.0
		for layer in stack:
			cumulative+=State.volume(layer.contents)/total
			var point:=clampf(cumulative,0,1)
			if not boundaries.has(point): boundaries.append(point)
	boundaries.sort()
	var result: Array=[]
	for i in range(boundaries.size()-1):
		var low:=boundaries[i]
		var high:=boundaries[i+1]
		if high-low<.000001: continue
		var a:=_composition_at(before,(low+high)*.5)
		var b:=_composition_at(after,(low+high)*.5)
		var contents:=interpolate(a,b,fraction)
		for id in contents: contents[id]*=(high-low)*lerpf(av,bv,fraction)
		result.append({"contents":contents})
	return result

static func _composition_at(stack: Array,point: float) -> Dictionary:
	var cursor:=point*State.volume(State.aggregate(stack))
	for layer in stack:
		var total:=State.volume(layer.contents)
		cursor-=total
		if cursor<=.000001 and total>0:
			var result: Dictionary=layer.contents.duplicate(true)
			for id in result: result[id]/=total
			return result
	return {}
