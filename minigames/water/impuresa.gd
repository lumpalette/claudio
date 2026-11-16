extends Area2D

func _on_body_entered(body: Node2D) -> void:
	if body.is_in_group("Player"):
		_collect()


func _collect() -> void:
	var contador = get_tree().get_first_node_in_group("contador")
	if contador:
		contador.impuresa_collected()
	queue_free()
