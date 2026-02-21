extends CharacterBody2D

enum State { MOVE, HANG, CLIMB }
var state: State = State.MOVE

@export var walk_speed := 120.0
@export var run_speed := 220.0
@export var jump_velocity := -420.0
@export var gravity := 1200.0

@onready var cam: Camera2D = $Camera2D
@export var run_shake_strength := 2.5   # сила тряски
@export var run_shake_speed := 18.0     # частота
var _shake_t := 0.0
var _cam_base_offset := Vector2.ZERO

@export var hang_snap_offset := Vector2(-7, 7)   
@export var climb_up_offset := Vector2(0, -28)   
@export var climb_forward := 14.0                

@onready var hint: RichTextLabel = $InteractLabel
@onready var anim: AnimatedSprite2D = $Visual/AnimatedSprite2D
@onready var visual: Node2D = $Visual
@onready var ray_wall: RayCast2D = $RayWall
@onready var ray_ledge: RayCast2D = $RayLedge

var dir := 1 # 1 вправо, -1 влево
var falling_started := false
var hang_point := Vector2.ZERO

var current_npc: Node = null
var can_interact := false

var air_speed := 0.0

func _ready() -> void:
	anim.animation_finished.connect(_on_anim_finished)
	_cam_base_offset = cam.offset

func _physics_process(delta: float) -> void:
	var axis := Input.get_axis("move_left", "move_right")
	match state:
		State.MOVE:
			_move_state(delta)
		State.HANG:
			_hang_state(delta)
		State.CLIMB:
			_climb_state(delta)
	_update_run_camera_shake(delta, axis) # axis — твой Input.get_axis(...)

func _update_run_camera_shake(delta: float, axis: float) -> void:
	var is_running := is_on_floor() and Input.is_action_pressed("sprint") and axis != 0

	if is_running:
		_shake_t += delta * run_shake_speed
		var shake := Vector2(
			sin(_shake_t) * run_shake_strength,
			sin(_shake_t * 1.7) * run_shake_strength * 0.6
		)
		cam.offset = _cam_base_offset + shake
	else:
		_shake_t = 0.0
		# плавно возвращаемся в ноль
		cam.offset = cam.offset.lerp(_cam_base_offset, 12.0 * delta)
		
func _move_state(delta: float) -> void:
	var axis := Input.get_axis("move_left", "move_right")

	if axis != 0:
		dir = 1 if axis > 0 else -1
		visual.scale.x = abs(visual.scale.x) * dir
		_update_rays_dir()

	# гравитация
	if not is_on_floor():
		velocity.y += gravity * delta
	else:
		falling_started = false

	# прыжок
	if is_on_floor() and Input.is_action_just_pressed("jump"):
		velocity.y = jump_velocity

	# бег только по земле + Shift
	var speed := walk_speed
	if is_on_floor():
		if Input.is_action_pressed("sprint") and axis != 0:
			speed = run_speed
		air_speed = speed
	else:
		speed = air_speed

	velocity.x = axis * speed

	move_and_slide()

	# попытка схватиться за уступ:
	_try_grab_ledge()

	# анимации обычного движения (можешь оставить свои)
	_update_move_anims(axis, speed)

func _try_grab_ledge() -> void:
	if state != State.MOVE:
		return
	if is_on_floor():
		return
	if not Input.is_action_pressed("jump"):
		return

	# не хватаемся, пока летим вверх (иначе рандомные зацепы)
	if velocity.y < 0:
		return

	# обновить лучи в этом же кадре
	ray_wall.force_raycast_update()
	ray_ledge.force_raycast_update()

	if ray_wall.is_colliding() and not ray_ledge.is_colliding():
		var col = ray_wall.get_collider()
		if col and col.is_in_group("npc"):
			return

		var p := ray_wall.get_collision_point()

		# фиксируем позицию, чтобы не было "полупикселей" и дрожания
		hang_point = (p + Vector2(hang_snap_offset.x * dir, hang_snap_offset.y)).round()

		_enter_hang()

func register_target(npc: Node) -> void:
	npc.interaction_available.connect(_on_npc_interaction_available)

func _on_npc_interaction_available(npc: Node, available: bool) -> void:
	current_npc = npc
	can_interact = available
	hint.visible = can_interact

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("interact") and can_interact and current_npc:
		if current_npc.try_kill():
			hint.visible = false
			can_interact = false
			current_npc = null

func _enter_hang() -> void:
	state = State.HANG
	velocity = Vector2.ZERO
	falling_started = false
	global_position = hang_point
	anim.play("hang")

func _hang_state(_delta: float) -> void:
	velocity = Vector2.ZERO

	# S — отпустить и упасть
	if Input.is_action_just_pressed("crouch"):
		state = State.MOVE
		velocity.y = 50.0
		return

	# W нажать ЕЩЁ РАЗ — залезть (climb)
	if Input.is_action_just_pressed("jump"):
		state = State.CLIMB
		anim.play("climb")

func _climb_state(_delta: float) -> void:
	# пока идет анимация — стоим на месте
	velocity = Vector2.ZERO

func _on_anim_finished() -> void:
	if state == State.CLIMB and anim.animation == "climb":
		# переносим на верх платформы
		global_position += climb_up_offset + Vector2(climb_forward * dir, 0)
		state = State.MOVE

func _update_move_anims(axis: float, speed: float) -> void:
	if state != State.MOVE:
		return

	if not is_on_floor():
		if velocity.y < 0:
			anim.play("jump")
		else:
			if not falling_started:
				falling_started = true
				anim.play("fall")
		return

	if abs(velocity.x) < 1.0:
		anim.play("idle")
		if is_on_floor() and axis == 0:
			air_speed = walk_speed
	elif abs(velocity.x) >= run_speed - 1.0:
		anim.play("run")
	else:
		anim.play("walk")

func _update_rays_dir() -> void:
	ray_wall.target_position.y = abs(ray_wall.target_position.y) * dir
	ray_ledge.target_position.y = abs(ray_ledge.target_position.y) * dir
