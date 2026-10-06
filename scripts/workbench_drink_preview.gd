extends Control
const Art=preload("res://scripts/workbench_art.gd")
const Liquid=preload("res://scripts/workbench_liquid.gd")
const Mint=preload("res://scripts/workbench_mint.gd")
const Ice=preload("res://scripts/workbench_ice.gd")
const Garnish=preload("res://scripts/workbench_garnish.gd")
var result: Dictionary={}
var accent:=Color("dbb455")
var clock:=0.0
var saved_art: Texture2D

func _ready() -> void:
	var path:=str(result.get("image_path",""))
	if path.begins_with("user://") and FileAccess.file_exists(path):
		var picture:=Image.load_from_file(path)
		if picture != null: saved_art=ImageTexture.create_from_image(picture)

func _init() -> void:
	texture_filter=CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS

func _process(delta: float) -> void:
	clock+=delta
	queue_redraw()

func _draw() -> void:
	if result.is_empty(): return
	if saved_art != null:
		var extent:=saved_art.get_size()*minf(size.x/saved_art.get_width(),size.y/saved_art.get_height())
		draw_texture_rect(saved_art,Rect2((size-extent)*.5,extent),false)
		return
	var vessel: Dictionary=result.get("contents",{})
	var cup:=str(result.get("cup","coupe"))
	if cup=="rocks": cup="highball"
	var texture: Texture2D=Art.texture(cup)
	if texture==null: return
	for i in range(8,0,-1):
		var ring:=StyleBoxFlat.new()
		ring.bg_color=Color.TRANSPARENT
		ring.border_color=Color(accent,.015+(8-i)*.006)
		ring.set_border_width_all(3)
		ring.set_corner_radius_all(22+i)
		draw_style_box(ring,Rect2(14-i,14-i,size.x-28+i*2,size.y-28+i*2))
	var panel:=StyleBoxFlat.new()
	panel.bg_color=Color("352b25")
	panel.border_color=accent
	panel.set_border_width_all(2)
	panel.set_corner_radius_all(18)
	draw_style_box(panel,Rect2(14,14,size.x-28,size.y-28))
	var extent:=texture.get_size()*minf((size.x-78)/texture.get_width(),(size.y-95)/texture.get_height())
	var rect:=Rect2(Vector2((size.x-extent.x)*.5,size.y-48-extent.y),extent)
	var fill:=rect
	var coupe:=cup in ["coupe","glass_cocktail_glass"]
	var contents: Dictionary=vessel.get("contents",{})
	var capacity:=float(result.get("capacity_ml",300))
	var batches:=WorkbenchSession.ice_batches(vessel)
	var displacement:=WorkbenchSession.ice_volume(vessel)/40.0
	Liquid.draw(self,fill,contents,capacity,coupe,.06,not batches.is_empty(),clock,false,displacement,cup,Liquid.State.layers(vessel),result.get("liquid_profiles",{}))
	var solids: Dictionary=vessel.get("solids",{})
	Mint.in_vessel(self,fill,int(solids.get("sku_mint_leaf",0)),contents,capacity,coupe,false,displacement,clock,[],0,false,cup,0,result.get("liquid_profiles",{}),WorkbenchSession.Muddle.leaves(vessel))
	for i in range(batches.size()):
		Ice.draw(self,fill,batches[i].kind,contents,capacity,coupe,false,10,clock,0,false,i,displacement,cup,int(batches[i].get("pieces",4 if batches[i].kind=="cube" else 10)))
	Mint.in_vessel(self,fill,int(solids.get("sku_mint_leaf",0)),contents,capacity,coupe,false,displacement,clock,[],0,false,cup,1,result.get("liquid_profiles",{}),WorkbenchSession.Muddle.leaves(vessel))
	draw_texture_rect(texture,rect,false)
	Garnish.draw(self,fill,WorkbenchSession.garnishes(vessel),[],clock,coupe,cup)
	if result.get("evaluation",{}).get("tier","")=="perfect":
		for i in range(5):
			var point:=Vector2(29+(i%2)*(size.x-58),60+i*57)
			var alpha:=.25+.3*(sin(clock*1.5+i)+1)*.5
			draw_line(point-Vector2(3,0),point+Vector2(3,0),Color(accent,alpha),1.2,true)
			draw_line(point-Vector2(0,4),point+Vector2(0,4),Color(accent,alpha),1.2,true)
