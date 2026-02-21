extends Node2D

@export var is_target := false
@export var animations: SpriteFrames

@onready var detect_area: Area2D = $DetectArea
@onready var vision_area: Area2D = $VisionArea
@onready var anim: AnimatedSprite2D = $Animation

var player_in_range: Node = null
var player_in_vision: Node = null

var can_see_player := false

var alive = true

signal interaction_available(npc: Node, available: bool)

var _last_pos: Vector2

func _ready() -> void:
	var player = get_tree().get_first_node_in_group("player")
	if player:
		player.register_target(self)
	detect_area.body_entered.connect(_on_detect_enter)
	detect_area.body_exited.connect(_on_detect_exit)
	vision_area.body_entered.connect(_on_vision_enter)
	vision_area.body_exited.connect(_on_vision_exit)

	if animations:
		anim.sprite_frames = animations

	_last_pos = global_position
	anim.play("idle")

func _process(_delta: float) -> void:
	# “видит игрока” если он в VisionArea
	can_see_player = player_in_vision != null

	# можно взаимодействовать только если:
	# - это цель
	# - игрок рядом
	# - цель НЕ видит игрока
	var available := is_target and player_in_range != null and not can_see_player and alive
	emit_signal("interaction_available", self, available)

	# анимация ходьбы/стоянки
	var moved := global_position.distance_to(_last_pos) > 0.1
	_last_pos = global_position

	if moved:
		if anim.animation != "walk" and alive:
			anim.play("walk")
	else:
		if anim.animation != "idle" and alive:
			anim.play("idle")

func try_kill() -> bool:
	if not alive:
		return false
	if not is_target:
		return false
	if player_in_range == null:
		return false
	if can_see_player:
		return false
	
	anim.play("death")
	anim.animation_looped
	alive = false
	return true

func _on_detect_enter(body: Node) -> void:
	if body.is_in_group("player"):
		player_in_range = body

func _on_detect_exit(body: Node) -> void:
	if body == player_in_range:
		player_in_range = null

func _on_vision_enter(body: Node) -> void:
	if body.is_in_group("player"):
		player_in_vision = body

func _on_vision_exit(body: Node) -> void:
	if body == player_in_vision:
		player_in_vision = null
