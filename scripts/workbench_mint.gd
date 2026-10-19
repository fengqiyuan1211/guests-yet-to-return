extends RefCounted
## Pixel leaf with the existing bending / bruising / tearing mesh and liquid clipping.
const Liquid=preload("res://scripts/workbench_liquid.gd")
const Ice=preload("res://scripts/workbench_ice.gd")
const TEXTURE=preload("res://assets/pixel_b/mint-leaf.svg")

static func _mesh_point(uv: Vector2,length: float,variant: int,flutter: float) -> Vector2:
	var cross_leaf:=uv.x-.5
	var along:=uv.y
	var curve:=sin(along*PI)
	return Vector2(cross_leaf*length*.71+curve*length*(.035*(variant%3-1)+flutter*.04), (along-.5)*length+absf(cross_leaf)*curve*length*.08)

static func _textured_triangle(canvas: CanvasItem,triangle: PackedVector2Array,uv: PackedVector2Array,tint: Color,mask: PackedVector2Array) -> void:
	var pieces: Array[PackedVector2Array]=[triangle]
	if not mask.is_empty():
		var contained:=true
		for point in triangle:
			if not Geometry2D.is_point_in_polygon(point,mask): contained=false; break
		if not contained: pieces=Geometry2D.intersect_polygons(triangle,mask)
	var basis:=Transform2D(triangle[1]-triangle[0],triangle[2]-triangle[0],triangle[0]).affine_inverse()
	for polygon in pieces:
		if polygon.size()<3: continue
		var coordinates:=PackedVector2Array()
		for point in polygon:
			var weights:=basis*point
			coordinates.append(uv[0]+(uv[1]-uv[0])*weights.x+(uv[2]-uv[0])*weights.y)
		# Clip fragments can be subpixel slivers: triangulate near the origin before drawing.
		var local:=PackedVector2Array()
		for point in polygon: local.append(point-polygon[0])
		var indices:=Geometry2D.triangulate_polygon(local)
		for i in range(0,indices.size(),3):
			canvas.draw_primitive(PackedVector2Array([polygon[indices[i]],polygon[indices[i+1]],polygon[indices[i+2]]]),PackedColorArray([tint]),PackedVector2Array([coordinates[indices[i]],coordinates[indices[i+1]],coordinates[indices[i+2]]]),TEXTURE)

static func _patch_uv(column: int,row: int,variant: int) -> Vector2:
	var x:=column/2.0
	var y:=row/6.0
	if column==1: x+=sin(row*2.7+variant)*.11
	if row>0 and row<6: y+=sin(column*3.1+row*1.9+variant)*.035
	return Vector2(x,y)

static func leaf(canvas: CanvasItem,center: Vector2,length: float,angle:=0.0,squash:=1.0,variant:=0,wet:=0.0,mask:=PackedVector2Array(),flutter:=0.0,water_tint:=Color.WHITE,work:=0.0) -> void:
	var bruise:=smoothstep(0,4,work)
	var tear:=smoothstep(3,9,work)
	var pose:=Transform2D(angle,Vector2(squash,lerpf(1,.85,bruise)),0,center)
	var tint:=Color.WHITE.lerp(water_tint.lightened(.55),wet*.16)
	tint=tint.darkened(bruise*.13)
	tint.a=1-wet*.10
	for row in range(6):
		for column in range(2):
			var uv:=PackedVector2Array([_patch_uv(column,row,variant),_patch_uv(column+1,row,variant),_patch_uv(column+1,row+1,variant),_patch_uv(column,row+1,variant)])
			var middle: Vector2=(uv[0]+uv[1]+uv[2]+uv[3])*.25
			var pivot:=_mesh_point(middle,length,variant,flutter)
			var seed:=variant*3.71+row*2.3+column*4.7
			var offset:=Vector2(sin(seed)*length*.20,cos(seed*1.37)*length*.16)*tear
			var points:=PackedVector2Array()
			for coordinate in uv:
				var local:=_mesh_point(coordinate,length,variant,flutter)
				local=pivot+(local-pivot).rotated(sin(seed*2)*tear*.45)*(1-tear*.20)+offset
				points.append(pose*local)
			for indices in [[0,1,2],[0,2,3]]:
				_textured_triangle(canvas,PackedVector2Array([points[indices[0]],points[indices[1]],points[indices[2]]]),PackedVector2Array([uv[indices[0]],uv[indices[1]],uv[indices[2]]]),tint,mask)

static func in_vessel(canvas: CanvasItem, rect: Rect2, count: int, contents: Dictionary, capacity: float, coupe: bool, mixing: bool, ice_fraction: float, phase: float, ages: Array=[], motion:=0.0, metal:=false, shape:="",depth_pass:=-1,profiles: Dictionary={},processing: Array=[]) -> void:
	if count<=0: return
	var profile:=Ice.profile(rect,coupe,mixing,shape)
	var qty:=Liquid.volume(contents)
	var surface:=rect.position.y+rect.size.y*Liquid.surface_fraction(qty,capacity,coupe,ice_fraction>0,mixing,ice_fraction,shape)
	var length:=clampf(rect.size.x*.44,40,76)
	for i in range(mini(count,18)):
		if depth_pass>=0 and (1 if i%3==0 else 0)!=depth_pass: continue
		var age: float=ages[i] if i<ages.size() else 10.0
		var entry:=1-smoothstep(0,.52,age)
		var a:=i*2.39996
		var spread:=sqrt((i%9+1)/10.0)
		var y: float=lerpf(surface+length*.22,profile.floor-length*.29,fmod(i*.381966+.12,1.0)) if qty>0 else profile.floor-length*.33-(i/6)*length*.24
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
		leaf(canvas,point,length*(.87+(i%3)*.075),a*.58+entry*.7+sin(phase*4+i)*motion*.18,.83+(i%3)*.07,i,.65 if qty>0 else 0.0,mask,sin(phase*1.8+i)*(.10+motion*.7)+entry*.5,Liquid.color(contents,profiles),float(processing[i].work) if i<processing.size() else 0.0)
