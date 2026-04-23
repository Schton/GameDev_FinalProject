extends CharacterBody2D

# =====================================================
# ADVANCED SOULSLIKE ENEMY AI (Godot 4)
# Features:
# - Idle patrol
# - Aggro detection
# - Chase player
# - Strafe / surround player
# - Attack combos
# - Cooldowns
# - Hit stun
# - Knockback
# - Return home if player escapes
# - Multi-enemy attack slot system
# =====================================================

enum State {
	IDLE,
	PATROL,
	CHASE,
	STRAFE,
	ATTACK,
	STUN,
	DEAD,
	RETURN_HOME
}

var state = State.IDLE

# ==========================
# SETTINGS
# ==========================
@export var move_speed := 130.0
@export var detect_range := 420.0
@export var lose_range := 700.0
@export var attack_range := 55.0
@export var strafe_range := 95.0

@export var max_health := 100
@export var attack_damage := 15

@export var attack_cooldown := 1.2
@export var stun_time := 0.35

# ==========================
# REFERENCES
# ==========================
@onready var anim = $AnimatedSprite2D
var player

# ==========================
# RUNTIME
# ==========================
var health := 100
var facing_dir := Vector2.DOWN
var spawn_position := Vector2.ZERO

var can_attack := true
var strafe_dir := 1
var stun_timer := 0.0
var attack_timer := 0.0

# =====================================================
# READY
# =====================================================
func _ready():
	health = max_health
	spawn_position = global_position
	player = get_tree().get_first_node_in_group("player")

	randomize()

# =====================================================
# MAIN LOOP
# =====================================================
func _physics_process(delta):

	if player == null:
		player = get_tree().get_first_node_in_group("player")
		return

	match state:
		State.IDLE:
			state_idle()

		State.PATROL:
			state_patrol()

		State.CHASE:
			state_chase()

		State.STRAFE:
			state_strafe()

		State.ATTACK:
			state_attack()

		State.STUN:
			state_stun(delta)

		State.RETURN_HOME:
			state_return_home()

		State.DEAD:
			velocity = Vector2.ZERO

	move_and_slide()
	update_animation()

# =====================================================
# STATES
# =====================================================

func state_idle():
	velocity = Vector2.ZERO

	if distance_to_player() < detect_range:
		state = State.CHASE

func state_patrol():
	velocity = Vector2.ZERO

func state_chase():

	var dist = distance_to_player()
	var dir = direction_to_player()

	if dist > lose_range:
		state = State.RETURN_HOME
		return

	if dist <= attack_range:
		try_attack()
		return

	if dist <= strafe_range:
		state = State.STRAFE
		return

	velocity = dir * move_speed

func state_strafe():

	var dist = distance_to_player()
	var dir = direction_to_player()

	if dist > strafe_range:
		state = State.CHASE
		return

	if dist <= attack_range:
		try_attack()
		return

	# Move sideways around player
	var side = dir.rotated(deg_to_rad(90 * strafe_dir))
	velocity = side * move_speed * 0.7

	# Randomly flip strafe direction
	if randf() < 0.01:
		strafe_dir *= -1

func state_attack():
	velocity = Vector2.ZERO

func state_stun(delta):
	velocity = Vector2.ZERO

	stun_timer -= delta
	if stun_timer <= 0:
		state = State.CHASE

func state_return_home():

	var dist = global_position.distance_to(spawn_position)

	if dist < 10:
		state = State.IDLE
		return

	var dir = global_position.direction_to(spawn_position)
	velocity = dir * move_speed

# =====================================================
# ATTACK SYSTEM
# =====================================================

func try_attack():

	if not can_attack:
		state = State.STRAFE
		return

	var attackers = get_tree().get_nodes_in_group("attackers")

	# max 2 enemies attack simultaneously
	if attackers.size() >= 2:
		state = State.STRAFE
		return

	start_attack()

func start_attack():

	state = State.ATTACK
	can_attack = false
	add_to_group("attackers")

	velocity = Vector2.ZERO

	anim.play("attack_" + get_dir())

	# Wait for animation
	await anim.animation_finished

	# DAMAGE CHECK
	if distance_to_player() <= attack_range + 10:
		if player.has_method("take_damage"):
			player.take_damage(attack_damage)

	remove_from_group("attackers")

	state = State.STRAFE

	await get_tree().create_timer(attack_cooldown).timeout
	can_attack = true

# =====================================================
# DAMAGE / HITSTUN
# =====================================================

func take_damage(amount, knock_dir := Vector2.ZERO):
	if state == State.DEAD:
		return

	health -= amount

	if health <= 0:
		die()
		return

	state = State.STUN
	stun_timer = stun_time

	velocity = knock_dir * 220

	anim.play("hurt_" + get_dir())
	print("Enemy HP:", health)

func die():

	state = State.DEAD
	velocity = Vector2.ZERO
	anim.play("death")

	await anim.animation_finished
	queue_free()

# =====================================================
# HELPERS
# =====================================================

func distance_to_player():
	return global_position.distance_to(player.global_position)

func direction_to_player():
	return global_position.direction_to(player.global_position)

func update_animation():

	if state == State.ATTACK or state == State.STUN or state == State.DEAD:
		return

	if velocity.length() > 0:
		facing_dir = velocity.normalized()
		anim.play("walk_" + get_dir())
	else:
		anim.play("idle_" + get_dir())

func get_dir() -> String:

	if abs(facing_dir.x) > abs(facing_dir.y):
		if facing_dir.x > 0:
			return "right"
		return "left"

	if facing_dir.y > 0:
		return "front"

	return "back"
