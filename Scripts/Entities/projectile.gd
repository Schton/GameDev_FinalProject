extends Area2D

@export var speed := 500.0
var velocity := Vector2.ZERO
var max_distance := 0.0
var start_pos := Vector2.ZERO

func _ready():
	# Record the starting position the moment the projectile enters the world
	start_pos = global_position

func _physics_process(delta):
	position += velocity * delta
	if max_distance > 0:
		var distance_traveled = global_position.distance_to(start_pos)
		if distance_traveled >= max_distance:
			queue_free()

func _on_visible_on_screen_notifier_2d_screen_exited():
	queue_free()

func _on_body_entered(body: Node2D) -> void:
	# We can check if it hit a TileMap or a static body
	print("Projectile hit: ", body.name)

	# DAMAGE ENEMIES
	if body.has_method("take_damage"):
		body.take_damage(18, velocity.normalized())

	# TILEMAP DEBUG
	elif body is TileMap:
		var tile_pos = body.local_to_map(body.to_local(global_position))
		print("I hit a TileMap tile at: ", tile_pos)

	else:
		print("I hit a node named: ", body.name)
	
	# Optional: Spawn an explosion effect here
	# spawn_explosion()
	
	# Destroy the projectile so it doesn't go through the wall
	queue_free()
