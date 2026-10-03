extends Control
const Garnish=preload("res://scripts/workbench_garnish.gd")
var kind: String="garnish"
func _draw() -> void:
	Garnish.piece(self,size*.5,minf(size.x,size.y)*.36,kind,-.12)
