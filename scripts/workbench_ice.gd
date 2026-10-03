extends RefCounted
## Procedural 2.5D ice: geometry and presentation only, no inventory or recipe mutation.
const Shape=preload("res://scripts/workbench_vessel_shape.gd")
const Liquid = preload("res://scripts/workbench_liquid.gd")

static func count(kind: String) -> int:
	return 4 if kind=="cube" else 10

static func displacement(age: float, kind: String) -> float:
	var arrived:=0.0
	for i in range(count(kind)):
		arrived+=smoothstep(.32+i*.055,.55+i*.055,age)
	return arrived/count(kind)

static func profile(rect: Rect2, coupe: bool, mixing: bool, shape:="") -> Dictionary:
	if not shape.is_empty():
		var p:=Shape.profile(shape)
		return {"center":rect.position.x+rect.size.x*p.center,"rim":rect.position.y+rect.size.y*p.walls.front().x,"floor":rect.position.y+rect.size.y*p.walls.back().x,"half":rect.size.x*Shape.radius(shape,p.walls.front().x)}
	return {"center":rect.position.x+rect.size.x*(.435 if mixing else .5),"rim":rect.position.y+rect.size.y*(.05 if coupe else .09),"floor":rect.position.y+rect.size.y*(.34 if coupe else (.80 if mixing else .89)),"half":rect.size.x*(.46 if coupe else (.36 if mixing else .35))}

static func cavity(rect: Rect2, coupe: bool, mixing: bool, entry: bool, metal:=false, shape:="") -> PackedVector2Array:
	if not shape.is_empty() and not metal: return Shape.cavity(rect,shape,entry)
	var p:=profile(rect,coupe,mixing,shape)
	var points:=PackedVector2Array()
	var top: float=p.rim-150 if entry else p.rim
	if metal:
		# Only the opening is visible. Ice behind opaque steel is occluded.
		points.append(Vector2(p.center-p.half,top))
		points.append(Vector2(p.center+p.half,top))
		for i in range(25):
			var a:=i*PI/24.0
			points.append(Vector2(p.center+cos(a)*p.half,p.rim+sin(a)*rect.size.y*.055))
		return points
	points.append(Vector2(p.center-p.half,top))
	points.append(Vector2(p.center+p.half,top))
	if coupe:
		for i in range(1,41):
			var y:=lerpf(p.rim,p.floor,i/40.0)
			points.append(Vector2(p.center+p.half*sqrt(maxf(0,(p.floor-y)/(p.floor-p.rim))),y))
		for i in range(1,41):
			var y:=lerpf(p.floor,p.rim,i/40.0)
			points.append(Vector2(p.center-p.half*sqrt(maxf(0,(p.floor-y)/(p.floor-p.rim))),y))
	else:
		var bottom_half: float=rect.size.x*(.25 if mixing else .30)
		for i in range(25):
			var a:=i*PI/24.0
			points.append(Vector2(p.center+cos(a)*bottom_half,p.floor+sin(a)*rect.size.y*.014))
	return points

static func pieces(rect: Rect2, kind: String, qty: float, capacity: float, coupe: bool, mixing: bool, age: float, phase: float, motion: float=0.0, portion:=0, ice_fraction:=-1.0, shape:="", piece_count:=-1) -> Array:
	var p:=profile(rect,coupe,mixing,shape)
	var rng:=RandomNumberGenerator.new()
	rng.seed=(72891 if kind=="cube" else 19871)+portion*173
	var result: Array=[]
	var total:=count(kind) if piece_count<0 else piece_count
	var columns:=2 if kind=="cube" else 3
	var base:=minf(rect.size.x*(.255 if kind=="cube" else .20),(p.floor-p.rim)*(.43 if kind=="cube" else .31))
	var surface:=rect.position.y+rect.size.y*Liquid.surface_fraction(qty,capacity,coupe,true,mixing,displacement(age,kind) if ice_fraction<0 else ice_fraction,shape)
	for i in range(total):
		var scale_factor:=rng.randf_range(.84,1.12)
		var side:=base*scale_factor
		var row: int=(i+portion*count(kind))/columns
		var column:=i%columns
		var x: float=p.center+(column-(columns-1)*.5)*base*.80+rng.randf_range(-.08,.08)*base
		var floor_y: float=p.floor-side*.58-row*base*.64
		var floating_y: float=surface+side*.35+row*base*(.48 if kind=="crushed" else .55)+rng.randf_range(-.08,.08)*base
		var y:=minf(floor_y,floating_y) if qty>.05 else floor_y
		y=maxf(p.rim+side*.22,y)
		if not shape.is_empty():
			var width:=rect.size.x*Shape.radius(shape,(y-rect.position.y)/rect.size.y)
			x=clampf(x,p.center-maxf(0,width-side*.33),p.center+maxf(0,width-side*.33))
		elif coupe:
			var width: float=p.half*sqrt(clampf((p.floor-y)/(p.floor-p.rim),.05,1))
			x=clampf(x,p.center-width+side*.33,p.center+width-side*.33)
		var angle:=rng.randf_range(-.42,.38)
		var local_age:=age-i*.055
		var travel_time:=.48+rng.randf_range(-.035,.035)
		var fall:=clampf(local_age/travel_time,0,1)
		var start_y: float=p.rim-48-i%3*12
		var point:=Vector2(x,lerpf(start_y,y,fall*fall))
		var impact:=maxf(0,local_age-travel_time)
		if fall>=1:
			# Damped contact bounce, followed by a subtle floating drift.
			point.y-=absf(sin(impact*15))*exp(-impact*6)*side*.22
			point.x+=sin(impact*17+i)*exp(-impact*5)*side*.12
			if qty>.05:
				point.y+=sin(phase*1.4+i*2.1)*side*.035
				point.x+=sin(phase*1.1+i*1.8)*side*.025
			point.x+=sin(phase*6+i)*base*.08*motion
			angle+=sin(phase*5+i)*.05*motion
		else:
			angle+=(1-fall)*rng.randf_range(-.65,.65)
		result.append({"point":point,"side":side,"angle":angle,"active":local_age>=0,"impact":impact,"landed":fall>=1,"surface":surface,"index":i,"shard":kind!="cube"})
	result.sort_custom(func(a,b): return a.point.y<b.point.y)
	return result

static func faces(piece: Dictionary) -> Array:
	var top:=PackedVector2Array([Vector2(-.46,-.23),Vector2(-.10,-.54),Vector2(.48,-.42),Vector2(.31,-.13)])
	var front:=PackedVector2Array([Vector2(-.46,-.23),Vector2(.31,-.13),Vector2(.34,.35),Vector2(.23,.46),Vector2(-.34,.37),Vector2(-.43,.25)])
	var side:=PackedVector2Array([Vector2(.31,-.13),Vector2(.48,-.42),Vector2(.54,.17),Vector2(.34,.35)])
	if piece.shard:
		top=PackedVector2Array([Vector2(-.48,-.12),Vector2(.06,-.55),Vector2(.48,-.04),Vector2(.10,.10)])
		front=PackedVector2Array([Vector2(-.48,-.12),Vector2(.10,.10),Vector2(.16,.40),Vector2(-.28,.23)])
		side=PackedVector2Array([Vector2(.10,.10),Vector2(.48,-.04),Vector2(.36,.30),Vector2(.16,.40)])
	var result: Array=[]
	for polygon in [front,side,top]:
		var vertices:=PackedVector2Array()
		for index in range(polygon.size()):
			var corner: Vector2=polygon[index]
			var start: Vector2=corner.lerp(polygon[(index+polygon.size()-1)%polygon.size()],.10)
			var end: Vector2=corner.lerp(polygon[(index+1)%polygon.size()],.10)
			for j in range(4):
				var t:=j/3.0
				var point:=start*(1-t)*(1-t)+corner*2*(1-t)*t+end*t*t
				vertices.append(piece.point+(point*piece.side).rotated(piece.angle))
		result.append(vertices)
	return result

static func _paint(canvas: CanvasItem, polygon: PackedVector2Array, mask: PackedVector2Array, tint: Color, surface: float, liquid: Color, wet: bool) -> void:
	for clipped in Geometry2D.intersect_polygons(polygon,mask):
		if clipped.size()<3: continue
		var colors:=PackedColorArray()
		for point in clipped:
			var submerged:=smoothstep(surface-2,surface+7,point.y) if wet else 0.0
			var color:=tint.lerp(Color(liquid.r,liquid.g,liquid.b,tint.a*.70),submerged*.42)
			colors.append(color)
		canvas.draw_polygon(clipped,colors)

static func _line(canvas: CanvasItem, points: PackedVector2Array, mask: PackedVector2Array, color: Color, width: float) -> void:
	for segment in Geometry2D.intersect_polyline_with_polygon(points,mask):
		if segment.size()>=2: canvas.draw_polyline(segment,color,width,true)

static func draw(canvas: CanvasItem, rect: Rect2, kind: String, contents: Dictionary, capacity: float, coupe: bool, mixing: bool, age: float, phase: float, motion:=0.0, metal:=false, portion:=0, ice_fraction:=-1.0, shape:="", piece_count:=-1) -> void:
	if kind not in ["cube","crushed"]: return
	var qty:=Liquid.volume(contents)
	var liquid:=Liquid.color(contents)
	var mask:=cavity(rect,coupe,mixing,age<1.7,metal,shape)
	var geometry:=pieces(rect,kind,qty,capacity,coupe,mixing,age,phase,motion,portion,ice_fraction,shape,piece_count)
	for piece in geometry:
		if not piece.active: continue
		var panels:=faces(piece)
		var shades: Array[Color]=[Color(.78,.91,.93,.34),Color(.34,.61,.66,.38),Color(.91,.97,.94,.49)]
		for index in range(panels.size()):
			_paint(canvas,panels[index],mask,shades[index],piece.surface,liquid,qty>.05)
		# Soft partial edge reflections avoid a white wireframe / plastic-box look.
		var edge:=PackedVector2Array()
		for local in [Vector2(-.40,-.25),Vector2(-.10,-.50),Vector2(.43,-.40)]: edge.append(piece.point+(local*piece.side).rotated(piece.angle))
		_line(canvas,edge,mask,Color(.94,.98,.94,.43),1.1)
		var lower:=PackedVector2Array()
		for local in [Vector2(-.32,.37),Vector2(.23,.44),Vector2(.34,.34)]: lower.append(piece.point+(local*piece.side).rotated(piece.angle))
		_line(canvas,lower,mask,Color(.23,.42,.43,.24),1.0)
		var frost:=PackedVector2Array()
		for local in [Vector2(-.24,-.13),Vector2(.03,-.07),Vector2(.14,.05),Vector2(.08,.24),Vector2(-.04,.30),Vector2(-.22,.20),Vector2(-.29,.04)]: frost.append(piece.point+(local*piece.side).rotated(piece.angle))
		_paint(canvas,frost,mask,Color(.86,.95,.93,.14),piece.surface,liquid,qty>.05)
		var glint:=PackedVector2Array()
		for local in [Vector2(-.35,-.17),Vector2(-.29,.16),Vector2(-.22,.26)]: glint.append(piece.point+(local*piece.side).rotated(piece.angle))
		_line(canvas,glint,mask,Color(1,.97,.86,.60),1.7)
		var crack:=PackedVector2Array()
		for local in [Vector2(.16,-.07),Vector2(-.02,.09),Vector2(.04,.22)]: crack.append(piece.point+(local*piece.side).rotated(piece.angle))
		_line(canvas,crack,mask,Color(.86,.97,.97,.26),.8)
		if kind=="cube":
			for i in range(3):
				var bubble: Vector2=piece.point+(Vector2(-.13+i*.12,.11+(i%2)*.08)*piece.side).rotated(piece.angle)
				if Geometry2D.is_point_in_polygon(bubble,mask):
					canvas.draw_circle(bubble,maxf(.6,piece.side*.024),Color(.96,1,.96,.44),false,.75,true)
		if qty>.05 and piece.landed and piece.impact<.55:
			var ring:=PackedVector2Array()
			var radius: float=piece.side*(.25+piece.impact*.8)
			for i in range(25):
				var a:=i*TAU/24
				ring.append(Vector2(piece.point.x,piece.surface)+Vector2(cos(a)*radius,sin(a)*radius*.18))
			_line(canvas,ring,mask,Color(.96,.96,.82,.3*(1-piece.impact/.55)),1.0)

static func preview(canvas: CanvasItem, rect: Rect2, kind: String) -> void:
	# The carried ice uses the same geometric pieces instead of the catalogue sprite.
	var mask:=PackedVector2Array([rect.position,Vector2(rect.end.x,rect.position.y),rect.end,Vector2(rect.position.x,rect.end.y)])
	var total:=3 if kind=="cube" else 7
	for i in range(total):
		var piece: Dictionary={"point":rect.get_center()+Vector2((i%3-1)*rect.size.x*.25,(i/3)*rect.size.y*.24),"side":rect.size.x*(.37 if kind=="cube" else .32),"angle":(i-1)*.14,"shard":kind=="crushed"}
		var index:=0
		for face in faces(piece):
			_paint(canvas,face,mask,[Color(.74,.89,.91,.48),Color(.34,.58,.61,.50),Color(.95,.98,.92,.65)][index],0,Color.WHITE,false)
			var outline: PackedVector2Array=face.duplicate()
			outline.append(outline[0])
			_line(canvas,outline,mask,Color(.98,1,.96,.8),1.3)
			index+=1
