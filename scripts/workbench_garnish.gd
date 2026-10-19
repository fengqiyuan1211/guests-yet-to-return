extends RefCounted
const Mint=preload("res://scripts/workbench_mint.gd")
## Painted geometry sized and seated on the glass rim, shared by pantry and table.

static func ellipse(canvas: CanvasItem, center: Vector2, radius: Vector2, color: Color) -> void:
	var points:=PackedVector2Array()
	for i in range(48): points.append(center+Vector2(cos(i*TAU/48)*radius.x,sin(i*TAU/48)*radius.y))
	canvas.draw_colored_polygon(points,color)

static func piece(canvas: CanvasItem, center: Vector2, radius: float, kind: String, angle:=0.0, pivot:=Vector2(.5,.5), frame:=Transform2D.IDENTITY) -> void:
	canvas.draw_set_transform_matrix(frame*Transform2D(angle,center))
	if kind not in ["sku_mint_leaf","sku_mint_sprig"]:
		var sprite_id: String="lime_wedge" if kind=="garnish" else kind.trim_prefix("sku_")
		var pixel: Texture2D=preload("res://scripts/pixel_art.gd").sprite(sprite_id)
		if pixel!=null:
			# Single fruit, native proportions; pantry and cup use the same artwork.
			var extent:=pixel.get_size()*(radius*2/maxf(pixel.get_width(),pixel.get_height()))
			canvas.draw_texture_rect(pixel,Rect2(-extent*pivot,extent),false)
			canvas.draw_set_transform_matrix(frame)
			return
	if kind=="sku_mint_leaf":
		Mint.leaf(canvas,Vector2.ZERO,radius*2.5,-.3,.84,0,.12)
	elif kind=="sku_mint_sprig":
		canvas.draw_polyline(PackedVector2Array([Vector2(0,radius*.9),Vector2(-2,0),Vector2(2,-radius*1.3)]),Color("657248"),2.2,true)
		for i in range(5):
			var side:=(-1.0 if i%2==0 else 1.0)
			var origin:=Vector2(side*radius*.31,radius*(.42-i*.30))
			Mint.leaf(canvas,origin,radius*(1.25 if i<4 else 1.0),side*.91,.83,i,.12)
	elif kind=="sku_cocktail_cherry":
		var c:=Vector2(0,radius*.20)
		ellipse(canvas,c+Vector2(1,2),Vector2(radius*.72,radius*.64),Color("39121d"))
		for layer in range(14):
			var t:=layer/13.0
			ellipse(canvas,c-Vector2(radius*.14,radius*.18)*t,Vector2(radius*.69,radius*.61)*(1-t*.76),Color("66202c").lerp(Color("ae4a4b"),t))
		ellipse(canvas,c-Vector2(radius*.24,radius*.25),Vector2(radius*.16,radius*.075),Color(.96,.82,.71,.75))
		var stem:=PackedVector2Array()
		for i in range(20):
			var t:=i/19.0
			stem.append(c+Vector2(sin(t*1.8)*radius*.52,-radius*.5-t*radius))
		canvas.draw_polyline(stem,Color("675838"),1.8,true)
		canvas.draw_polyline(stem,Color(.65,.60,.34,.5),.65,true)
	elif kind=="sku_white_cane_sugar":
		for i in range(18):
			var pos:=Vector2(sin(i*2.4)*radius*.7,cos(i*1.7)*radius*.42)
			var r:=radius*(.09+.025*(i%3))
			canvas.draw_colored_polygon(PackedVector2Array([pos+Vector2(-r,0),pos+Vector2(-r*.5,-r),pos+Vector2(r*.6,-r*.8),pos+Vector2(r,0)]),Color("f5eac8"))
			canvas.draw_colored_polygon(PackedVector2Array([pos+Vector2(-r,0),pos+Vector2(r,0),pos+Vector2(r*.6,r*.7),pos+Vector2(-r*.7,r*.6)]),Color("b9a781"))
			canvas.draw_line(pos+Vector2(-r*.5,-r),pos+Vector2(r*.6,-r*.8),Color("fff5d8"),.8,true)
	else:
		var lime:=kind=="garnish"
		var rind:=Color("556531") if lime else Color("ba872a")
		var flesh:=Color("b9c378") if lime else Color("edd082")
		# A lime wedge is a partial disc; lemon is a full wheel with a rim notch.
		var start: float=-PI*.90 if lime else -PI*.98
		var end: float=PI*.15 if lime else PI*.98
		# Exposed rind thickness and a contact shadow behind the moist cut face.
		for depth in range(6,0,-1):
			var edge:=PackedVector2Array([Vector2(0,depth)])
			for i in range(65):
				var a:=lerpf(start,end,i/64.0)
				edge.append(Vector2(cos(a)*radius,sin(a)*radius*.83+depth))
			canvas.draw_colored_polygon(edge,rind.darkened(.18+depth*.03))
		for layer in range(4):
			var r:=radius*(1-layer*.09)
			var polygon:=PackedVector2Array([Vector2.ZERO])
			for i in range(65):
				var a:=lerpf(start,end,i/64.0)
				polygon.append(Vector2(cos(a)*r,sin(a)*r*.83)+Vector2(0,3 if layer==0 else 0))
			var colors:=PackedColorArray()
			var base: Color=[rind,Color("e8d7a1"),flesh,flesh.lightened(.08)][layer]
			for point in polygon:
				colors.append(base.lightened(.14).lerp(base.darkened(.19),clampf((point.y/radius+1)*.5,0,1)))
			canvas.draw_polygon(polygon,colors)
		var segments:=6 if lime else 10
		for i in range(segments):
			var a:=lerpf(start,end,(i+.5)/segments)
			var wedge:=PackedVector2Array([Vector2(cos(a),sin(a)*.83)*radius*.13])
			for j in range(9):
				var b:=a+lerpf(-.20,.20,j/8.0)
				wedge.append(Vector2(cos(b),sin(b)*.83)*radius*.70)
			canvas.draw_colored_polygon(wedge,flesh.darkened(.03+(i%3)*.05))
			for j in range(3):
				var c:=Vector2(cos(a+(j-1)*.10),sin(a+(j-1)*.10)*.83)*radius*(.32+j*.1)
				canvas.draw_line(c,c+Vector2(cos(a)*3,sin(a)*2),Color(1,.96,.69,.28),.8,true)
		var rng:=RandomNumberGenerator.new()
		rng.seed=4892 if lime else 5094
		for i in range(95):
			var a:=rng.randf_range(start,end)
			var r:=radius*rng.randf_range(.14,.75)
			var point:=Vector2(cos(a)*r,sin(a)*r*.83)
			canvas.draw_line(point,point+Vector2(cos(a),sin(a)*.83)*rng.randf_range(.7,2.5),Color(1,.98,.78,rng.randf_range(.06,.22)),.7,true)
		for i in range(40):
			var a:=rng.randf_range(start,end)
			var point:=Vector2(cos(a),sin(a)*.83)*radius*.92
			canvas.draw_circle(point,.45,Color(.2,.25,.08,.20),true,-1,true)
		for i in range(5):
			var a:=lerpf(start,end,(i+.7)/5)
			var point:=Vector2(cos(a),sin(a)*.83)*radius*.52
			ellipse(canvas,point,Vector2(radius*.05,radius*.026),Color(1,.98,.84,.38))
		if not lime:
			ellipse(canvas,Vector2(6,-3),Vector2(1.3,2.7),Color("f7eac8"))
			ellipse(canvas,Vector2(-5,4),Vector2(1.3,2.3),Color("f7eac8"))
	canvas.draw_set_transform_matrix(frame)

static func draw(canvas: CanvasItem, rect: Rect2, ids: Array, ages: Array, phase: float, coupe: bool, shape:="", frame:=Transform2D.IDENTITY) -> void:
	canvas.draw_set_transform_matrix(frame)
	var center:=rect.position+rect.size*Vector2(.5,.07 if coupe else .09)
	var half:=rect.size.x*(.46 if coupe else .35)
	var depth:=rect.size.y*.035
	if not shape.is_empty():
		var p:=preload("res://scripts/workbench_vessel_shape.gd").profile(shape)
		center=rect.position+rect.size*Vector2(p.center,p.walls.front().x)
		half=rect.size.x*p.walls.front().y
		depth=rect.size.y*p.depth
	for i in range(ids.size()):
		var side:=1.0 if i%2==0 else -1.0
		# Place along the front ellipse, rather than on a flat row above the glass.
		var across:=side*(.84-(i/2)*.23)
		var anchor:=center+Vector2(across*half,depth*sqrt(maxf(0,1-across*across)))
		var age: float=ages[i] if i<ages.size() else 10.0
		var arriving:=1-smoothstep(0,.4,age)
		var bob:=sin(maxf(0,age-.4)*15)*exp(-maxf(0,age-.4)*8)*2 if age>=.4 else 0.0
		var radius:=clampf(half*.39,12,30)
		var pivot:=Vector2(.5,.5)
		var offset:=Vector2.ZERO
		var kind: String=ids[i]
		if kind in ["garnish","sku_lime_wedge"]: pivot=Vector2(.54,.79)
		elif kind in ["lemon_slice","sku_lemon_slice"]:
			pivot=Vector2(.64,.85); radius*=.91
		elif kind=="sku_cocktail_cherry":
			pivot=Vector2(.42,.76); radius*=.77
		elif kind=="sku_mint_sprig":
			radius*=.86; offset.y=-radius*.65
		ellipse(canvas,anchor+Vector2(1,2),Vector2(radius*.30,1.6),Color(0,0,0,.17*(1-arriving)))
		piece(canvas,anchor+offset+Vector2(0,-arriving*55+bob),radius,kind,side*.14+arriving*.3,pivot,frame)
		# The rim passes through the citrus notch, and across cherry / mint stems.
		if arriving<.03:
			var tangent:=Vector2(1,-across*depth/maxf(1,half*sqrt(1-across*across))).normalized()
			canvas.draw_line(anchor-tangent*2.5,anchor+tangent*2.5,Color(.85,.85,.73,.60),1.0,false)
	canvas.draw_set_transform(Vector2.ZERO)
