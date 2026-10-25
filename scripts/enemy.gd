@tool
extends CharacterBody2D
## Real-time monster on the stage map. Most kinds chase and hit on contact;
## the wraith and lizardman keep their distance and shoot, the minotaur charges,
## and the demon lord fires bullet patterns scaled by Game.boss_power().

const SPEEDS := {"wrath_merchant": 40.0, "wrath_beggar": 46.0, "wrath_king": 38.0,
	"slime": 34.0, "skeleton": 42.0, "wraith": 36.0, "wolf": 64.0, "golem": 28.0,
	"lizard": 44.0, "minotaur": 44.0, "demon_lord": 22.0}
const SHOOTERS := ["wraith", "lizard"]

var world
var id := ""
var e: Dictionary
var title := ""
var hp := 0
var max_hp := 0
var atk := 0.0
var def := 0.0
var speed := 40.0
var radius := 7.0
var height := 24.0
var dead := false
var spr: AnimatedSprite2D
var slow_t := 0.0
var _knock := Vector2.ZERO
var _atk_cd := 0.6
var _shot_cd := 1.5
var _flash := 0.0
var _state := "chase"
var _state_t := 3.0
var _charge_dir := Vector2.ZERO
var _charge_hit := false
var _pattern := 0
var _spiral := 0.0
var _busy := false
var _phase := 1
var _combo := 0
var _spin := 0.0


func setup(w, enemy_id: String, mult: float) -> void:
	world = w
	id = enemy_id
	e = Game.ENEMIES[id]
	title = e.name
	atk = float(e.atk) * mult
	def = float(e.def)
	speed = SPEEDS.get(id, 40.0) * randf_range(0.9, 1.1)
	if id == "demon_lord":
		title = Game.boss_title()
		max_hp = Game.BOSS_MAX_HP
		hp = int(Game.data.boss_hp)
		atk *= Game.boss_power()
		_state_t = 2.0
	else:
		max_hp = roundi(float(e.hp) * mult * 1.2)
		hp = max_hp
	spr = Game.enemy_sprite(id, 1.0)
	if e.kind == "mini":
		spr.scale = Vector2.ONE
		spr.position = Vector2(0, -14)
		height = 22.0
		radius = 7.0
	else:
		var sc: float = e.scale / 4.0
		spr.scale = Vector2(sc, sc)
		height = e.fh * sc
		spr.position = Vector2(0, -height / 2.0 + 2.0)
		radius = e.fw * sc * 0.3
	if id.begins_with("wrath_"):
		spr.self_modulate = Color(1.0, 0.45, 0.45)
		_state_t = 1.2
	add_child(spr)
	var col := CollisionShape2D.new()
	var sh := CircleShape2D.new()
	sh.radius = minf(radius * 0.7, 9.0)
	col.shape = sh
	add_child(col)
	collision_layer = 4
	collision_mask = 1
	motion_mode = CharacterBody2D.MOTION_MODE_FLOATING


func hit_pos() -> Vector2:
	return global_position + Vector2(0, -height / 2.0)


func is_boss() -> bool:
	return id == "demon_lord"


func _physics_process(delta: float) -> void:
	if Engine.is_editor_hint() or dead or world == null:
		return
	if world.cutscene:
		velocity = Vector2.ZERO
		return
	var p = world.player
	if p == null or p.dead:
		velocity = Vector2.ZERO
		return
	_atk_cd -= delta
	_shot_cd -= delta
	_state_t -= delta
	slow_t = maxf(0.0, slow_t - delta)
	var to: Vector2 = p.global_position - global_position
	var dist := to.length()
	var dir := to / maxf(dist, 0.001)
	var want := Vector2.ZERO
	var spd := speed * (0.45 if slow_t > 0.0 else 1.0)

	if id == "minotaur":
		want = _minotaur(delta, dir, dist)
	elif id == "demon_lord":
		want = _lord(dir, dist)
	elif id.begins_with("wrath_"):
		want = _wrath(delta, dir, dist)
	elif SHOOTERS.has(id):
		if dist > 95.0:
			want = dir
		elif dist < 60.0:
			want = -dir
		else:
			want = dir.orthogonal() * (1.0 if int(get_instance_id()) % 2 == 0 else -1.0) * 0.6
		if _shot_cd <= 0.0 and dist < 160.0:
			_shot_cd = randf_range(1.6, 2.2)
			_attack_anim()
			world.enemy_shot(hit_pos(), (p.hit_pos() - hit_pos()).normalized(), 110.0, atk * 0.8, title, Color("b48cff") if id == "wraith" else Color("8fe07a"))
	else:
		want = dir

	# Keep a little room between monsters so they do not stack up.
	for o in world.enemies:
		if o != self and not o.dead:
			var away: Vector2 = global_position - o.global_position
			var l := away.length()
			if l < 14.0 and l > 0.01:
				want += away / l * (14.0 - l) / 14.0
	if _state == "charge":
		velocity = _charge_dir * (300.0 if is_boss() else 190.0)
	else:
		velocity = want.limit_length(1.0) * spd
	velocity += _knock
	_knock = _knock.move_toward(Vector2.ZERO, 600.0 * delta)
	move_and_slide()

	if e.kind == "mini" and absf(velocity.x) > 1.0:
		# Mini sheets face right.
		spr.flip_h = velocity.x < 0.0

	# Contact damage.
	if dist < radius + 6.0 and _atk_cd <= 0.0:
		var power := atk
		if _state == "charge":
			power *= float(e.get("special_mult", 1.5))
		_atk_cd = 0.9
		_attack_anim()
		world.hurt_player(power, title)

	if _flash > 0.0:
		_flash -= delta
		spr.modulate = Color(1, 0.35, 0.35) if _flash > 0.0 else Color.WHITE
	elif _state == "windup":
		spr.modulate = Color(1, 0.6, 0.3) if fmod(_state_t, 0.16) < 0.08 else Color.WHITE
	elif slow_t > 0.0:
		spr.modulate = Color(0.6, 0.85, 1.3)
	else:
		spr.modulate = Color.WHITE


func _minotaur(_delta: float, dir: Vector2, dist: float) -> Vector2:
	match _state:
		"chase":
			if _state_t <= 0.0 and dist < 170.0:
				_state = "windup"
				_state_t = 0.6
				world.say_over(self, "%s!" % e.special, Color("ff9a5a"))
			return dir
		"windup":
			if _state_t <= 0.0:
				_state = "charge"
				_state_t = 0.55
				_charge_dir = dir
				Game.sfx("swing")
			return Vector2.ZERO
		"charge":
			if _state_t <= 0.0:
				# Each charge ends in a shockwave ring; often chains into a second charge.
				var o := hit_pos()
				Game.sfx("explosion")
				world.shake(3.0, 0.25)
				for i in 16:
					world.enemy_shot(o, Vector2.RIGHT.rotated(TAU * i / 16.0), 85.0, atk * 0.5, title, Color("ffb35a"))
				if _combo < 1 and randf() < 0.55:
					_combo += 1
					_state = "windup"
					_state_t = 0.35
				else:
					_combo = 0
					_state = "chase"
					_state_t = randf_range(2.4, 3.4)
			return Vector2.ZERO
	return dir


## Demon lord: three phases, one HP bar each (shared by every life). Phase 1: bullet hell in the room;
## phase 2: levelled-up room patterns with the sin curse; phase 3 crashes the game into
## Windowkill-style windows (stage_map.start_window_phase). Numbers scale with Game.boss_power().
func _lord(dir: Vector2, dist: float) -> Vector2:
	var ph := Game.boss_phase()
	if ph != _phase:
		_phase = ph
		_busy = false
		_state = "chase"
		_state_t = 1.5
		if ph == 3:
			world.start_window_phase(self)
		elif ph == 2:
			world.boss_power_up(self)
		return Vector2.ZERO
	if not _busy and _state_t <= 0.0:
		_busy = true
		_lord_attack(ph)
	if _busy or _state == "charge":
		return Vector2.ZERO
	if dist > 85.0:
		return dir * 0.7
	if dist < 50.0:
		return -dir * 0.7
	return dir.orthogonal() * 0.4


func _wait(t: float) -> bool:
	await get_tree().create_timer(t, false).timeout
	if world.cutscene:
		_busy = false
		return false
	return not dead and is_inside_tree() and not world._ended


func _lord_attack(ph: int) -> void:
	var bp := clampf(Game.boss_power(), 0.55, 1.4)
	var pw := atk * 0.65
	var sp := 0.75 + 0.35 * bp
	var curse := ph >= 2
	var purple := Color("c86bff")
	var red := Color("ff3b6b")
	var col := purple if ph == 1 else red
	var pool := [0, 1, 2]
	if ph == 2:
		pool = [0, 2, 3, 5, 1, 4, 6]
	elif ph == 3:
		pool = [7, 8, 0, 9, 3, 8, 2, 4]
	var pick: int = pool[_pattern % pool.size()]
	_pattern += 1
	_attack_anim()
	match pick:
		0:
			# Twin spirals turning both ways.
			Game.sfx("thunder")
			for step in 34:
				var o := hit_pos()
				for k in 2:
					world.enemy_shot(o, Vector2.RIGHT.rotated(step * 0.27 + PI * k), 80.0 * sp, pw, title, col, curse)
					world.enemy_shot(o, Vector2.RIGHT.rotated(-step * 0.27 + PI * k + 0.5), 80.0 * sp, pw, title, col, curse)
				if not await _wait(0.06):
					return
		1:
			# Wind-up then aimed fan volleys.
			_flash = 0.3
			world.fx_warn(hit_pos(), 14.0, 0.35)
			if not await _wait(0.35):
				return
			Game.sfx("fire")
			for v in (3 if ph == 1 else 5):
				var o := hit_pos()
				var aimv: Vector2 = (world.player.hit_pos() - o).normalized()
				for i in 11:
					world.enemy_shot(o, aimv.rotated((i - 5) * 0.12), 135.0 * sp, pw, title, Color("ff9a3b"), curse)
				if not await _wait(0.2):
					return
		2:
			# Dense rings with a gap that wanders.
			var gap := randf() * TAU
			for ring in 4:
				Game.sfx("thunder")
				var o := hit_pos()
				for i in 40:
					var a := TAU * i / 40.0
					if absf(wrapf(a - gap, -PI, PI)) > 0.42:
						world.enemy_shot(o, Vector2.RIGHT.rotated(a), 70.0 * sp, pw, title, col, curse)
				gap += randf_range(-0.9, 0.9)
				if not await _wait(0.45):
					return
		3:
			# Laser-like bullet lines, telegraphed.
			var o := hit_pos()
			var base: Vector2 = (world.player.hit_pos() - o).normalized()
			var dirs := [base, base.rotated(0.6), base.rotated(-0.6)]
			for d in dirs:
				world.fx_line(o, d, 320.0, 0.6)
			if not await _wait(0.6):
				return
			Game.sfx("explosion")
			for j in 14:
				for d in dirs:
					world.enemy_shot(o, d, (120.0 + j * 16.0) * sp, pw, title, Color("ffe0ff"), curse)
		4:
			# Summon minions behind a ring.
			if world.alive_count() < 5:
				world.say_over(self, "จงลุกขึ้น ข้ารับใช้ของข้า!", Color("d9a0ff"))
				world.summon_minions(2 if ph == 2 else 3)
			var o := hit_pos()
			for i in 24:
				world.enemy_shot(o, Vector2.RIGHT.rotated(TAU * i / 24.0), 90.0 * sp, pw, title, col, curse)
		5:
			# Homing orbs.
			Game.sfx("fire")
			for i in 6:
				world.enemy_shot(hit_pos(), Vector2.RIGHT.rotated(TAU * i / 6.0), 55.0 * sp, pw * 1.2, title, Color("7a3bff"), true, 2.4)
				if not await _wait(0.12):
					return
		6:
			# Curse of rebirth: arena-wide triple ring, the only safe pocket is marked in green.
			world.say_over(self, "คำสาปแห่งการเกิดใหม่!!", Color("ff4a6a"))
			var o := hit_pos()
			var safe := randf() * TAU
			world.fx_safe(o + Vector2.RIGHT.rotated(safe) * 60.0, 22.0, 1.4)
			world.shake(3.0, 1.2)
			if not await _wait(1.4):
				return
			for ring in 3:
				Game.sfx("explosion")
				for i in 64:
					var a := TAU * i / 64.0
					if absf(wrapf(a - safe, -PI, PI)) > 0.3:
						world.enemy_shot(o, Vector2.RIGHT.rotated(a), (60.0 + ring * 22.0) * sp, pw * 1.3, title, Color("ff1a4a"), true)
				if not await _wait(0.25):
					return
		7:
			# Dash across the arena; its window flies with it and every window shakes on impact.
			var aimv: Vector2 = (world.player.global_position - global_position).normalized()
			world.fx_line(hit_pos(), aimv, 260.0, 0.55)
			_flash = 0.5
			if not await _wait(0.55):
				return
			Game.sfx("swing")
			_charge_dir = aimv
			_state = "charge"
			if not await _wait(0.45):
				_state = "chase"
				return
			_state = "chase"
			world.shake_windows(10.0, 0.4)
			Game.sfx("explosion")
			var o := hit_pos()
			for i in 20:
				world.enemy_shot(o, Vector2.RIGHT.rotated(TAU * i / 20.0), 90.0 * sp, pw, title, col, curse)
		8:
			# Special orbs, each living in its own little window, homing in on the hero.
			Game.sfx("fire")
			for i in 3:
				var d := Vector2.RIGHT.rotated(randf() * TAU)
				world.window_orb(hit_pos() + d * 10.0, d, 45.0 * sp, pw * 1.4, title)
				if not await _wait(0.35):
					return
		9:
			# Leap and slam onto the hero's spot (green-free red warning), shockwave ring.
			var target: Vector2 = world.player.global_position
			world.fx_warn(target, 28.0, 0.85)
			_flash = 0.85
			if not await _wait(0.85):
				return
			global_position = world.nearest_open(target, global_position)
			Game.sfx("explosion")
			world.shake_windows(16.0, 0.6)
			world.shake(6.0, 0.4)
			var o := hit_pos()
			for ring in 2:
				for i in 28:
					world.enemy_shot(o, Vector2.RIGHT.rotated(TAU * (i + ring * 0.5) / 28.0), (70.0 + ring * 30.0) * sp, pw, title, col, curse)
	if not await _wait((1.1 if ph == 1 else 0.8 if ph == 2 else 0.7) / bp):
		return
	_busy = false

## Angry villager: bullet hell (ring with a gap, rotating spiral, aimed bursts, double rings).
## Every bullet carries the sin curse.
func _wrath(delta: float, dir: Vector2, dist: float) -> Vector2:
	var o := hit_pos()
	var pw := atk * 0.55
	var red := Color("ff3b6b")
	if _spiral > 0.0:
		_spiral -= delta
		if _shot_cd <= 0.0:
			_shot_cd = 0.07
			_spin += 0.33
			for k in 3:
				world.enemy_shot(o, Vector2.RIGHT.rotated(_spin + TAU * k / 3.0), 85.0, pw, title, red, true)
		return Vector2.ZERO
	if _state_t <= 0.0:
		_state_t = 1.3
		_attack_anim()
		var aimv: Vector2 = (world.player.hit_pos() - o).normalized()
		match _pattern % 4:
			0:
				Game.sfx("thunder")
				var gap := aimv.angle() + randf_range(-0.6, 0.6)
				for i in 26:
					var a := TAU * i / 26.0
					if absf(wrapf(a - gap, -PI, PI)) > 0.45:
						world.enemy_shot(o, Vector2.RIGHT.rotated(a), 75.0, pw, title, red, true)
			1:
				_spiral = 1.5
				_shot_cd = 0.0
			2:
				Game.sfx("fire")
				for i in 9:
					world.enemy_shot(o, aimv.rotated((i - 4) * 0.13), 130.0, pw, title, Color("ff9a3b"), true)
			3:
				var off := randf() * TAU
				for i in 14:
					world.enemy_shot(o, Vector2.RIGHT.rotated(off + TAU * i / 14.0), 60.0, pw, title, red, true)
					world.enemy_shot(o, Vector2.RIGHT.rotated(off + TAU * (i + 0.5) / 14.0), 100.0, pw, title, red, true)
		_pattern += 1
	if dist > 95.0:
		return dir * 0.8
	if dist < 55.0:
		return -dir * 0.8
	return dir.orthogonal() * 0.7


func _attack_anim() -> void:
	if spr.sprite_frames.has_animation("attack"):
		spr.play("attack")
		if not spr.animation_finished.is_connected(_back_to_idle):
			spr.animation_finished.connect(_back_to_idle)


func _back_to_idle() -> void:
	if not dead:
		spr.play("idle")


func hurt(d: int, knock: Vector2) -> void:
	hp = maxi(0, hp - d)
	_flash = 0.12
	if not is_boss() and _state != "charge":
		_knock = knock
	queue_redraw()


func kill() -> void:
	dead = true
	velocity = Vector2.ZERO
	collision_layer = 0
	queue_redraw()
	if spr.sprite_frames.has_animation("die"):
		spr.play("die")
	else:
		Game.spawn_vfx(world, "explosion", hit_pos(), 1.0)
	var tw := create_tween()
	tw.tween_interval(0.6)
	tw.tween_property(self, "modulate:a", 0.0, 0.4)
	tw.tween_callback(queue_free)


func _draw() -> void:
	if dead or is_boss() or hp >= max_hp:
		return
	var w := maxf(14.0, radius * 2.4)
	var y := -height - 5.0
	draw_rect(Rect2(-w / 2.0 - 1, y - 1, w + 2, 4), Color(0, 0, 0, 0.8))
	draw_rect(Rect2(-w / 2.0, y, w * float(hp) / float(max_hp), 2), Game.C_HP)
