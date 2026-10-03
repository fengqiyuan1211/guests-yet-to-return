extends RefCounted
## Curled, veined leaf geometry; display only, quantities remain in the session.
const Liquid=preload("res://scripts/workbench_liquid.gd")
const Ice=preload("res://scripts/workbench_ice.gd")

static func _point(t: float, across: float, length: float, variant: int) -> Vector2:
	var width:=pow(maxf(0,sin(t*PI)),.82)*length*.285
	var teeth:=.93+.07*cos(t*TAU*9)
	var ridge:=sin(t*PI)*length*(.07+.015*(variant%3))
	var curl: float=sin(t*PI)*absf(across)*length*.09+pow(t,5)*length*.09
	return Vector2(ridge+across*width*teeth,(.5-t)*length+curl)

static func _paint(canvas: CanvasItem, points: PackedVector2Array, colors: PackedColorArray) -> void:
	# Triangulate near the origin: tiny tip triangles lose precision at table coordinates.
	var local:=PackedVector2Array()
	for point in points: local.append(point-points[0])
	var indices:=Geometry2D.triangulate_polygon(local)
	for i in range(0,indices.size(),3):
		var triangle:=PackedVector2Array()
		var shades:=PackedColorArray()
		for j in range(3):
			triangle.append(points[indices[i+j]])
			shades.append(colors[0] if colors.size()==1 else colors[indices[i+j]])
		canvas.draw_primitive(triangle,shades,PackedVector2Array())

static func _polygon(canvas: CanvasItem, points: PackedVector2Array, colors: PackedColorArray, mask: PackedVector2Array) -> void:
	if mask.is_empty():
		_paint(canvas,points,colors)
		return
	var inside:=true
	for point in points:
		if not Geometry2D.is_point_in_polygon(point,mask): inside=false; break
	if inside: _paint(canvas,points,colors)
	else:
		for clipped in Geometry2D.intersect_polygons(points,mask):
			if clipped.size()>2: _paint(canvas,clipped,PackedColorArray([colors[0]]))

static func _line(canvas: CanvasItem, points: PackedVector2Array, color: Color, width: float, mask: PackedVector2Array) -> void:
	if mask.is_empty(): canvas.draw_polyline(points,color,width,true)
	else: Ice._line(canvas,points,mask,color,width)

static func leaf(canvas: CanvasItem, center: Vector2, length: float, angle:=0.0, squash:=1.0, variant:=0, wet:=0.0, mask:=PackedVector2Array()) -> void:
	var pose:=Transform2D(angle,Vector2(squash,1),0,center)
	var dark:=Color("243d29").lerp(Color("35554b"),wet*.35)
	var light:=Color("91aa62").lerp(Color("76926b"),wet*.3)
	var outline:=PackedVector2Array()
	for side in [-1.0,1.0]:
		for j in range(33):
			var t:=j/32.0 if side<0 else 1-j/32.0
			outline.append(pose*_point(t,side,length,variant))
	var shadow:=PackedVector2Array()
	for point in outline: shadow.append(point+Vector2(length*.03,length*.045))
	_polygon(canvas,shadow,PackedColorArray([Color(0.06,.12,.06,.22)]),mask)
	# Both halves rise towards the curved midrib, with unequal lighting and rolled edges.
	for side in [-1.0,1.0]:
		for j in range(32):
			for band in range(2):
				var polygon:=PackedVector2Array()
				var colors:=PackedColorArray()
				for uv in [Vector2(j/32.0,band*.5),Vector2((j+1)/32.0,band*.5),Vector2((j+1)/32.0,(band+1)*.5),Vector2(j/32.0,(band+1)*.5)]:
					polygon.append(pose*_point(uv.x,uv.y*side,length,variant))
					var shade:=clampf((.70 if side<0 else .38)+sin(uv.x*PI)*.13-uv.y*.28+.035*sin(j*2.7+variant),0,1)
					colors.append(dark.lerp(light,shade))
				# Base/tip quads can contain coincident points; use triangles there.
				if j==0: polygon.remove_at(3); colors.remove_at(3)
				elif j==31: polygon.remove_at(2); colors.remove_at(2)
				_polygon(canvas,polygon,colors,mask)
	var midrib:=PackedVector2Array()
	for j in range(25): midrib.append(pose*_point(j/24.0,0,length,variant))
	_line(canvas,midrib,Color(.65,.72,.40,.5),maxf(.65,length*.018),mask)
	for side in [-1.0,1.0]:
		for j in range(1,7):
			var t:=.10+j*.115
			var vein:=PackedVector2Array()
			for k in range(9):
				var u: float=k/8.0
				vein.append(pose*_point(t+u*.115,u*side*.91,length,variant))
			_line(canvas,vein,Color(.62,.72,.39,.32 if side<0 else .20),maxf(.45,length*.009),mask)
			for k in [3,5]:
				var u: float=k/8.0
				var twig:=PackedVector2Array([pose*_point(t+u*.115,u*side*.91,length,variant),pose*_point(t+u*.115+.055,(u+.13)*side,length,variant)])
				_line(canvas,twig,Color(.69,.76,.46,.22),maxf(.4,length*.006),mask)
	# Fine, irregular ridges give a matte leaf surface rather than a solid green icon.
	for i in range(25):
		var t:=.14+fmod(i*.137, .70)
		var across:=sin(i*7.13+variant)*.78
		var point:=pose*_point(t,across,length,variant)
		_line(canvas,PackedVector2Array([point,point+Vector2(.5,-.8)*length/50]),Color(.8,.81,.54,.17),.65,mask)
	_line(canvas,PackedVector2Array([pose*Vector2(0,length*.57),pose*_point(0,0,length,variant)]),Color("80905a"),maxf(.7,length*.023),mask)
	if wet>.1:
		var gleam:=PackedVector2Array()
		for j in range(9): gleam.append(pose*_point(.36+j*.029,-.29,length,variant))
		_line(canvas,gleam,Color(.89,.92,.73,.35*wet),maxf(.7,length*.018),mask)

static func in_vessel(canvas: CanvasItem, rect: Rect2, count: int, contents: Dictionary, capacity: float, coupe: bool, mixing: bool, ice_fraction: float, phase: float, ages: Array=[], motion:=0.0, metal:=false, shape:="") -> void:
	if count<=0: return
	var profile:=Ice.profile(rect,coupe,mixing,shape)
	var qty:=Liquid.volume(contents)
	var surface:=rect.position.y+rect.size.y*Liquid.surface_fraction(qty,capacity,coupe,ice_fraction>0,mixing,ice_fraction,shape)
	var length:=clampf(rect.size.x*.32,30,55)
	for i in range(mini(count,18)):
		var age: float=ages[i] if i<ages.size() else 10.0
		var entry:=1-smoothstep(0,.52,age)
		var a:=i*2.39996
		var spread:=sqrt((i%9+1)/10.0)
		var y: float=surface+length*(.22+(i%3)*.31) if qty>0 else profile.floor-length*.33-(i/6)*length*.24
		if metal: y=profile.rim+rect.size.y*.023
		y=clampf(y,profile.rim+length*.12,profile.floor-length*.21)
		var half: float=profile.half
		if not shape.is_empty(): half=rect.size.x*Liquid.Shape.radius(shape,(y-rect.position.y)/rect.size.y)
		elif coupe: half*=sqrt(clampf((profile.floor-y)/(profile.floor-profile.rim),.01,1))
		var x: float=profile.center+cos(a)*maxf(0,half-length*.55)*spread
		var point:=Vector2(x,y-entry*(48+i%3*5))
		if qty>0 and entry<.01:
			point+=Vector2(sin(phase*1.2+i)*.6,sin(phase*1.4+i*2)*.4)
			point+=Vector2(cos(phase*4+a)*4,sin(phase*4+a)*1.4)*motion
		var mask:=Ice.cavity(rect,coupe,mixing,entry>.01,metal,shape)
		leaf(canvas,point,length*(.87+(i%3)*.075),a*.58+entry*.7+sin(phase*4+i)*motion*.18,.65+(i%3)*.10,i,.65 if qty>0 else 0.0,mask)
