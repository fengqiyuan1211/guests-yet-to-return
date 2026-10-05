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
	var render:=Appearance.rendering()
	for point in points:
		var depth := clampf((point.y-top)/maxf(1,bottom-top),0,1)
		var shaded := tint.lightened(float(render.surface_lighten)).lerp(tint.darkened(float(render.bottom_darken)),depth)
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
		var bands:=layer_bands(rect,qty,capacity,coupe,ice,mixing,ice_fraction,shape,layers,profiles,ripple)
		_draw_layer_body(canvas,body,rect,bands,center.y,rect.position.y+rect.size.y*bottom,phase,ripple)
		tint=color(layers.back().contents,profiles)
	var fizz:=Appearance.carbonation(contents,profiles)
	_draw_bubbles(canvas,body,rect,phase,fizz)
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
	_draw_surface_pops(canvas,surface,center,radii,phase,fizz)
	for band in range(2):
		var glint := PackedVector2Array()
		for i in range(25):
			var angle := lerpf(.14,.87,i/24.0)*PI
			glint.append(center+Vector2(cos(angle)*radii.x*(.89-band*.20),sin(angle)*radii.y*(.85-band*.25)))
		if mask.is_empty(): canvas.draw_polyline(glint,Color(.97,.96,.80,.24-band*.10),1.0,true)
		else:
			for segment in Geometry2D.intersect_polyline_with_polygon(glint,mask):
				if segment.size()>1: canvas.draw_polyline(segment,Color(.97,.96,.80,.24-band*.10),1.0,true)

## Visual-only diffuse interfaces; the authoritative layer amounts stay untouched.
static func layer_bands(rect: Rect2,qty: float,capacity: float,coupe: bool,ice: bool,mixing: bool,ice_fraction: float,shape: String,layers: Array,profiles: Dictionary={},motion:=0.0) -> Array:
	var total:=State.volume(State.aggregate(layers))
	if total<=0: return []
	var config: Dictionary=Appearance.rendering().layer_edges
	var bands: Array=[]
	var cumulative:=0.0
	var lower:=rect.position.y+rect.size.y*surface_fraction(0,capacity,coupe,ice,mixing,0,shape)
	for layer in layers:
		cumulative+=State.volume(layer.contents)
		var share:=cumulative/total
		var upper:=rect.position.y+rect.size.y*surface_fraction(qty*share,capacity,coupe,ice,mixing,ice_fraction*share,shape)
		bands.append({"top":upper,"height":maxf(.001,lower-upper),"tint":color(layer.contents,profiles),"width":0.0,"wave_fraction":float(config.wave_fraction)})
		lower=upper
	for i in range(bands.size()-1):
		var similarity:=1-State.distance(layers[i].contents,layers[i+1].contents)
		var desired:=rect.size.y*float(config.width_fraction)*(1+similarity*.7+clampf(motion,0,1)*.6)
		bands[i].width=minf(desired,minf(bands[i].height,bands[i+1].height)*float(config.max_neighbor_fraction))
	return bands

static func _boundary_y(band: Dictionary,x: float,rect: Rect2,phase: float,motion: float) -> float:
	var u: float=(x-rect.position.x)/maxf(1,rect.size.x)
	var wave:=sin(u*TAU+phase*.9)*.55+sin(u*PI*3-phase*1.3)*.25+(pow(u-.5,2)-.12)*1.2
	return float(band.top)+wave*float(band.width)*float(band.wave_fraction)*(1+clampf(motion,0,1))

static func layer_color_at(point: Vector2,rect: Rect2,bands: Array,phase:=0.0,motion:=0.0) -> Color:
	if bands.is_empty(): return Color.TRANSPARENT
	var tint: Color=bands[0].tint
	for i in range(bands.size()-1):
		var boundary:=_boundary_y(bands[i],point.x,rect,phase,motion)
		var width:=maxf(.00001,float(bands[i].width))
		if point.y>=boundary+width: return bands[i].tint
		if point.y<=boundary-width:
			tint=bands[i+1].tint
			continue
		var blend:=1-smoothstep(boundary-width,boundary+width,point.y)
		# Premultiplied linear-light blending keeps transparent interfaces free of white seams.
		var other: Color=bands[i+1].tint
		var alpha:=lerpf(tint.a,other.a,blend)
		var a:=tint.srgb_to_linear()
		var b:=other.srgb_to_linear()
		var mixed: Color=(a*a.a).lerp(b*b.a,blend)/maxf(.00001,alpha)
		tint=mixed.linear_to_srgb()
		tint.a=alpha
		return tint
	return tint

static func _draw_layer_body(canvas: CanvasItem,body: PackedVector2Array,rect: Rect2,bands: Array,top: float,bottom: float,phase: float,motion: float) -> void:
	if bands.is_empty(): return
	var ys: Array[float]=[rect.position.y,rect.end.y]
	for i in range(bands.size()-1):
		for j in range(9): ys.append(float(bands[i].top)+float(bands[i].width)*lerpf(-1.5,1.5,j/8.0))
	ys.sort()
	var config:=Appearance.rendering()
	var columns:=int(config.layer_edges.mesh_columns)
	for row in range(ys.size()-1):
		if ys[row+1]-ys[row]<.00001: continue
		for column in range(columns):
			var x0:=lerpf(rect.position.x,rect.end.x,column/float(columns))
			var x1:=lerpf(rect.position.x,rect.end.x,(column+1)/float(columns))
			var tile:=PackedVector2Array([Vector2(x0,ys[row]),Vector2(x1,ys[row]),Vector2(x1,ys[row+1]),Vector2(x0,ys[row+1])])
			for clipped in Geometry2D.intersect_polygons(tile,body):
				var local:=PackedVector2Array()
				var colors:=PackedColorArray()
				for point in clipped:
					local.append(point-clipped[0])
					var tint:=layer_color_at(point,rect,bands,phase,motion)
					var depth:=clampf((point.y-top)/maxf(1,bottom-top),0,1)
					var shaded:=tint.lightened(float(config.surface_lighten)).lerp(tint.darkened(float(config.bottom_darken)),depth)
					shaded.a=tint.a*lerpf(.80,1,depth)
					colors.append(shaded)
				var indices:=Geometry2D.triangulate_polygon(local)
				for k in range(0,indices.size(),3):
					canvas.draw_primitive(PackedVector2Array([clipped[indices[k]],clipped[indices[k+1]],clipped[indices[k+2]]]),PackedColorArray([colors[indices[k]],colors[indices[k+1]],colors[indices[k+2]]]),PackedVector2Array())

## Deterministic visual particles: phase animates them, never changes cup state.
static func bubble_samples(body: PackedVector2Array,rect: Rect2,phase: float,fizz: float) -> Array:
	var result: Array=[]
	if fizz<=.001 or body.size()<3: return result
	var config: Dictionary=Appearance.rendering().bubbles
	var bounds:=Rect2(body[0],Vector2.ZERO)
	for point in body: bounds=bounds.expand(point)
	var scale:=clampf(rect.size.x/180.0,.55,1.5)
	var count:=ceili(float(config.max_count)*sqrt(fizz))
	for i in range(count):
		var seed:=fmod(i*.61803398875+.19,1.0)
		var stagger:=fposmod(sin((i+1)*78.233)*43758.5453,1.0)
		var age:=fmod(phase/float(config.rise_seconds)*(.8+stagger*.5)+stagger,1.0)
		var radius:=lerpf(float(config.radius_min),float(config.radius_max),seed)*scale*(.65+.35*age)
		var point:=Vector2(bounds.position.x+bounds.size.x*(.1+.8*seed)+sin(phase*2+i*2.7)*2*scale,lerpf(bounds.end.y,bounds.position.y,age))
		var inside:=true
		for direction in [Vector2.ZERO,Vector2.UP,Vector2.DOWN,Vector2.LEFT,Vector2.RIGHT]:
			if not Geometry2D.is_point_in_polygon(point+direction*(radius+1),body): inside=false; break
		if inside: result.append({"point":point,"radius":radius,"alpha":float(config.opacity)*minf(1,age*8)*minf(1,(1-age)*12)})
	return result

static func _draw_bubbles(canvas: CanvasItem,body: PackedVector2Array,rect: Rect2,phase: float,fizz: float) -> void:
	for bubble in bubble_samples(body,rect,phase,fizz):
		var point: Vector2=bubble.point
		var radius: float=bubble.radius
		var alpha: float=bubble.alpha
		# Hollow refraction edge and offset highlight remain readable over wood or cola.
		canvas.draw_arc(point+Vector2(.5,.6),radius,0,TAU,16,Color(.16,.25,.28,alpha*.4),1,true)
		canvas.draw_arc(point,radius,0,TAU,16,Color(.88,.97,1,alpha*.7),.9,true)
		canvas.draw_arc(point,radius,PI*1.05,PI*1.65,7,Color(1,1,.94,alpha),1.35,true)
		canvas.draw_circle(point+Vector2(-radius*.3,-radius*.35),maxf(.4,radius*.22),Color(1,1,1,alpha*.8),true,-1,true)

static func _draw_surface_pops(canvas: CanvasItem,surface: PackedVector2Array,center: Vector2,radii: Vector2,phase: float,fizz: float) -> void:
	if fizz<=.001: return
	var count:=ceili(float(Appearance.rendering().bubbles.surface_pops)*sqrt(fizz))
	for i in range(count):
		var age:=fmod(phase*.9+i*.371,1.0)
		var origin:=center+Vector2(sin(i*4.7)*radii.x*.75,cos(i*2.3)*radii.y*.45)
		var ring:=PackedVector2Array()
		for j in range(25):
			var angle:=j*TAU/24
			ring.append(origin+Vector2(cos(angle),sin(angle)*.35)*(1+age*4))
		for segment in Geometry2D.intersect_polyline_with_polygon(ring,surface):
			if segment.size()>1: canvas.draw_polyline(segment,Color(.96,1,1,(1-age)*.55),.9,true)

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
		var shades: Array[Color]=[tint.darkened(.08),tint.lightened(.12),tint.lightened(.34),tint.lightened(.16),tint.darkened(.04)]
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
