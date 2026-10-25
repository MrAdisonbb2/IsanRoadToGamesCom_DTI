@tool
extends AnimatedSprite2D
## Harmless wanderer: small animals (RPG Maker style 3x4 sheet block) or an NPC strip
## like the beggar. Walks around inside its area, animals scurry away from the hero.

var area := Rect2()
var world
var speed := 18.0
var shy := true
var _vel := Vector2.ZERO
var _t := 0.0
var _dirs := false


## Animal from a sheet of 4x2 blocks, each block 3 frames x 4 rows (down, left, right, up).
func setup_animal(sheet: String, fw: int, fh: int, block: Vector2i) -> void:
	var t := Game.tex(sheet)
	var sf := SpriteFrames.new()
	sf.remove_animation("default")
	var rows := ["down", "left", "right", "up"]
	for r in 4:
		var n: String = rows[r]
		sf.add_animation(n)
		sf.set_animation_speed(n, 6.0)
		for c in [0, 1, 2, 1]:
			var at := AtlasTexture.new()
			at.atlas = t
			at.region = Rect2((block.x * 3 + c) * fw, (block.y * 4 + r) * fh, fw, fh)
			sf.add_frame(n, at)
	sprite_frames = sf
	offset = Vector2(0, -fh / 2.0 + 4.0)
	_dirs = true
	play("down")
	pause()


func setup_npc(frames: SpriteFrames, sc: float) -> void:
	sprite_frames = frames
	scale = Vector2(sc, sc)
	offset = Vector2(0, -16)
	shy = false
	speed = 10.0
	play("idle")


func _process(delta: float) -> void:
	if Engine.is_editor_hint():
		return
	_t -= delta
	var p = world.player if world else null
	if shy and p and not p.dead and p.global_position.distance_to(global_position) < 34.0:
		_vel = (global_position - p.global_position).normalized() * speed * 2.5
		_t = 0.6
	elif _t <= 0.0:
		_t = randf_range(1.0, 3.0)
		_vel = Vector2.ZERO if randf() < 0.4 else Vector2.RIGHT.rotated(randf() * TAU) * speed
	position += _vel * delta
	var clamped := position.clamp(area.position, area.end)
	if clamped != position:
		position = clamped
		_vel = -_vel
	if _vel.length() < 1.0:
		if _dirs:
			pause()
		return
	if _dirs:
		var a := "right" if _vel.x > 0 else "left"
		if absf(_vel.y) > absf(_vel.x):
			a = "down" if _vel.y > 0 else "up"
		if animation != a or not is_playing():
			play(a)
	else:
		flip_h = _vel.x < 0.0
