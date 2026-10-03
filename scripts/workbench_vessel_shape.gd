extends RefCounted
## Inner walls measured against the trimmed shared glass artwork (not its bounding box).
## Each pair is axial height / radius. Millilitres remain owned by WorkbenchSession.
const PROFILES := {
	"coupe": {"center":.5,"depth":.085,"walls":[Vector2(.13,.46),Vector2(.18,.455),Vector2(.23,.42),Vector2(.28,.34),Vector2(.32,.21),Vector2(.345,0)]},
	"glass_cocktail_glass": {"center":.5,"depth":.075,"walls":[Vector2(.115,.445),Vector2(.19,.447),Vector2(.25,.41),Vector2(.31,.32),Vector2(.36,.20),Vector2(.39,0)]},
	"glass_balloon_glass": {"center":.5,"depth":.044,"walls":[Vector2(.065,.34),Vector2(.14,.405),Vector2(.23,.451),Vector2(.31,.447),Vector2(.39,.37),Vector2(.46,.24),Vector2(.50,0)]},
	"highball": {"center":.5,"depth":.038,"walls":[Vector2(.065,.43),Vector2(.55,.414),Vector2(.68,.365),Vector2(.79,.30)]},
	"mixing": {"center":.435,"depth":.040,"walls":[Vector2(.08,.357),Vector2(.55,.335),Vector2(.67,.28),Vector2(.80,.245)]}
}
static var volume_tables: Dictionary={}

static func profile(id: String) -> Dictionary:
	return PROFILES.get("highball" if id=="rocks" else id,PROFILES.highball)

static func radius(id: String, y: float) -> float:
	var walls: Array=profile(id).walls
	for i in range(1,walls.size()):
		if y<=walls[i].x:
			return lerpf(walls[i-1].y,walls[i].y,clampf((y-walls[i-1].x)/(walls[i].x-walls[i-1].x),0,1))
	return float(walls.back().y)

static func surface(id: String, fraction: float) -> float:
	var walls: Array=profile(id).walls
	if not volume_tables.has(id):
		var cumulative:=PackedFloat32Array([0.0])
		for i in range(1,257):
			var y:=lerpf(walls.back().x,walls.front().x,(i-.5)/256.0)
			cumulative.append(cumulative[-1]+pow(radius(id,y),2))
		volume_tables[id]=cumulative
	var table: PackedFloat32Array=volume_tables[id]
	var target:=clampf(fraction,0,1)*table[-1]
	for i in range(1,table.size()):
		if table[i]>=target:
			var t: float=(i-1+(target-table[i-1])/maxf(.000001,table[i]-table[i-1]))/256.0
			return lerpf(walls.back().x,walls.front().x,t)
	return float(walls.front().x)

static func depth(id: String, y: float) -> float:
	return float(profile(id).depth)*radius(id,y)/radius(id,float(profile(id).walls.front().x))

static func _body(rect: Rect2, id: String, top: float) -> PackedVector2Array:
	var p:=profile(id)
	var floor_y: float=p.walls.back().x
	var points:=PackedVector2Array()
	var width:=radius(id,top)
	for i in range(33):
		var a:=PI+i*PI/32.0
		points.append(rect.position+rect.size*Vector2(p.center+cos(a)*width,top+sin(a)*depth(id,top)))
	for i in range(1,65):
		var y:=lerpf(top,floor_y,i/64.0)
		points.append(rect.position+rect.size*Vector2(p.center+radius(id,y),y))
	if radius(id,floor_y)>0:
		for i in range(1,33):
			var a:=i*PI/32.0
			points.append(rect.position+rect.size*Vector2(p.center+cos(a)*radius(id,floor_y),floor_y+sin(a)*depth(id,floor_y)))
	for i in range(1,64):
		var y:=lerpf(floor_y,top,i/64.0)
		points.append(rect.position+rect.size*Vector2(p.center-radius(id,y),y))
	return points

static func cavity(rect: Rect2, id: String, entry:=false) -> PackedVector2Array:
	var p:=profile(id)
	var rim: float=p.walls.front().x
	if not entry: return _body(rect,id,rim)
	var points:=PackedVector2Array()
	points.append(rect.position+rect.size*Vector2(p.center-radius(id,rim),rim)-Vector2(0,150))
	points.append(rect.position+rect.size*Vector2(p.center+radius(id,rim),rim)-Vector2(0,150))
	var outline:=_body(rect,id,rim)
	for i in range(32,outline.size()): points.append(outline[i])
	return points

static func body(rect: Rect2, id: String, top: float) -> PackedVector2Array:
	var sections:=Geometry2D.intersect_polygons(_body(rect,id,top),cavity(rect,id))
	return sections[0] if not sections.is_empty() else PackedVector2Array()
