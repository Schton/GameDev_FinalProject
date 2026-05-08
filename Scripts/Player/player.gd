extends CharacterBody2D

enum Faction { PLAYER, ENEMY }
enum State { ALIVE, DEAD } # Use the same names as the enemy script
var state = State.ALIVE

var current_duelist = null

@export var faction = Faction.PLAYER

@export var projectile_scene: PackedScene
@export var projectile_distance := 600.0

@export var move_speed := 200.0
@onready var anim := $Sprite2D  # Make sure this is AnimatedSprite2D

@export var max_hp := 500
@export var sword_damage := 25
@export var spell_damage := 18

var hp := 100
var invincible := false

# ================= VARIABLES =================
var is_attacking := false
var current_anim := ""  # Track current animation to prevent freezing

enum Direction { UP, DOWN, LEFT, RIGHT }
var facing := Direction.DOWN

@export var dash_speed := 800.0
@export var dash_duration := 0.25 # A quarter of a second
var is_dashing := false

# ================= INPUT =================
func _ready():
	hp = max_hp
	$SwordHitbox.monitoring = false
	add_to_group("units")

func _process(delta):
	if Input.is_action_just_pressed("mouse_left") and not is_attacking:
		attack()

	if Input.is_action_just_pressed("key_shift") and not is_dashing:
		start_dash()

	if Input.is_action_just_pressed("key_e"):
		if not is_attacking and not is_dashing:
			fire_projectile()

# ================= PHYSICS & MOVEMENT =================
func _physics_process(delta):
	# 1. Handle Attacking State (Priority)
	if is_attacking:
		velocity = Vector2.ZERO
		move_and_slide()
		if not anim.is_playing():
			is_attacking = false
		return

	# 2. Get Input
	var input_dir = Vector2.ZERO
	input_dir.x = Input.get_action_strength("key_d") - Input.get_action_strength("key_a")
	input_dir.y = Input.get_action_strength("key_s") - Input.get_action_strength("key_w")

	# 3. Handle Movement and Dashing
	if input_dir != Vector2.ZERO:
		input_dir = input_dir.normalized()
		
		# Determine speed
		var current_speed = dash_speed if is_dashing else move_speed
		velocity = input_dir * current_speed
	  
		update_facing(input_dir)
		play_walk()
	else:
		# If not moving but dashing, dash forward. Otherwise, Idle.
		if is_dashing:
			velocity = get_facing_vector() * dash_speed
		else:
			velocity = Vector2.ZERO
			play_idle()

	move_and_slide()
# ================= DIRECTION =================
func update_facing(dir: Vector2):
	if abs(dir.x) > abs(dir.y):
		if dir.x > 0:
			facing = Direction.RIGHT
		else:
			facing = Direction.LEFT
	else:
		if dir.y > 0:
			facing = Direction.DOWN
		else:
			facing = Direction.UP

# ================= ANIMATION =================
func play_walk():
	match facing:
		Direction.UP:
			_set_anim("walk_back")
		Direction.DOWN:
			_set_anim("walk_front")
		Direction.LEFT:
			_set_anim("walk_left")
		Direction.RIGHT:
			_set_anim("walk_right")

func play_idle():
	match facing:
		Direction.UP:
			_set_anim("idle_back")
		Direction.DOWN:
			_set_anim("idle_front")
		Direction.LEFT:
			_set_anim("idle_left")
		Direction.RIGHT:
			_set_anim("idle_right")

# Only change animation when needed (prevents frame reset)
func _set_anim(name: String):
	if current_anim == name:
		return
	anim.play(name)
	current_anim = name

func _input(event):
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP and event.pressed:
			$Camera2D.zoom *= 0.9  # zoom in
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN and event.pressed:
			$Camera2D.zoom *= 1.1  # zoom out
	 # Clamp so zoom doesn’t go too extreme
		$Camera2D.zoom.x = clamp($Camera2D.zoom.x, 0.7, 5)
		$Camera2D.zoom.y = clamp($Camera2D.zoom.y, 0.7, 5)


# ================= ATTACK =================
func attack():
	is_attacking = true
	match facing:
		Direction.UP:
			_set_anim("attack_back")
		Direction.DOWN:
			_set_anim("attack_front")
		Direction.LEFT:
			_set_anim("attack_left")
		Direction.RIGHT:
			_set_anim("attack_right")
	start_sword_hit()

func start_sword_hit():
	var hitbox = $SwordHitbox
	position_sword_hitbox()

	hitbox.monitoring = true
	
	# CRITICAL: We need to wait for the physics engine to update 
	# now that the hitbox has moved and turned on.
	await get_tree().physics_frame 
	
	var bodies = hitbox.get_overlapping_bodies()
	print("Checking for bodies... found: ", bodies.size()) # Debug this!

	for body in bodies:
		if body.has_method("take_damage") and body.faction != faction:
			var knock = global_position.direction_to(body.global_position)
			body.take_damage(sword_damage, knock)
			
	await get_tree().create_timer(0.1).timeout
	hitbox.monitoring = false

func position_sword_hitbox():
	var hitbox = $SwordHitbox

	match facing:
		Direction.UP:
			hitbox.position = Vector2(0, -38)

		Direction.DOWN:
			hitbox.position = Vector2(0, 38)

		Direction.LEFT:
			hitbox.position = Vector2(-38, 0)

		Direction.RIGHT:
			hitbox.position = Vector2(38, 0)

# ================= SIGNAL =================
# Connect this signal from AnimatedSprite2D → Player node
func _on_sprite_2d_animation_finished():
	var a_name = anim.animation
	# Since AnimatedSprite2D's signal doesn't send the name by default, 
	# we check the current animation manually
	if anim.animation.begins_with("attack") or a_name.begins_with("cast"):
		is_attacking = false
		current_anim = "" # Reset this so walk/idle can play immediately

# ================= Projectile =================
func fire_projectile():
	if projectile_scene == null or is_attacking or is_dashing:
		return

	# Lock movement using your existing attack state
	is_attacking = true 
	
	# 1. Play the Casting Animation
	match facing:
		Direction.UP: _set_anim("cast_up")
		Direction.DOWN: _set_anim("cast_down")
		Direction.LEFT: _set_anim("cast_left")
		Direction.RIGHT: _set_anim("cast_right")

	# 2. Spawn the actual projectile
	var projectile = projectile_scene.instantiate()
	get_parent().add_child(projectile)
	projectile.global_position = global_position

	# Pass the distance variable to the projectile
	projectile.max_distance = projectile_distance
	
	var dir := get_facing_vector() # Using the helper function we made earlier!
	projectile.velocity = dir * projectile.speed

	# Fixed signal connection (only one line!)
	projectile.tree_exited.connect(_on_projectile_removed)

func start_dash():
	is_dashing = true
	set_collision_mask_value(3, false)
	await get_tree().create_timer(dash_duration).timeout
	set_collision_mask_value(3, true)
	is_dashing = false

func get_facing_vector() -> Vector2:
	match facing:
		Direction.UP: return Vector2.UP
		Direction.DOWN: return Vector2.DOWN
		Direction.LEFT: return Vector2.LEFT
		Direction.RIGHT: return Vector2.RIGHT
	return Vector2.ZERO

func _on_projectile_removed():
	# This runs every time a projectile disappears or hits a wall
	print("A projectile has left the scene.")

# ================= Damage =================

func take_damage(amount, knock_dir := Vector2.ZERO, attacker = null):
	if invincible:
		return

	hp -= amount
	print("Player HP:", hp)

	if hp <= 0:
		die()
		return

	invincible = true
	await get_tree().create_timer(0.5).timeout
	invincible = false

func die():
	anim.play("death")
	queue_free()

func _on_sword_hitbox_body_entered(body: Node2D) -> void:
	if body.has_method("take_damage") and body.faction != faction:
		var knock = global_position.direction_to(body.global_position)
		body.take_damage(sword_damage, knock)
	print("Sword touched:", body.name)
