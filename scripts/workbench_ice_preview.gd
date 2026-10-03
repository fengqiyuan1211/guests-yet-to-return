extends Control
const Ice = preload("res://scripts/workbench_ice.gd")
var kind := "cube"

func _draw() -> void:
	Ice.preview(self,Rect2(Vector2(0,12),size-Vector2(0,20)),kind)
