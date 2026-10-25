@tool
extends Node2D
## Walkable stage (Soul Knight / Hyper Light Drifter style). The main path (start, fights,
## exit) winds over a grid of room slots; shop / event / grave / rest rooms branch off it as
## dead ends. Combat rooms lock their doors until every wave is dead, side rooms open
## shop.gd / event.gd as an overlay with E, and the portal after the last fight leads on.
## Each stage has its own look: forest, teal ruins, demon castle; side rooms are cozy camps.

const T := 16
const ZOOM := 2.5
const SLOT := Vector2i(34, 24)
const COMBAT := ["battle", "miniboss", "boss"]
const SIDE := ["shop", "event", "grave", "rest"]
const STAGE_THEMES := ["forest", "ruins", "castle"]
const PlayerScript := preload("res://scripts/player.gd")
const EnemyScript := preload("res://scripts/enemy.gd")
const ShotScript := preload("res://scripts/projectile.gd")
const CritterScript := preload("res://scripts/critter.gd")
const ShopScript := preload("res://scripts/shop.gd")
const EventScript := preload("res://scripts/event.gd")
const INTERACT_TEXT := {"shop": "คุยกับพ่อค้า", "event": "ตรวจสอบ", "grave": "ดูหลุมศพ", "rest": "พักที่กองไฟ"}

# 16px floor tiles: [texture, base tiles, accent tiles (flowers, tufts, cracks)].
const FLOORS := {
	"forest": ["tiles/forest.png",
		[Vector2(304, 304), Vector2(320, 304), Vector2(336, 304), Vector2(352, 304), Vector2(320, 320), Vector2(352, 320)],
		[Vector2(304, 336), Vector2(320, 336), Vector2(336, 336), Vector2(352, 336), Vector2(304, 352), Vector2(320, 352),
			Vector2(336, 352), Vector2(352, 352), Vector2(288, 336), Vector2(288, 352), Vector2(288, 304), Vector2(304, 368)]],
	"camp": ["tiles/forest.png",
		[Vector2(192, 304), Vector2(208, 304), Vector2(224, 304), Vector2(240, 304), Vector2(208, 320), Vector2(224, 320)],
		[Vector2(192, 336), Vector2(208, 352), Vector2(224, 336), Vector2(240, 352), Vector2(240, 336), Vector2(208, 336)]],
	"ruins": ["tiles/dungeon.png",
		[Vector2(0, 80), Vector2(0, 80), Vector2(0, 80), Vector2(16, 80)],
		[Vector2(48, 80), Vector2(0, 96), Vector2(48, 96)]],
	"castle": ["tiles/dungeon.png",
		[Vector2(0, 16), Vector2(0, 16), Vector2(0, 16), Vector2(16, 16)],
		[Vector2(48, 16), Vector2(0, 32), Vector2(48, 32)]],
}
const CLEAR := {"forest": Color("0e1f14"), "ruins": Color("0b171c"), "castle": Color("14080f")}
const MOOD := {"forest": Color(0.82, 0.95, 0.85), "ruins": Color(0.68, 0.85, 0.9), "castle": Color(0.82, 0.6, 0.78)}

# Props: [texture, region]. Dungeon and village props are transparent; forest.png ones sit on sand.
const PROPS := {
	"pillar": ["tiles/dungeon.png", Rect2(80, 280, 16, 26)],
	"pillar_b": ["tiles/dungeon.png", Rect2(96, 280, 16, 26)],
	"rubble": ["tiles/dungeon.png", Rect2(112, 192, 32, 32)],
	"rubble_b": ["tiles/dungeon.png", Rect2(144, 192, 32, 32)],
	"chest": ["tiles/dungeon.png", Rect2(224, 254, 16, 18)],
	"pot": ["tiles/dungeon.png", Rect2(256, 255, 16, 17)],
	"pot_b": ["tiles/dungeon.png", Rect2(272, 255, 16, 17)],
	"woodpile": ["tiles/dungeon.png", Rect2(288, 256, 16, 16)],
	"barrel_s": ["tiles/dungeon.png", Rect2(208, 288, 16, 16)],
	"sacks": ["tiles/dungeon.png", Rect2(256, 285, 16, 19)],
	"crates_d": ["tiles/dungeon.png", Rect2(272, 285, 32, 20)],
	"throne": ["tiles/dungeon.png", Rect2(208, 264, 16, 26)],
	"chain": ["tiles/dungeon.png", Rect2(224, 280, 16, 24)],
	"rack": ["tiles/dungeon.png", Rect2(240, 240, 32, 16)],
	"stall": ["props/village.png", Rect2(180, 240, 74, 93)],
	"crate": ["props/village.png", Rect2(180, 177, 28, 32)],
	"barrel": ["props/village.png", Rect2(208, 182, 16, 28)],
	"wagon": ["props/village.png", Rect2(337, 155, 54, 52)],
	"plant": ["props/village.png", Rect2(400, 103, 16, 25)],
	"statue": ["tiles/forest.png", Rect2(208, 368, 32, 48)],
	"tomb": ["tiles/forest.png", Rect2(176, 368, 16, 16)],
}
const TREES := ["props/tree_big.png", "props/tree_medium.png", "props/tree_small.png"]
const FOREST_ANIMALS := [Vector2i(2, 0), Vector2i(3, 0), Vector2i(1, 0), Vector2i(0, 1), Vector2i(3, 1)]

var player
var enemies: Array = []

var _s: Dictionary
var _stage := 0
var _theme := "forest"
var _route: Array = []
var _rooms: Array = []  # {kind, rect: Rect2i (cells), k: route index or -1, main, theme}
var _links: Array = []  # [room a, room b]
var _walk := {}  # Vector2i -> theme name
var _wall := {}  # Vector2i -> theme name
var _closed := {}  # door cells blocked while a fight is on
var _door_body: StaticBody2D
var _props_body: StaticBody2D
var _texs := {}
var _rng := RandomNumberGenerator.new()
var _glow_tex: GradientTexture2D
var _add_mat: CanvasItemMaterial
var _entities: Node2D
var _lights: Node2D
var _shots: Node2D
var _fx: Node2D
var _overlay: CanvasLayer
var _hud
var _room_label: Label
var _prompt: Label
var _boss_box: VBoxContainer
var _boss_bar: ProgressBar
var _boss_label: Label
var _menu: Control
var _npcs: Array = []  # {k, kind, pos, node, moving}
var _near: Dictionary = {}
var _portal: Portal
var _cur_room := -1
var _fight_room := -1
var _waves: Array = []
var _pending := 0
var _ended := false
var _dialog := false
var _boss_dirty := false
var _save_t := 0.0
var _hud_t := 0.0


func _ready() -> void:
	_s = Game.slot()
	_stage = int(_s.stage)
	_theme = STAGE_THEMES[clampi(_stage, 0, 2)]
	_route = _s.route.duplicate()
	# A save whose node ran past the route would skip every room (and the boss) for good.
	if int(_s.node) > _route.size() - 1:
		_s.node = maxi(_route.size() - 1, 0)
	_rng.seed = hash([int(Game.data.loop), int(_s.life), _stage])
	_glow_tex = GradientTexture2D.new()
	_glow_tex.fill = GradientTexture2D.FILL_RADIAL
	_glow_tex.fill_from = Vector2(0.5, 0.5)
	_glow_tex.fill_to = Vector2(1.0, 0.5)
	_glow_tex.width = 64
	_glow_tex.height = 64
	var gr := Gradient.new()
	gr.set_color(0, Color(1, 1, 1, 0.9))
	gr.set_color(1, Color(1, 1, 1, 0.0))
	_glow_tex.gradient = gr
	_add_mat = CanvasItemMaterial.new()
	_add_mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	_build_layout()
	_entities = Node2D.new()
	_entities.y_sort_enabled = true
	add_child(_entities)
	_lights = Node2D.new()
	_lights.z_index = 4
	add_child(_lights)
	_shots = Node2D.new()
	_shots.z_index = 5
	add_child(_shots)
	_fx = Node2D.new()
	_fx.z_index = 6
	add_child(_fx)
	_props_body = StaticBody2D.new()
	_props_body.collision_layer = 1
	add_child(_props_body)
	_decorate()
	_place_npcs()
	_setup_quests()
	_place_pickups()
	_register_targets()
	var spawn := _spawn_point()
	if Engine.is_editor_hint():
		var h := Game.hero_sprite(_s.cls, 1.0)
		h.position = spawn + Vector2(0, -14)
		_entities.add_child(h)
		return

	# The stage keeps reading input while paused (menu, overlays); the world itself pauses.
	process_mode = Node.PROCESS_MODE_ALWAYS
	for n in [_entities, _lights, _shots, _fx]:
		n.process_mode = Node.PROCESS_MODE_PAUSABLE
	RenderingServer.set_default_clear_color(CLEAR[_theme])
	var mood := CanvasModulate.new()
	mood.color = MOOD[_theme]
	add_child(mood)
	var st: Dictionary = Game.STAGES[_stage]
	Game.play_bgm(st.bgm)
	player = PlayerScript.new()
	player.position = spawn
	_entities.add_child(player)
	player.setup(self, _s)
	var cam := Camera2D.new()
	cam.zoom = Vector2(ZOOM, ZOOM)
	cam.position_smoothing_enabled = true
	cam.position_smoothing_speed = 8.0
	var b := _bounds()
	cam.limit_left = int(b.position.x)
	cam.limit_top = int(b.position.y)
	cam.limit_right = int(b.end.x)
	cam.limit_bottom = int(b.end.y)
	player.add_child(cam)
	_build_ui()
	if int(_s.node) == 0:
		_banner(st.name)


func _tex(path: String) -> Texture2D:
	if not _texs.has(path):
		_texs[path] = Game.tex(path)
	return _texs[path]


# ---------------------------------------------------------------- layout
func _build_layout() -> void:
	var kinds: Array = ["start"]
	kinds.append_array(_route)
	if _stage < Game.STAGES.size() - 1:
		kinds.append("exit")
	var main: Array = []
	var parent := {}
	for i in kinds.size():
		if SIDE.has(kinds[i]):
			parent[i] = main.back()
		else:
			main.append(i)
	# Optional villager rooms for the NPC quests (not route nodes); no shop on the last stage.
	if _stage < Game.STAGES.size() - 1:
		for q in 3:
			parent[kinds.size()] = main[_rng.randi_range(0, main.size() - 1)]
			kinds.append("quest")

	# Random walk for the main path, then a free neighbour slot for every side room.
	var pos := {}
	for attempt in 60:
		pos.clear()
		var used := {}
		var cur := Vector2i.ZERO
		var ok := true
		for j in main.size():
			if j > 0:
				var opts := []
				for d in [Vector2i.RIGHT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT]:
					var n: Vector2i = cur + d
					if not used.has(n) and _free_around(used, n) >= 2:
						opts.append(n)
				if opts.is_empty():
					ok = false
					break
				cur = opts[_rng.randi() % opts.size()]
			used[cur] = true
			pos[main[j]] = cur
		if ok:
			for i in parent:
				var dirs := [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]
				var turn := _rng.randi() % 4
				var placed := false
				for di in 4:
					var n: Vector2i = pos[parent[i]] + dirs[(di + turn) % 4]
					if not used.has(n):
						used[n] = true
						pos[i] = n
						placed = true
						break
				if not placed:
					ok = false
					break
		if ok:
			break

	for i in kinds.size():
		var kind: String = kinds[i]
		var sz := Vector2i(18 + _rng.randi_range(-2, 2), 11 + _rng.randi_range(-1, 1))
		match kind:
			"start", "exit":
				sz = Vector2i(12, 9)
			"shop", "event", "grave", "rest":
				sz = Vector2i(14, 10)
			"quest":
				sz = Vector2i(12, 9)
			"miniboss":
				sz = Vector2i(22, 13)
			"boss":
				sz = Vector2i(26, 15)
		var c: Vector2i = pos.get(i, Vector2i(i, 0)) * SLOT
		var r := Rect2i(c - sz / 2, sz)
		var side: bool = SIDE.has(kind) or kind == "quest"
		_rooms.append({"kind": kind, "rect": r, "k": -1 if kind in ["start", "exit", "quest"] else i - 1,
			"main": not side, "theme": "camp" if side else _theme, "slot": pos.get(i, Vector2i(i, 0))})
		_fill(r, _rooms[i].theme)
	for j in range(1, main.size()):
		_links.append([main[j - 1], main[j]])
	for i in parent:
		_links.append([parent[i], i])
	for l in _links:
		_corridor(l[0], l[1])

	for c in _walk:
		for dy in [-1, 0, 1]:
			for dx in [-1, 0, 1]:
				var n: Vector2i = c + Vector2i(dx, dy)
				if not _walk.has(n) and not _wall.has(n):
					_wall[n] = _walk[c]
	# One static body for every wall, one box per horizontal run of wall cells.
	var body := StaticBody2D.new()
	body.collision_layer = 1
	add_child(body)
	var rows := {}
	for c in _wall:
		if not rows.has(c.y):
			rows[c.y] = []
		rows[c.y].append(c.x)
	for y in rows:
		var xs: Array = rows[y]
		xs.sort()
		var start: int = xs[0]
		for j in range(1, xs.size() + 1):
			if j == xs.size() or xs[j] != xs[j - 1] + 1:
				_add_box(body, Rect2(Vector2(start, y) * T, Vector2(xs[j - 1] - start + 1, 1) * T))
				if j < xs.size():
					start = xs[j]
	_door_body = StaticBody2D.new()
	_door_body.collision_layer = 1
	add_child(_door_body)


func _free_around(used: Dictionary, c: Vector2i) -> int:
	var n := 0
	for d in [Vector2i.RIGHT, Vector2i.LEFT, Vector2i.UP, Vector2i.DOWN]:
		if not used.has(c + d):
			n += 1
	return n


## Straight 3-wide corridor between two rooms in neighbouring slots (rooms share a centre line).
func _corridor(a: int, b: int) -> void:
	var ra: Rect2i = _rooms[a].rect
	var rb: Rect2i = _rooms[b].rect
	var sa: Vector2i = _rooms[a].slot
	var sb: Vector2i = _rooms[b].slot
	if sa.y == sb.y:
		var cy := sa.y * SLOT.y
		var x0 := mini(ra.end.x, rb.end.x)
		var x1 := maxi(ra.position.x, rb.position.x)
		_fill(Rect2i(x0, cy - 1, x1 - x0, 3), _theme, false)
	else:
		var cx := sa.x * SLOT.x
		var y0 := mini(ra.end.y, rb.end.y)
		var y1 := maxi(ra.position.y, rb.position.y)
		_fill(Rect2i(cx - 1, y0, 3, y1 - y0), _theme, false)


func _fill(r: Rect2i, theme: String, overwrite := true) -> void:
	for y in range(r.position.y, r.end.y):
		for x in range(r.position.x, r.end.x):
			var c := Vector2i(x, y)
			if overwrite or not _walk.has(c):
				_walk[c] = theme


func _add_box(body: StaticBody2D, rect: Rect2) -> void:
	var col := CollisionShape2D.new()
	var sh := RectangleShape2D.new()
	sh.size = rect.size
	col.shape = sh
	col.position = rect.get_center()
	body.add_child(col)


func _bounds() -> Rect2:
	var r := Rect2()
	var first := true
	for c in _wall:
		var cell := Rect2(Vector2(c) * T, Vector2(T, T))
		r = cell if first else r.merge(cell)
		first = false
	return r.grow(T * 3)


func _center(i: int) -> Vector2:
	var r: Rect2i = _rooms[i].rect
	return (Vector2(r.position) + Vector2(r.size) / 2.0) * T


func _door_cells(i: int) -> Array:
	var r: Rect2i = _rooms[i].rect
	var out := []
	var g := r.grow(1)
	for y in range(g.position.y, g.end.y):
		for x in range(g.position.x, g.end.x):
			var c := Vector2i(x, y)
			if not r.has_point(c) and _walk.has(c):
				out.append(c)
	return out


func _lock(i: int, on: bool) -> void:
	for c in _door_body.get_children():
		c.queue_free()
	_closed.clear()
	if on:
		for c in _door_cells(i):
			_closed[c] = true
			_add_box(_door_body, Rect2(Vector2(c) * T, Vector2(T, T)))
		Game.sfx("explosion")
	queue_redraw()


# ---------------------------------------------------------------- drawing
func _draw() -> void:
	if _texs.is_empty() and Engine.is_editor_hint() and _walk.is_empty():
		return
	for c in _walk:
		var th: String = _walk[c]
		var f: Array = FLOORS[th]
		var h := absi(c.x * 73856093 ^ c.y * 19349663)
		var tiles: Array = f[2] if h % 100 < (14 if th == "forest" else 8) else f[1]
		var rr := Rect2(Vector2(c) * T, Vector2(T, T))
		draw_texture_rect_region(_tex(f[0]), rr, Rect2(tiles[(h / 100) % tiles.size()], Vector2(16, 16)))
		if _wall.has(c + Vector2i(0, -1)):
			draw_rect(Rect2(rr.position, Vector2(T, 5)), Color(0, 0, 0, 0.35))
	var dung := _tex("tiles/dungeon.png")
	var bushes := [_tex("props/bush1.png"), _tex("props/bush2.png")]
	for c in _wall:
		var th: String = _wall[c]
		var rr := Rect2(Vector2(c) * T, Vector2(T, T))
		if th == "forest" or th == "camp":
			draw_rect(rr, Color("13261a"))
		elif _walk.has(c + Vector2i(0, 1)):
			draw_texture_rect_region(dung, rr, Rect2(Vector2(112 if th == "ruins" else 32, 128), Vector2(16, 16)))
		else:
			draw_rect(rr, Color("17121e") if th == "castle" else Color("10191c"))
			var rim := Color(0.45, 0.6, 0.62) if th == "ruins" else Color(0.5, 0.38, 0.55)
			if _walk.has(c + Vector2i(0, -1)):
				draw_rect(Rect2(rr.position, Vector2(T, 3)), rim)
			if _walk.has(c + Vector2i(1, 0)):
				draw_rect(Rect2(rr.position + Vector2(T - 2, 0), Vector2(2, T)), rim)
			if _walk.has(c + Vector2i(-1, 0)):
				draw_rect(Rect2(rr.position, Vector2(2, T)), rim)
	# Hedge of bushes along every foliage wall, slightly spilling over the floor edge.
	for c in _wall:
		var th: String = _wall[c]
		if th != "forest" and th != "camp":
			continue
		var h := absi(c.x * 92837111 ^ c.y * 689287499)
		var sz := 20.0 + float(h % 7)
		var p := Vector2(c) * T + Vector2(T, T) / 2.0 - Vector2(sz, sz) / 2.0 + Vector2(float(h % 5) - 2.0, -3.0)
		draw_texture_rect(bushes[h % 2], Rect2(p, Vector2(sz, sz)), false, Color(0.75, 0.9, 0.75) if h % 3 == 0 else Color.WHITE)
	for c in _closed:
		var rr := Rect2(Vector2(c) * T, Vector2(T, T))
		draw_rect(rr, Color(0.1, 0.07, 0.04, 0.85))
		for k in 3:
			draw_line(rr.position + Vector2(3 + k * 5, 0), rr.position + Vector2(3 + k * 5, T), Game.C_BORDER, 2.0)


# ---------------------------------------------------------------- decoration
func _prop(name: String, pos: Vector2, sc := 1.0, solid := 0.0, parent: Node = null) -> Sprite2D:
	var p: Array = PROPS[name]
	var s := Sprite2D.new()
	s.texture = _tex(p[0])
	s.region_enabled = true
	s.region_rect = p[1]
	s.centered = false
	var r: Rect2 = p[1]
	s.offset = Vector2(-r.size.x / 2.0, -r.size.y + 2.0)
	s.scale = Vector2(sc, sc)
	s.position = pos
	(parent if parent else _entities).add_child(s)
	if solid > 0.0:
		_solid(pos, solid)
	return s


func _tree(path: String, pos: Vector2, sc: float, solid := 0.0) -> void:
	var s := Sprite2D.new()
	s.texture = _tex(path)
	s.centered = false
	s.offset = Vector2(-s.texture.get_width() / 2.0, -s.texture.get_height() * 0.93)
	s.scale = Vector2(sc, sc)
	s.position = pos
	_entities.add_child(s)
	if solid > 0.0:
		_solid(pos, solid)


func _solid(pos: Vector2, r: float) -> void:
	var col := CollisionShape2D.new()
	var sh := CircleShape2D.new()
	sh.radius = r
	col.shape = sh
	col.position = pos + Vector2(0, -2)
	_props_body.add_child(col)


func glow(pos: Vector2, color: Color, radius: float) -> Sprite2D:
	var g := Sprite2D.new()
	g.texture = _glow_tex
	g.material = _add_mat
	g.modulate = color
	g.scale = Vector2.ONE * (radius / 32.0)
	g.position = pos
	_lights.add_child(g)
	return g


func _critter(sheet: String, fw: int, fh: int, block: Vector2i, i: int) -> void:
	var c = CritterScript.new()
	c.world = self
	c.setup_animal(sheet, fw, fh, block)
	var r: Rect2i = _rooms[i].rect.grow(-1)
	c.area = Rect2(Vector2(r.position) * T, Vector2(r.size) * T)
	c.position = c.area.position + Vector2(_rng.randf(), _rng.randf()) * c.area.size
	_entities.add_child(c)


## A cell away from the room's centre lines (corridors attach there) and its middle.
func _spot(i: int, margin := 2) -> Vector2:
	var r: Rect2i = _rooms[i].rect.grow(-margin)
	var ctr: Vector2i = _rooms[i].rect.get_center()
	for t in 40:
		var c := Vector2i(_rng.randi_range(r.position.x, r.end.x - 1), _rng.randi_range(r.position.y, r.end.y - 1))
		if absi(c.x - ctr.x) >= 3 and absi(c.y - ctr.y) >= 2:
			return (Vector2(c) + Vector2(0.5, 0.9)) * T
	return (Vector2(r.position) + Vector2(1, 1)) * T


## A cell along the inner edge of the room (for clutter that hugs the walls).
func _edge_spot(i: int) -> Vector2:
	var r: Rect2i = _rooms[i].rect
	var ctr := r.get_center()
	for t in 40:
		var c: Vector2i
		match _rng.randi() % 4:
			0:
				c = Vector2i(_rng.randi_range(r.position.x, r.end.x - 1), r.position.y)
			1:
				c = Vector2i(_rng.randi_range(r.position.x, r.end.x - 1), r.end.y - 1)
			2:
				c = Vector2i(r.position.x, _rng.randi_range(r.position.y, r.end.y - 1))
			_:
				c = Vector2i(r.end.x - 1, _rng.randi_range(r.position.y, r.end.y - 1))
		if absi(c.x - ctr.x) >= 3 and absi(c.y - ctr.y) >= 3:
			return (Vector2(c) + Vector2(0.5, 0.9)) * T
	return _center(i)


func _decorate() -> void:
	for i in _rooms.size():
		var room: Dictionary = _rooms[i]
		var r: Rect2i = room.rect
		var big: bool = r.size.x >= 17
		match room.theme:
			"forest":
				for n in (2 if big else 1):
					_tree(TREES[2 if n == 0 else 1], _spot(i, 3), _rng.randf_range(0.22, 0.28), 5.0)
				for n in 4:
					var b := _prop_bush(_edge_spot(i))
				# Animals only outside fights, they distract during combat.
				for n in (0 if COMBAT.has(room.kind) else 2):
					_critter("animals/critters.png", 42, 36, FOREST_ANIMALS[_rng.randi() % FOREST_ANIMALS.size()], i)
				for n in 2:
					glow(_edge_spot(i), Color(0.3, 0.9, 0.8, 0.35), 18.0)
				_fireflies(i, Color(0.85, 1.0, 0.45))
			"ruins":
				if big:
					for n in 2:
						_prop(["pillar", "pillar_b"][n], _spot(i, 3), 1.0, 5.0)
				for n in 4:
					_prop(["pot", "pot_b", "crates_d", "barrel_s", "sacks", "rubble"].pick_random(), _edge_spot(i), 0.8 if n == 3 else 1.0)
				_torches(i, Color(1.0, 0.6, 0.25, 0.8))
				for n in 3:
					glow(_spot(i, 1), Color(0.2, 0.9, 0.9, 0.45), 22.0)
				if not COMBAT.has(room.kind):
					_critter("animals/critters.png", 42, 36, Vector2i(0, 0), i)
			"castle":
				if big:
					for n in 2:
						_prop("pillar", _spot(i, 3), 1.0, 5.0)
				for n in 3:
					var sk := _prop(["pot", "chain", "rubble_b", "rack"].pick_random(), _edge_spot(i))
					sk.modulate = Color(0.85, 0.75, 0.9)
				_torches(i, Color(1.0, 0.25, 0.55, 0.85))
				for n in 3:
					glow(_spot(i, 1), Color(0.9, 0.1, 0.3, 0.4), 26.0)
				if room.kind == "boss":
					var tp := _center(i) + Vector2(0, -(r.size.y / 2.0 - 1.5) * T)
					_prop("throne", tp, 1.6)
					glow(tp + Vector2(0, -16), Color(0.8, 0.2, 1.0, 0.7), 60.0)
			"camp":
				for n in 2:
					var lp := _edge_spot(i)
					glow(lp + Vector2(0, -6), Color(1.0, 0.75, 0.4, 0.55), 30.0)
					_prop("barrel", lp, 0.8)
				for n in 3:
					_prop(["crate", "sacks", "pot", "plant"].pick_random(), _edge_spot(i), 0.8)
				_fireflies(i, Color(1.0, 0.85, 0.5))
	_outer_trees()


func _prop_bush(pos: Vector2) -> Sprite2D:
	var s := Sprite2D.new()
	s.texture = _tex(["props/bush1.png", "props/bush2.png"].pick_random())
	s.scale = Vector2.ONE * _rng.randf_range(0.22, 0.3)
	s.offset = Vector2(0, -26)
	s.position = pos
	_entities.add_child(s)
	return s


## Wall torches (animated) on the top wall of a dungeon room, each with a warm glow.
func _torches(i: int, color: Color) -> void:
	var r: Rect2i = _rooms[i].rect
	var t := _tex("tiles/dungeon.png")
	var sf := SpriteFrames.new()
	sf.set_animation_speed("default", 8.0)
	for x in [0, 16, 32, 48]:
		var at := AtlasTexture.new()
		at.atlas = t
		at.region = Rect2(x, 240, 16, 20)
		sf.add_frame("default", at)
	var x := r.position.x + 2
	while x < r.end.x - 1:
		var c := Vector2i(x, r.position.y - 1)
		if _wall.has(c) and absi(x - r.get_center().x) >= 3:
			var a := AnimatedSprite2D.new()
			a.sprite_frames = sf
			a.position = (Vector2(c) + Vector2(0.5, 0.4)) * T
			a.z_index = 1
			add_child(a)
			a.play()
			a.frame = _rng.randi() % 4
			glow(a.position + Vector2(0, 10), color, 34.0)
		x += _rng.randi_range(4, 6)


func _fireflies(i: int, color: Color) -> void:
	var p := CPUParticles2D.new()
	var r: Rect2i = _rooms[i].rect
	p.position = _center(i)
	p.amount = 10
	p.lifetime = 4.0
	p.preprocess = 4.0
	p.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	p.emission_rect_extents = Vector2(r.size) * T / 2.0
	p.direction = Vector2.UP
	p.spread = 180.0
	p.gravity = Vector2.ZERO
	p.initial_velocity_min = 3.0
	p.initial_velocity_max = 9.0
	p.texture = _glow_tex
	p.material = _add_mat
	p.scale_amount_min = 0.05
	p.scale_amount_max = 0.1
	var ramp := Gradient.new()
	ramp.set_color(0, Color(color, 0.0))
	ramp.add_point(0.5, Color(color, 0.9))
	ramp.set_color(ramp.get_point_count() - 1, Color(color, 0.0))
	p.color_ramp = ramp
	_lights.add_child(p)


## Trees around the forest (and around every camp): a dense canopy outside the walls,
## kept clear of the rooms' southern edges so they never hide the hero.
func _outer_trees() -> void:
	var dist := {}
	var frontier: Array = _walk.keys()
	for c in frontier:
		dist[c] = 0
	var d := 0
	while d < 6:
		d += 1
		var nxt: Array = []
		for c in frontier:
			for o in [Vector2i.RIGHT, Vector2i.LEFT, Vector2i.UP, Vector2i.DOWN]:
				var n: Vector2i = c + o
				if not dist.has(n):
					dist[n] = d
					nxt.append(n)
		frontier = nxt
	var taken := {}
	var cells: Array = dist.keys()
	cells.sort()
	for c in cells:
		var dd: int = dist[c]
		if dd < 2 or taken.has(c) or _rng.randf() > 0.45:
			continue
		var th := _near_theme(c)
		if th != "forest" and th != "camp":
			continue
		var blocked := false
		for y in range(c.y - 7, c.y):
			for x in range(c.x - 2, c.x + 3):
				if _walk.has(Vector2i(x, y)):
					blocked = true
		var p := (Vector2(c) + Vector2(0.5, 1.0)) * T
		if blocked:
			var low := false
			for x in range(c.x - 1, c.x + 2):
				if _walk.has(Vector2i(x, c.y - 1)) or _walk.has(Vector2i(x, c.y - 2)):
					low = true
			if not low and _rng.randf() < 0.5:
				_prop_bush(p)
			continue
		_tree(TREES[0] if dd >= 4 else TREES[_rng.randi_range(1, 2)], p, _rng.randf_range(0.26, 0.36))
		for y in range(-2, 3):
			for x in range(-2, 3):
				taken[c + Vector2i(x, y)] = true


func _near_theme(c: Vector2i) -> String:
	for r in range(1, 8):
		for o in [Vector2i(r, 0), Vector2i(-r, 0), Vector2i(0, r), Vector2i(0, -r)]:
			if _walk.has(c + o):
				return _walk[c + o]
	return ""


func _place_npcs() -> void:
	var kinds: Dictionary = _s.get("event_kinds", {})
	for i in _rooms.size():
		var room: Dictionary = _rooms[i]
		var pos := _center(i)
		if room.kind == "exit":
			_portal = Portal.new()
			_portal.position = pos
			add_child(_portal)
			glow(pos, Color(0.55, 0.35, 1.0, 0.6), 40.0)
			continue
		if not INTERACT_TEXT.has(room.kind):
			continue
		var n: Node2D
		var anchor := pos
		var moving := false
		match room.kind:
			"shop":
				var m := Game.npc_sprite("merchant", 1.0)
				m.position = pos + Vector2(-4, -14)
				_entities.add_child(m)
				_prop("stall", pos + Vector2(0, 2), 0.7)
				_prop("crate", pos + Vector2(-34, 4), 0.7)
				_prop("barrel", pos + Vector2(32, 2), 0.7)
				_prop("plant", pos + Vector2(26, -30), 0.7)
				glow(pos + Vector2(0, -20), Color(1.0, 0.8, 0.45, 0.6), 46.0)
				for k in 2:
					_critter("animals/birds.png", 42, 36, Vector2i(k, 0), i)
				_critter("animals/pets.png", 26, 36, Vector2i(_rng.randi() % 4, 1), i)
				n = m
				anchor = pos + Vector2(0, 16)
			"grave":
				var g := _grave()
				_prop("tomb", pos + Vector2(0, -10), 1.2)
				var h := Game.hero_sprite(g.get("cls", "knight"), 1.0)
				h.play("die")
				h.frame = h.sprite_frames.get_frame_count("die") - 1
				h.pause()
				h.modulate = Color(0.5, 0.6, 0.8, 0.8)
				h.position = pos + Vector2(0, -4)
				_entities.add_child(h)
				glow(pos, Color(0.4, 0.6, 1.0, 0.5), 36.0)
				n = h
			"rest":
				var w := _prop("woodpile", pos, 1.0)
				_campfire(pos)
				n = w
			_:
				var k := str(room.k)
				if not kinds.has(k):
					var roll := _rng.randf()
					if _stage == 0:
						kinds[k] = "beggar" if roll < 0.6 else ("shrine" if roll < 0.8 else "chest")
					else:
						kinds[k] = ["beggar", "shrine", "chest"][_rng.randi() % 3]
					_s.event_kinds = kinds
				match kinds[k]:
					"beggar":
						var b = CritterScript.new()
						b.world = self
						b.setup_npc(Game.strip_frames("npcs/beggar.png", 26, 36), 0.9)
						var rr: Rect2i = room.rect.grow(-3)
						b.area = Rect2(Vector2(rr.position) * T, Vector2(rr.size) * T)
						b.position = pos
						_entities.add_child(b)
						n = b
						moving = true
					"shrine":
						n = _prop("statue", pos, 1.0, 6.0)
						glow(pos + Vector2(0, -20), Color(0.6, 0.5, 1.0, 0.7), 44.0)
					_:
						n = _prop("chest", pos, 1.3)
						glow(pos + Vector2(0, -6), Color(1.0, 0.85, 0.3, 0.6), 30.0)
		if Game.is_used(room.k):
			n.modulate = Color(0.45, 0.45, 0.5, 0.75)
		_npcs.append({"k": room.k, "kind": room.kind, "pos": anchor, "node": n, "moving": moving})


func _campfire(pos: Vector2) -> void:
	var p := CPUParticles2D.new()
	p.position = pos + Vector2(0, -6)
	p.amount = 18
	p.lifetime = 0.8
	p.emission_shape = CPUParticles2D.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = 3.0
	p.direction = Vector2.UP
	p.spread = 25.0
	p.gravity = Vector2(0, -12)
	p.initial_velocity_min = 10.0
	p.initial_velocity_max = 20.0
	p.texture = _glow_tex
	p.material = _add_mat
	p.scale_amount_min = 0.08
	p.scale_amount_max = 0.16
	var ramp := Gradient.new()
	ramp.set_color(0, Color(1.0, 0.85, 0.3, 1.0))
	ramp.set_color(1, Color(1.0, 0.2, 0.05, 0.0))
	p.color_ramp = ramp
	_lights.add_child(p)
	var g := glow(pos + Vector2(0, -6), Color(1.0, 0.55, 0.2, 0.75), 56.0)
	if not Engine.is_editor_hint():
		var tw := g.create_tween().set_loops()
		tw.tween_property(g, "modulate:a", 0.5, 0.3)
		tw.tween_property(g, "modulate:a", 0.8, 0.25)


func _grave() -> Dictionary:
	for g in Game.data.graves:
		if int(g.stage) == _stage:
			return g
	return {}


# ---------------------------------------------------------------- quests
const QUEST_GIVERS := [["ป้าทอผ้า", "merchant", Color(1.0, 0.8, 0.9)], ["ลุงคนตัดไม้", "beggar", Color(0.8, 1.0, 0.8)],
	["หนูน้อยมะลิ", "merchant", Color(0.8, 0.9, 1.2)], ["ยายเก็บสมุนไพร", "beggar", Color(1.1, 1.0, 0.75)]]
const QUEST_RECEIVERS := [["ท่านผู้ใหญ่บ้าน", "king"], ["ช่างตีเหล็ก", "merchant"], ["พระธุดงค์", "beggar"]]
const PARCELS := [["ห่อผ้าไหม", "icons/scroll.png"], ["จดหมายฉบับสำคัญ", "icons/scroll.png"], ["ยาสมุนไพร", "icons/elixir.png"]]
const LOST_ITEMS := [["กุญแจบ้าน", "icons/key.png"], ["มงกุฎดอกไม้", "icons/crown.png"], ["ขวดยาวิเศษ", "icons/potion.png"]]

var _quests: Array = []  # {type, giver_room, target_room, giver, target, item, icon, reward, marks}
var _quest_label: Label


## Two small jobs per stage from villagers in the "quest" rooms: a delivery and a lost item.
## Their progress lives in slot.quest_state ("offer" -> "carry"/"active" -> "done").
func _setup_quests() -> void:
	var qrooms := []
	for i in _rooms.size():
		if _rooms[i].kind == "quest":
			qrooms.append(i)
	if qrooms.size() < 3:
		return
	# Own seed so the villagers and items are the same after every reload.
	_rng.seed = hash([int(Game.data.loop), int(_s.life), _stage, "quests"])
	var g1: Array = QUEST_GIVERS[_rng.randi() % 2]
	var g2: Array = QUEST_GIVERS[2 + _rng.randi() % 2]
	var rc: Array = QUEST_RECEIVERS[_rng.randi() % QUEST_RECEIVERS.size()]
	var parcel: Array = PARCELS[_rng.randi() % PARCELS.size()]
	var lost: Array = LOST_ITEMS[_rng.randi() % LOST_ITEMS.size()]
	var spots := []
	for i in _rooms.size():
		if _rooms[i].main and _rooms[i].kind != "start":
			spots.append(i)
	var lost_room: int = spots[_rng.randi() % spots.size()]
	_quests = [
		{"type": "deliver", "giver_room": qrooms[0], "target_room": qrooms[1], "giver": g1[0], "target": rc[0],
			"item": parcel[0], "icon": parcel[1], "reward": 40 + 25 * _stage},
		{"type": "lost", "giver_room": qrooms[2], "target_room": lost_room, "giver": g2[0], "target": "",
			"item": lost[0], "icon": lost[1], "reward": 50 + 25 * _stage},
	]
	var npc_looks := [g1, g2]
	for qi in _quests.size():
		var q: Dictionary = _quests[qi]
		var look: Array = npc_looks[qi]
		var gp := _center(q.giver_room)
		var gs := Game.npc_sprite(look[1], 1.0)
		gs.modulate = look[2]
		gs.position = gp + Vector2(0, -16)
		_entities.add_child(gs)
		_npcs.append({"k": -1, "kind": "quest", "qi": qi, "role": "giver", "pos": gp, "node": gs, "moving": false, "name": q.giver, "sheet": look[1]})
		if q.type == "deliver":
			var tp := _center(q.target_room)
			var ts := Game.npc_sprite(rc[1], 1.0)
			ts.position = tp + Vector2(0, -16)
			_entities.add_child(ts)
			_npcs.append({"k": -1, "kind": "quest", "qi": qi, "role": "receiver", "pos": tp, "node": ts, "moving": false, "name": q.target, "sheet": rc[1]})
		else:
			var ip := _edge_spot(q.target_room)
			var it := Sprite2D.new()
			it.texture = _tex(q.icon)
			it.scale = Vector2.ONE * (14.0 / it.texture.get_width())
			it.position = ip + Vector2(0, -6)
			_entities.add_child(it)
			var gl := glow(ip, Color(1.0, 0.9, 0.4, 0.7), 22.0)
			it.set_meta("glow", gl)
			_npcs.append({"k": -1, "kind": "quest", "qi": qi, "role": "item", "pos": ip, "node": it, "moving": false})
	_refresh_quests()


func _room_name(i: int) -> String:
	var kind: String = _rooms[i].kind
	if kind == "exit":
		return "ประตูมิติ"
	if kind == "start":
		return "จุดเริ่มต้น"
	return Game.NODE_INFO[kind].name if Game.NODE_INFO.has(kind) else kind


func _qstate(qi: int) -> String:
	return str(_s.get("quest_state", {}).get(str(qi), "offer"))


func _set_qstate(qi: int, st: String) -> void:
	if not _s.has("quest_state"):
		_s.quest_state = {}
	_s.quest_state[str(qi)] = st
	Game.save_game()
	_refresh_quests()


func _quest_usable(n: Dictionary) -> bool:
	var st := _qstate(n.qi)
	match n.role:
		"giver":
			return st != "done" and st != "failed"
		"receiver":
			return st == "carry"
		_:
			return st == "active"


## Markers over quest NPCs (! = new job, ? = ready to hand in), the lost item's visibility
## and the quest list under the HUD.
func _refresh_quests() -> void:
	var lines := []
	for n in _npcs:
		if n.kind != "quest":
			continue
		var q: Dictionary = _quests[n.qi]
		var st := _qstate(n.qi)
		if n.role == "item":
			n.node.visible = st == "active"
			n.node.get_meta("glow").visible = st == "active"
			continue
		var mark := ""
		if n.role == "giver" and st == "offer":
			mark = "!"
		elif (n.role == "receiver" and st == "carry") or (n.role == "giver" and q.type == "lost" and st == "carry"):
			mark = "?"
		if not n.has("mark"):
			var l := Game.label("", 30, Color("ffe066"))
			l.add_theme_constant_override("outline_size", 8)
			l.scale = Vector2(0.4, 0.4)
			l.position = n.pos + Vector2(-4, -50)
			_fx.add_child(l)
			n.mark = l
		n.mark.text = mark
	for qi in _quests.size():
		var q: Dictionary = _quests[qi]
		match _qstate(qi):
			"carry":
				lines.append("• นำ%sไปส่ง%s" % [q.item, q.target] if q.type == "deliver" else "• นำ%sกลับไปให้%s" % [q.item, q.giver])
			"active":
				lines.append("• ตามหา%sของ%s (แถว%s)" % [q.item, q.giver, _room_name(q.target_room)])
			"done":
				lines.append("• [เสร็จแล้ว] งานของ%s" % q.giver)
			"failed":
				lines.append("• [ล้มเหลว] งานของ%s" % q.giver)
	if _quest_label:
		_quest_label.text = ("เควส\n" + "\n".join(lines)) if not lines.is_empty() else ""


func _quest_talk(n: Dictionary) -> void:
	var qi: int = n.qi
	var q: Dictionary = _quests[qi]
	var st := _qstate(qi)
	match [q.type, n.role, st]:
		["deliver", "giver", "offer"]:
			_dialog_box(q.giver, "ช่วยเอา%sไปส่งให้%sที่บ้านอีกหลังหน่อยได้ไหม ข้าเดินไม่ไหวแล้ว จะให้ค่าเดินทาง %dG" % [q.item, q.target, q.reward],
				[["รับงาน", func(): _accept_delivery(qi)], ["ไว้ก่อน", Callable()]])
		["deliver", "giver", _]:
			_dialog_box(q.giver, "%sรออยู่นะ ฝากด้วยล่ะ" % q.target, [["ตกลง", Callable()]])
		["deliver", "receiver", "carry"]:
			_dialog_box(q.target, "อ้อ %sจาก%sนี่เอง ขอบใจมาก นี่ค่าเหนื่อย" % [q.item, q.giver],
				[["รับเงิน %dG" % q.reward, func(): _quest_reward(qi, n)]])
		["lost", "giver", "offer"]:
			_dialog_box(q.giver, "ฮือ... %sหายไปแถว%s ข้างในมีมอนสเตอร์ด้วย ช่วยตามหาให้หน่อยได้ไหม" % [q.item, _room_name(q.target_room)],
				[["ช่วยหา", func(): _set_qstate(qi, "active")], ["ไว้ก่อน", Callable()]])
		["lost", "giver", "active"]:
			_dialog_box(q.giver, "ยังหา%sไม่เจอเลยหรือ... มันส่องแสงวิบวับอยู่นะ" % q.item, [["ตกลง", Callable()]])
		["lost", "giver", "carry"]:
			_dialog_box(q.giver, "%sของข้า! ขอบคุณมากเลย รับนี่ไปนะ" % q.item, [["รับเงิน %dG + ยา 1 ขวด" % q.reward, func(): _quest_reward(qi, n)]])
		["lost", "item", "active"]:
			Game.sfx("coin")
			say_over(player, "พบ %s!" % q.item, Color("ffe066"))
			_set_qstate(qi, "carry")


func _accept_delivery(qi: int) -> void:
	_set_qstate(qi, "carry")
	say_over(player, "ได้รับ %s" % _quests[qi].item, Color("ffe066"))


func _quest_reward(qi: int, n: Dictionary) -> void:
	var q: Dictionary = _quests[qi]
	_s.gold = int(_s.gold) + int(q.reward)
	if q.type == "lost" and not Game.add_item("potion"):
		_s.gold = int(_s.gold) + 15
	# Helping villagers is a good deed that follows you into the next life.
	Game.data.karma = clampi(int(Game.data.karma) + 1, -3, 3)
	_s.deeds.append("good")
	if Game.gain_xp(15) > 0:
		player.mp = float(_s.mp)
		say_over(player, "LEVEL UP! Lv%d" % _s.lv, Color("7ad66b"))
	Game.sfx("coin")
	world_text(n.node.global_position - Vector2(0, 30), "+%dG" % q.reward, Color("ffd24a"), 24)
	_set_qstate(qi, "done")
	_hud.refresh()


## Paused dialogue panel with a speaker name and buttons [[text, callable], ...].
func _dialog_box(speaker: String, text: String, buttons: Array) -> void:
	get_tree().paused = true
	_prompt.text = ""
	var box := PanelContainer.new()
	box.name = "QuestDialog"
	box.theme = get_tree().root.theme
	box.position = Vector2(140, 300)
	box.size = Vector2(680, 150)
	_overlay.add_child(box)
	var v := VBoxContainer.new()
	box.add_child(v)
	v.add_child(Game.label(speaker, 20, Color("f5d76e")))
	var l := Game.label(text, 17)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(650, 50)
	v.add_child(l)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_END
	v.add_child(row)
	for b in buttons:
		var cb: Callable = b[1]
		var btn := Game.button(b[0], func():
			box.queue_free()
			get_tree().paused = false
			if cb.is_valid():
				cb.call(), 16)
		row.add_child(btn)
	row.get_child(0).grab_focus()


## Where the hero stands when the stage (re)loads: the furthest main room already cleared.
func _spawn_point() -> Vector2:
	var node := int(_s.node)
	var best := 0
	for i in _rooms.size():
		var r: Dictionary = _rooms[i]
		if r.main and r.k >= 0 and r.k < node:
			best = i
	return _center(best)


# ---------------------------------------------------------------- UI
func _build_ui() -> void:
	var ui := CanvasLayer.new()
	ui.layer = 10
	add_child(ui)
	_ui = ui
	_hud = preload("res://scripts/hud.gd").new()
	_hud.position = Vector2(10, 8)
	_hud.size = Vector2(940, 60)
	ui.add_child(_hud)
	_room_label = Game.label("", 15, Color("f5d76e"))
	_room_label.add_theme_constant_override("outline_size", 4)
	_room_label.position = Vector2(14, 74)
	ui.add_child(_room_label)
	var hint := Game.label(Game.CONTROLS_TEXT, 12, Color(0.85, 0.8, 0.9, 0.75))
	hint.add_theme_constant_override("outline_size", 3)
	hint.position = Vector2(14, 96)
	ui.add_child(hint)
	_needs_label = Game.label("", 16, Color("ff7a5a"))
	_needs_label.add_theme_constant_override("outline_size", 5)
	_needs_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_needs_label.position = Vector2(560, 74)
	_needs_label.size = Vector2(386, 24)
	ui.add_child(_needs_label)
	_quest_label = Game.label("", 14, Color("ffe9a8"))
	_quest_label.add_theme_constant_override("outline_size", 4)
	_quest_label.position = Vector2(14, 118)
	ui.add_child(_quest_label)
	_prompt = Game.label("", 18, Color.WHITE)
	_prompt.add_theme_constant_override("outline_size", 6)
	_prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_prompt.position = Vector2(180, 430)
	_prompt.size = Vector2(600, 30)
	ui.add_child(_prompt)
	var bar := SkillBar.new()
	bar.p = player
	bar.position = Vector2(238, 478)
	bar.size = Vector2(484, 52)
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.add_child(bar)
	var pi := ParryIcon.new()
	pi.p = player
	pi.position = Vector2(884, 470)
	pi.size = Vector2(64, 60)
	pi.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.add_child(pi)
	_boss_box = VBoxContainer.new()
	_boss_box.position = Vector2(260, 118)
	_boss_box.visible = false
	ui.add_child(_boss_box)
	_boss_label = Game.label("", 16, Color("d9a0ff"))
	_boss_label.add_theme_constant_override("outline_size", 4)
	_boss_box.add_child(_boss_label)
	_boss_bar = Game.bar(Color("9b3fd1"), 440, 14)
	_boss_bar.max_value = Game.BOSS_MAX_HP
	_boss_box.add_child(_boss_bar)
	_overlay = CanvasLayer.new()
	_overlay.layer = 20
	add_child(_overlay)
	_build_menu()
	_update_room_label()
	_refresh_quests()


func _build_menu() -> void:
	_menu = PanelContainer.new()
	_menu.position = Vector2(330, 170)
	_menu.size = Vector2(300, 180)
	_menu.visible = false
	_menu.theme = get_tree().root.theme
	_overlay.add_child(_menu)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	_menu.add_child(v)
	var t := Game.label("หยุดพัก", 24, Color("f5d76e"))
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(t)
	v.add_child(Game.button("เล่นต่อ", _toggle_menu, 18))
	var back := Game.button("พักกลับหน้าเซฟ", func():
		Game.save_game()
		get_tree().paused = false
		Game.goto("save_select"), 18)
	back.name = "Back"
	v.add_child(back)


func _toggle_menu() -> void:
	_menu.visible = not _menu.visible
	get_tree().paused = _menu.visible
	var back: Button = _menu.find_child("Back", true, false)
	back.disabled = _fight_room >= 0
	back.text = "ออกไม่ได้ระหว่างต่อสู้" if back.disabled else "พักกลับหน้าเซฟ"


func _update_room_label() -> void:
	var st: Dictionary = Game.STAGES[_stage]
	var where := "จุดเริ่มต้น"
	if _cur_room >= 0:
		var kind: String = _rooms[_cur_room].kind
		where = "ประตูมิติ" if kind == "exit" else (Game.NODE_INFO[kind].name if Game.NODE_INFO.has(kind) else where)
	var left := 0
	for r in _rooms:
		if COMBAT.has(r.kind) and r.k >= int(_s.node):
			left += 1
	_room_label.text = "%s  ·  %s  ·  เหลือห้องต่อสู้ %d" % [st.name, where, left]


func _banner(text: String, color := Color("f5d76e"), size := 44) -> void:
	var l := Game.label(text, size, color)
	l.add_theme_constant_override("outline_size", 10)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.position = Vector2(0, 190)
	l.size = Vector2(960, 60)
	l.modulate.a = 0.0
	_overlay.add_child(l)
	var tw := l.create_tween()
	tw.tween_property(l, "modulate:a", 1.0, 0.3)
	tw.tween_interval(1.2)
	tw.tween_property(l, "modulate:a", 0.0, 0.6)
	tw.tween_callback(l.queue_free)


func ui_blocking() -> bool:
	return _dialog or get_tree().paused


# ---------------------------------------------------------------- loop
func _physics_process(delta: float) -> void:
	if Engine.is_editor_hint() or _ended or get_tree().paused or player == null:
		return
	var ri := _room_at(player.global_position)
	if ri != -1 and ri != _cur_room:
		_cur_room = ri
		_enter_room(ri)
		_update_room_label()
	if _fight_room >= 0 and not _dialog and _pending == 0 and alive_count() == 0:
		if _waves.size() > 0:
			_spawn_wave(_waves.pop_front())
		else:
			_clear_room()
	_update_near()
	_needs(delta)
	_check_pickups(delta)
	_update_windows(delta)
	_save_t += delta
	if _boss_dirty and _save_t > 0.5:
		_boss_dirty = false
		_save_t = 0.0
		Game.save_game()
	_hud_t -= delta
	if _hud_t <= 0.0:
		_hud_t = 0.15
		_hud.refresh()
		if _wrath != null and is_instance_valid(_wrath) and not _wrath.dead:
			_boss_bar.max_value = _wrath.max_hp
			_boss_bar.value = _wrath.hp
			_boss_label.text = "%s  %d/%d" % [_wrath.title, _wrath.hp, _wrath.max_hp]
		elif _boss_box.visible:
			_boss_bar.max_value = Game.BOSS_MAX_HP
			_boss_bar.value = Game.data.boss_hp
			_boss_label.text = "%s  เฟส %d/%d  ·  %d/%d" % [Game.boss_title(), Game.boss_phase(), Game.BOSS_PHASES, Game.data.boss_hp, Game.BOSS_MAX_HP]
	if _portal and _portal.active and player.global_position.distance_to(_portal.position) < 12.0:
		_ended = true
		Game.sfx("reborn")
		Game.advance_node()
		Game.goto("stage_map")


var _starve_t := 0.0
var _needs_label: Label


## Food and water drain with play time; an empty bar costs 1 HP every 2 s (both empty: 2).
func _needs(delta: float) -> void:
	if _dialog:
		return
	# The mark of sin makes hunger and thirst bite harder.
	var sin_k := 1.0 + 0.2 * int(_s.get("sin", 0))
	_s.food = maxf(0.0, float(_s.get("food", 100.0)) - Game.FOOD_DRAIN * delta * sin_k)
	_s.water = maxf(0.0, float(_s.get("water", 100.0)) - Game.WATER_DRAIN * delta * sin_k)
	var warn := []
	if _s.food <= 30.0:
		warn.append("หิว!" if _s.food > 0.0 else "อดอาหาร! (B เปิดกระเป๋า)")
	if _s.water <= 30.0:
		warn.append("กระหาย!" if _s.water > 0.0 else "ขาดน้ำ! (B เปิดกระเป๋า)")
	_needs_label.text = "  ".join(warn)
	_needs_label.modulate.a = 0.55 + 0.45 * absf(sin(Time.get_ticks_msec() / 250.0))
	var empty := int(_s.food <= 0.0) + int(_s.water <= 0.0)
	if empty == 0:
		_starve_t = 0.0
		return
	_starve_t += delta
	if _starve_t >= 2.0:
		_starve_t = 0.0
		_s.hp = maxi(0, int(_s.hp) - empty)
		world_text(player.hit_pos() - Vector2(0, 12), "-%d" % empty, Color("ffb347"))
		if int(_s.hp) <= 0:
			_on_death("อดอาหาร" if _s.food <= 0.0 else "ขาดน้ำ", true)


func _unhandled_input(event: InputEvent) -> void:
	if Engine.is_editor_hint() or _ended or player == null:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		var busy: bool = _dialog or _overlay_open() != null or _overlay.has_node("QuestDialog")
		if _inv and (event.physical_keycode == KEY_B or event.physical_keycode == KEY_ESCAPE):
			_toggle_inventory()
		elif event.physical_keycode == KEY_B and not busy and not _menu.visible:
			_toggle_inventory()
		elif event.physical_keycode == KEY_ESCAPE and not busy:
			_toggle_menu()
		elif event.physical_keycode == KEY_E and not get_tree().paused and not _near.is_empty():
			_open(_near)


func _room_at(pos: Vector2) -> int:
	var c := Vector2i((pos / T).floor())
	for i in _rooms.size():
		var r: Rect2i = _rooms[i].rect
		if r.grow(-1).has_point(c):
			return i
	return -1


func _enter_room(i: int) -> void:
	var room: Dictionary = _rooms[i]
	if room.kind == "exit":
		if not COMBAT.has(_route.back()):
			_portal.active = true
		return
	if not room.main or room.k < 0:
		return
	var k: int = room.k
	# Moving on along the main path passes the side rooms before it (they stay usable).
	while int(_s.node) < k:
		Game.advance_node()
	if int(_s.node) == k and COMBAT.has(room.kind):
		_start_fight(i)


func _update_near() -> void:
	_near = {}
	if _fight_room < 0:
		for n in _npcs:
			var p: Vector2 = n.node.position if n.moving else n.pos
			var usable: bool = _quest_usable(n) if n.kind == "quest" else not Game.is_used(n.k)
			if usable and player.global_position.distance_to(p) < 28.0:
				_near = n
				break
	var what := ""
	if not _near.is_empty():
		what = ("เก็บ" + _quests[_near.qi].item if _near.role == "item" else "คุย") if _near.kind == "quest" else INTERACT_TEXT[_near.kind]
	_prompt.text = "[E] %s" % what if what != "" else ""


func _overlay_open() -> Control:
	for c in _overlay.get_children():
		if c.has_signal("closed"):
			return c
	return null


func _open(n: Dictionary) -> void:
	if n.kind == "quest":
		_quest_talk(n)
		return
	_s.visit = n.kind
	_s.visit_k = n.k
	if n.kind == "event":
		_s.pending_event = _s.event_kinds.get(str(n.k), "")
	var ov: Control = (ShopScript if n.kind == "shop" else EventScript).new()
	ov.size = Vector2(960, 540)
	ov.theme = get_tree().root.theme
	_overlay.add_child(ov)
	get_tree().paused = true
	_prompt.text = ""
	ov.closed.connect(_close_overlay.bind(ov, n))


func _close_overlay(ov: Control, n: Dictionary) -> void:
	ov.queue_free()
	_s.visit = ""
	get_tree().paused = false
	Game.play_bgm(Game.STAGES[_stage].bgm)
	player.mp = float(_s.mp)
	if Game.is_used(n.k):
		n.node.modulate = Color(0.45, 0.45, 0.5, 0.75)
	Game.save_game()
	_hud.refresh()


# ---------------------------------------------------------------- items, bag, pickups
const PICKUP_TABLE := ["fruit", "fruit", "water", "water", "herb", "herb", "bread", "meat", "juice", "gold"]
const DROP_TABLE := ["fruit", "water", "herb", "bread", "meat", "juice"]

var _pickups: Array = []  # {id, key, pos, node, glow}
var _full_msg_t := 0.0
var _inv: PanelContainer
var _inv_sel := ""


## Uses one item from the bag (inventory or Q/R) and shows what it did.
func use_item(id: String) -> void:
	var nm: String = Game.ITEM_DEFS[id].name
	if Game.item_count(id) <= 0:
		say_over(player, "ไม่มี%s" % nm, Game.C_DIM)
		return
	var msg := Game.use_item(id)
	if msg.begins_with("HP เต็ม") or msg.begins_with("MP เต็ม"):
		say_over(player, msg, Game.C_DIM)
		return
	player.mp = float(_s.mp)
	Game.sfx("heal")
	if Game.ITEM_DEFS[id].has("heal"):
		Game.spawn_vfx(self, "heal", player.hit_pos(), 0.6)
	say_over(player, msg, Game.C_GOOD)
	_hud.refresh()


## Glowing pickups: one per room (none in miniboss / boss rooms), collected ones stay gone.
func _place_pickups() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = _rng.seed + 7
	var picked: Array = _s.get("picked", [])
	for i in _rooms.size():
		var kind: String = _rooms[i].kind
		if kind == "miniboss" or kind == "boss":
			continue
		var key := "%d" % i
		var id: String = PICKUP_TABLE[rng.randi() % PICKUP_TABLE.size()]
		var r: Rect2i = _rooms[i].rect.grow(-1)
		var pos := (Vector2(rng.randi_range(r.position.x, r.end.x - 1), r.position.y if rng.randf() < 0.5 else r.end.y - 1) + Vector2(0.5, 0.8)) * T
		var skip := false
		for x in picked:
			if str(x) == key:
				skip = true
		if not skip:
			_spawn_pickup(id, pos, key)


func _spawn_pickup(id: String, pos: Vector2, key := "") -> void:
	var s := Sprite2D.new()
	s.texture = _tex("icons/coin.png" if id == "gold" else Game.ITEM_DEFS[id].icon)
	s.scale = Vector2.ONE * (11.0 / s.texture.get_width())
	s.position = pos + Vector2(0, -5)
	_entities.add_child(s)
	var tw := s.create_tween().set_loops()
	tw.tween_property(s, "position:y", pos.y - 8.0, 0.6).set_trans(Tween.TRANS_SINE)
	tw.tween_property(s, "position:y", pos.y - 5.0, 0.6).set_trans(Tween.TRANS_SINE)
	var g := glow(pos + Vector2(0, -4), Color(1.0, 0.95, 0.6, 0.45), 14.0)
	_pickups.append({"id": id, "key": key, "pos": pos, "node": s, "glow": g})


func _check_pickups(delta: float) -> void:
	_full_msg_t -= delta
	for p in _pickups.duplicate():
		if player.global_position.distance_to(p.pos) > 12.0:
			continue
		if p.id == "gold":
			var g := randi_range(8, 20) + 6 * _stage
			_s.gold = int(_s.gold) + g
			world_text(p.pos - Vector2(0, 12), "+%dG" % g, Color("ffd24a"), 22)
		elif Game.add_item(p.id):
			say_over(player, "เก็บ %s" % Game.ITEM_DEFS[p.id].name, Color("ffe9a8"))
		else:
			if _full_msg_t <= 0.0:
				_full_msg_t = 2.0
				say_over(player, "กระเป๋าเต็ม!", Game.C_BAD)
			continue
		Game.sfx("coin")
		if p.key != "":
			if not _s.has("picked"):
				_s.picked = []
			_s.picked.append(p.key)
		p.node.queue_free()
		p.glow.queue_free()
		_pickups.erase(p)
		_hud.refresh()


# ---------------------------------------------------------------- inventory window (B)
func _toggle_inventory() -> void:
	if _inv:
		_hide_skill_tip()
		_inv.queue_free()
		_inv = null
		get_tree().paused = false
		Game.save_game()
		return
	get_tree().paused = true
	_prompt.text = ""
	_inv = PanelContainer.new()
	_inv.position = Vector2(170, 40)
	_inv.size = Vector2(620, 470)
	_inv.theme = get_tree().root.theme
	_overlay.add_child(_inv)
	_fill_inventory()


## Stacks shown in the grid: [id, count, def]; quest items you carry are listed too.
func _bag_stacks() -> Array:
	var out := []
	var b := Game.bag()
	for id in Game.ITEM_ORDER:
		var n := int(b.get(id, 0))
		while n > 0:
			out.append([id, mini(n, Game.STACK), Game.ITEM_DEFS[id]])
			n -= Game.STACK
	for qi in _quests.size():
		if _qstate(qi) == "carry":
			var q: Dictionary = _quests[qi]
			var to: String = q.target if q.type == "deliver" else q.giver
			out.append(["quest", 1, {"name": q.item, "icon": q.icon, "desc": "ของเควส · นำไปให้%s" % to}])
	return out


func _fill_inventory() -> void:
	_hide_skill_tip()
	for c in _inv.get_children():
		c.queue_free()
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	_inv.add_child(v)
	var top := HBoxContainer.new()
	v.add_child(top)
	var title := Game.label("กระเป๋า  (%d/%d ช่อง)" % [Game.bag_slots_used(), Game.BAG_SLOTS], 22, Color("f5d76e"))
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(title)
	top.add_child(Game.label("เงิน %dG" % int(_s.gold), 18, Color("ffd24a")))
	var stats := "HP %d/%d  ·  MP %d/%d  ·  อาหาร %d%%  ·  น้ำ %d%%" % [_s.hp, _s.max_hp, _s.mp, _s.max_mp,
		roundi(float(_s.get("food", 100.0))), roundi(float(_s.get("water", 100.0)))]
	if int(_s.get("sin", 0)) > 0:
		stats += "  ·  ตราบาป x%d" % int(_s.sin)
	v.add_child(Game.label(stats, 15, Color("ff9ad5") if int(_s.get("sin", 0)) > 0 else Game.C_TEXT))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	v.add_child(row)
	var grid := GridContainer.new()
	grid.columns = 5
	grid.add_theme_constant_override("h_separation", 4)
	grid.add_theme_constant_override("v_separation", 4)
	row.add_child(grid)
	var stacks := _bag_stacks()
	var sel: Array = []
	for i in Game.BAG_SLOTS:
		var b := Button.new()
		b.custom_minimum_size = Vector2(62, 62)
		b.focus_mode = Control.FOCUS_NONE
		if i < stacks.size():
			var st: Array = stacks[i]
			b.icon = _tex(st[2].icon)
			b.expand_icon = true
			b.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
			b.vertical_icon_alignment = VERTICAL_ALIGNMENT_TOP
			b.text = "x%d" % st[1] if st[0] != "quest" else "เควส"
			b.add_theme_font_size_override("font_size", 12)
			b.tooltip_text = "%s\n%s" % [st[2].name, st[2].desc]
			var key: String = st[0] if st[0] != "quest" else "quest:" + st[2].name
			if key == _inv_sel:
				sel = st
				b.add_theme_stylebox_override("normal", Game.panel_style(Color("54406f"), Color("ffe066")))
			b.pressed.connect(func():
				Game.sfx("click")
				_inv_sel = key
				_fill_inventory())
		else:
			b.disabled = true
		grid.add_child(b)
	var info := VBoxContainer.new()
	info.custom_minimum_size = Vector2(250, 0)
	row.add_child(info)
	if sel.is_empty():
		info.add_child(Game.label("คลิกช่องเพื่อดูของ", 16, Game.C_DIM))
	else:
		info.add_child(Game.label(sel[2].name, 20, Color("f5d76e")))
		var d := Game.label(sel[2].desc, 15)
		d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		d.custom_minimum_size = Vector2(240, 0)
		info.add_child(d)
		if sel[0] != "quest":
			var id: String = sel[0]
			info.add_child(Game.button("ใช้ (เหลือ %d)" % Game.item_count(id), func():
				use_item(id)
				if Game.item_count(id) <= 0:
					_inv_sel = ""
				_fill_inventory(), 18))
	v.add_child(_skill_row())
	var close := Game.button("ปิด (B)", _toggle_inventory, 16)
	close.size_flags_horizontal = Control.SIZE_SHRINK_END
	v.add_child(close)


## Class skills with icons; hovering one shows a styled detail panel.
func _skill_row() -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	row.add_child(Game.label("สกิล", 18, Color("f5d76e")))
	var keys := ["M1", "1", "2", "3", "F"]
	var kit: Array = Game.CLASSES[_s.cls].skills.duplicate()
	kit.append({"name": "ปัดป้อง (Parry)", "mp": 0, "cd": 7.0, "desc": "กางโล่ 0.2 วินาที ถ้าโดนกระสุนหรือโดนตีในจังหวะนั้น จะบล็อกได้ทั้งหมดและฟื้น HP +20 (ใช้ได้กับกระสุนบอส หน้าต่างลูกพลัง และชาวบ้านโต้กลับ)"})
	for i in 5:
		var slot := Panel.new()
		slot.custom_minimum_size = Vector2(52, 52)
		slot.add_theme_stylebox_override("panel", Game.panel_style(Color("2a2038"), Game.C_BORDER))
		var ic := TextureRect.new()
		ic.texture = _tex("skills/%s_%d.png" % [_s.cls, i] if i < 4 else "icons/shield.png")
		ic.position = Vector2(8, 8)
		ic.size = Vector2(36, 36)
		ic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		ic.mouse_filter = Control.MOUSE_FILTER_IGNORE
		slot.add_child(ic)
		var badge := Game.label(keys[i], 12, Color("f5d76e"))
		badge.add_theme_constant_override("outline_size", 4)
		badge.position = Vector2(3, -2)
		badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
		slot.add_child(badge)
		var sk: Dictionary = kit[i]
		slot.mouse_entered.connect(_show_skill_tip.bind(slot, sk, keys[i]))
		slot.mouse_exited.connect(_hide_skill_tip)
		row.add_child(slot)
	row.add_child(Game.label("(ชี้เมาส์ที่ไอคอนเพื่อดูรายละเอียด)", 13, Game.C_DIM))
	return row


var _skill_tip: PanelContainer


func _show_skill_tip(slot: Control, sk: Dictionary, key: String) -> void:
	_hide_skill_tip()
	_skill_tip = PanelContainer.new()
	_skill_tip.theme = get_tree().root.theme
	_skill_tip.add_theme_stylebox_override("panel", Game.panel_style(Color("120d18"), Color("ffe066")))
	_skill_tip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 2)
	_skill_tip.add_child(v)
	v.add_child(Game.label("%s   [ปุ่ม %s]" % [sk.name, key], 18, Color("f5d76e")))
	var cost := "ไม่ใช้ MP" if int(sk.mp) == 0 else "MP %d" % int(sk.mp)
	v.add_child(Game.label("%s  ·  คูลดาวน์ %.1f วิ" % [cost, float(sk.cd)], 14, Color("8fb4ff")))
	var d := Game.label(sk.desc, 15)
	d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	d.custom_minimum_size = Vector2(260, 0)
	v.add_child(d)
	v.add_child(Game.label("ATK ปัจจุบัน %d (ดาเมจ = ATK × ตัวคูณในคำอธิบาย)" % int(_s.atk), 12, Game.C_DIM))
	_overlay.add_child(_skill_tip)
	var p := slot.global_position + Vector2(0, -8)
	_skill_tip.reset_size()
	var sz := _skill_tip.get_combined_minimum_size()
	_skill_tip.position = Vector2(clampf(p.x, 4.0, 956.0 - sz.x), clampf(p.y - sz.y, 4.0, 536.0 - sz.y))


func _hide_skill_tip() -> void:
	if _skill_tip and is_instance_valid(_skill_tip):
		_skill_tip.queue_free()
	_skill_tip = null


# ---------------------------------------------------------------- harming villagers
const HURT_LINES := ["อย่านะ!", "เจ้าทำอะไรน่ะ!", "ช่วยด้วย!", "โอ๊ย! หยุดเดี๋ยวนี้!"]
const TAUNTS := ["เจ้าคิดว่าคนธรรมดาจะไม่มีเขี้ยวเล็บหรือ!", "บาปของเจ้า... ข้าจะคืนให้เป็นร้อยเท่า!", "ข้าเคยเป็นผู้กล้ามาก่อนเจ้าเสียอีก!"]

var npc_targets: Array = []  # {entry, node, hp, max_hp, name, sheet, key, room, hit}
var _wrath = null  # the villager that turned on the hero


## Merchant, beggar and quest villagers can be hit. Killed ones stay dead for this life's stage.
func _register_targets() -> void:
	var dead: Array = _s.get("npc_dead", [])
	for e in _npcs.duplicate():
		var nm := ""
		var sheet := ""
		match e.kind:
			"shop":
				nm = "พ่อค้า"
				sheet = "merchant"
			"event":
				if e.moving:
					nm = "ขอทาน"
					sheet = "beggar"
			"quest":
				if e.role != "item":
					nm = e.name
					sheet = e.sheet
		if nm == "":
			continue
		var room := _room_at(e.pos)
		var hp := 60 + 30 * _stage
		var t := {"entry": e, "node": e.node, "hp": hp, "max_hp": hp, "name": nm, "sheet": sheet,
			"key": "%d_%s" % [room, e.get("role", e.kind)], "room": room, "hit": false}
		var is_dead := false
		for x in dead:
			if str(x) == t.key:
				is_dead = true
		if is_dead:
			_remove_npc(t)
		else:
			npc_targets.append(t)


func _npc_center(t: Dictionary) -> Vector2:
	return t.node.global_position + (Vector2(0, -14) if t.entry.moving else Vector2.ZERO)


## Player projectiles call this; returns true when the shot hit a villager.
func shot_hits_npc(pos: Vector2, radius: float, mult: float) -> bool:
	for t in npc_targets:
		if _npc_center(t).distance_to(pos) < radius + 8.0:
			_hit_npc(t, mult)
			return true
	return false


func _hit_npc(t: Dictionary, mult: float) -> void:
	if not npc_targets.has(t):
		return
	var r := _roll(mult, 2.0)
	t.hp -= r.dmg
	Game.sfx("hit")
	Game.spawn_vfx(self, "hit", _npc_center(t), 0.5)
	world_text(_npc_center(t) - Vector2(0, 10), "%d" % r.dmg, Color.WHITE)
	var tw: Tween = t.node.create_tween()
	tw.tween_property(t.node, "self_modulate", Color(1, 0.3, 0.3), 0.06)
	tw.tween_property(t.node, "self_modulate", Color.WHITE, 0.12)
	var first: bool = not t.hit
	t.hit = true
	if first:
		say_over(t.node, HURT_LINES.pick_random(), Color("ff8a8a"))
	if t.hp <= 0:
		_npc_killed(t)
	elif randf() < (0.35 if first else 0.1):
		_npc_retaliate(t)


func _npc_killed(t: Dictionary) -> void:
	Game.sfx("die")
	Game.spawn_vfx(self, "blood", _npc_center(t), 1.2)
	var at: Vector2 = t.node.global_position
	_remove_npc(t, true)
	_murder(t.name)
	match t.entry.kind:
		"shop":
			_s.gold = int(_s.gold) + 40 + 20 * _stage
			world_text(at - Vector2(0, 20), "+%dG" % (40 + 20 * _stage), Color("ffd24a"), 24)
			for k in ["bread", "water", "potion"]:
				_spawn_pickup(k, at + Vector2(randf_range(-18, 18), randf_range(4, 14)))
		"event":
			_s.gold = int(_s.gold) + 5
			_spawn_pickup("fruit", at + Vector2(-8, 8))
			_spawn_pickup("water", at + Vector2(8, 8))
		_:
			_spawn_pickup("herb", at + Vector2(0, 8))
	_hud.refresh()


## Heavy sin: karma drops hard (carries to the next life) and the mark of sin stacks.
func _murder(who: String) -> void:
	Game.data.karma = clampi(int(Game.data.karma) - 2, -3, 3)
	_s.sin = mini(int(_s.get("sin", 0)) + 1, 5)
	_s.deeds.append("murder")
	Game.sfx("bad")
	_banner("คุณสังหาร%s... ตราบาป x%d" % [who, int(_s.sin)], Color("ff4a6a"), 28)
	Game.save_game()


## Takes a villager off the map for good: shop / event closed, their quest failed.
func _remove_npc(t: Dictionary, record := false) -> void:
	npc_targets.erase(t)
	_npcs.erase(t.entry)
	if is_instance_valid(t.node):
		t.node.queue_free()
	var e: Dictionary = t.entry
	match e.kind:
		"shop", "event":
			if not Game.is_used(e.k):
				if not _s.has("used"):
					_s.used = []
				_s.used.append(int(e.k))
		"quest":
			if _qstate(e.qi) != "done":
				_set_qstate(e.qi, "failed")
	if record:
		if not _s.has("npc_dead"):
			_s.npc_dead = []
		_s.npc_dead.append(t.key)


## Random event: the villager fights back as a bullet-hell mini boss.
func _npc_retaliate(t: Dictionary) -> void:
	var at: Vector2 = t.node.global_position
	_remove_npc(t, true)
	var e = EnemyScript.new()
	e.position = at
	_entities.add_child(e)
	e.setup(self, "wrath_" + t.sheet, float(_s.enemy_mult) * (1.0 + 0.5 * _stage))
	e.title = "%sผู้โกรธเกรี้ยว" % t.name
	enemies.append(e)
	_wrath = e
	Game.spawn_vfx(self, "magic", at + Vector2(0, -10), 1.4)
	Game.sfx("thunder")
	Game.play_bgm("miniboss")
	say_over(e, TAUNTS.pick_random(), Color("ff5a7a"))
	_banner(e.title, Color("ff4a6a"), 34)
	_boss_box.visible = true
	if _room_at(player.global_position) == t.room and _fight_room < 0:
		_fight_room = t.room
		_lock(t.room, true)


# ---------------------------------------------------------------- fights
func _start_fight(i: int) -> void:
	_fight_room = i
	_lock(i, true)
	_waves.clear()
	var pool: Array = Game.STAGES[_stage].enemies
	match _rooms[i].kind:
		"boss":
			_dialog = true
			await _cutscene(i, "demon_lord", _boss_lines())
			_dialog = false
			Game.play_bgm("boss")
		"miniboss":
			_waves = [[pool.pick_random(), pool.pick_random()]]
			_dialog = true
			await _cutscene(i, "minotaur", _mino_lines())
			_dialog = false
			Game.play_bgm("miniboss")
		_:
			Game.play_bgm("battle")
			for w in 2:
				var ids := []
				var n := 3 + randi() % 2 + int(_s.extra_foes) - (1 if w == 0 else 0)
				for j in n:
					ids.append(pool.pick_random())
				_waves.append(ids)


func _spawn_wave(ids: Array) -> void:
	for id in ids:
		var pos := _center(_fight_room) if id == "demon_lord" else _free_spot(_fight_room)
		_spawn_enemy(id, pos)


func _spawn_enemy(id: String, pos: Vector2) -> void:
	_pending += 1
	fx_warn(pos, 9.0, 0.7)
	await get_tree().create_timer(0.7, false).timeout
	_pending -= 1
	if _ended:
		return
	_add_enemy(id, pos)


func _add_enemy(id: String, pos: Vector2):
	var e = EnemyScript.new()
	e.position = pos
	_entities.add_child(e)
	e.setup(self, id, float(_s.enemy_mult))
	enemies.append(e)
	Game.spawn_vfx(self, "magic", pos + Vector2(0, -8), 0.6)
	if e.is_boss():
		_boss_box.visible = true
	return e


func summon_minions(n: int) -> void:
	if _fight_room < 0:
		return
	for i in n:
		_spawn_enemy(["skeleton", "wraith"].pick_random(), _free_spot(_fight_room))


func _free_spot(i: int) -> Vector2:
	var r: Rect2i = _rooms[i].rect.grow(-2)
	for t in 30:
		var p := (Vector2(randi_range(r.position.x, r.end.x - 1), randi_range(r.position.y, r.end.y - 1)) + Vector2(0.5, 0.5)) * T
		if p.distance_to(player.global_position) > 60.0:
			return p
	return _center(i)


func alive_count() -> int:
	var n := 0
	for e in enemies:
		if not e.dead:
			n += 1
	return n


func _clear_room() -> void:
	var i := _fight_room
	_fight_room = -1
	_lock(i, false)
	_boss_box.visible = false
	if not _rooms[i].main:
		# An angry villager was beaten in a side room: no route progress here.
		Game.play_bgm(Game.STAGES[_stage].bgm)
		Game.save_game()
		return
	Game.sfx("levelup")
	if _rooms[i].kind == "miniboss":
		_s.atk = int(_s.atk) + 5
		if not Game.add_item("potion"):
			_s.gold = int(_s.gold) + 15
		_banner("ได้ \"เขามิโนทอร์\" ATK +5 และยา 1 ขวด", Color("f5d76e"), 26)
	else:
		_banner("เคลียร์ห้อง!", Color("7ad66b"), 34)
	Game.play_bgm(Game.STAGES[_stage].bgm)
	if _rooms[i].k >= _route.size() - 1:
		# Last fight: the portal opens; the slot moves to the next stage when the hero steps in,
		# so the side rooms stay usable until then.
		if _portal:
			_portal.active = true
			_banner("ประตูมิติเปิดแล้ว!", Color("b48cff"), 30)
	else:
		Game.advance_node()
	Game.save_game()
	_update_room_label()


# ---------------------------------------------------------------- boss cutscenes
var cutscene := false
var _phase_said := {}  # boss phase -> its dialogue already played this visit
var _ui: CanvasLayer
var _talk_next := false
var _talk_skip := false


func _boss_lines() -> Array:
	match Game.boss_phase():
		2:
			return _phase2_lines()
		3:
			return [["boss", "ใช้ได้นี่นา ถ้างั้นเจอนี่หน่อย"]]
	return [
		["boss", "ในที่สุด [color=yellow]ผู้กล้า[/color]ที่มีความสามารถ ถ้าแกคิดจะสู้กับข้าได้ละก็"],
		["hero", "พูดมาก มาสู้กันดีกว่า คนจริงเขาวัดกันที่[color=yellow]สกิล[/color]"],
		["boss", "...."],
		["boss", "เออได้ เดี๋ยวหาว่าไม่เตือน"],
	]


func _phase2_lines() -> Array:
	return [
		["boss", "หึหึ งั้นได้เวลาที่[color=yellow]เพิ่มระดับ[/color]แล้วสินะ"],
		["hero", "จะอะไรก็เข้ามาเถอะ ข้าจะกลับบ้าน"],
		["boss", "ผู้กล้าสมัยนี้เป็นอะไรไปหมด.."],
	]

func _mino_lines() -> Array:
	return [
		["boss", "มนุษย์... กล้าดียังไงมาเหยียบ[color=yellow]ป้อม[/color]ของข้า!"],
		["hero", "หลีกทางไป ข้ามีที่ต้องไป"],
		["boss", "ข้าคือ[color=yellow]มิโนทอร์[/color] ผู้เฝ้าป้อม! ไม่มีใครผ่านเขาคู่นี้ไปได้!"],
	]


## Undertale-style boss entrance: lights dim, a spotlight on the boss, the hero walks up,
## dialogue in a black box with a white border, then a power-up flash and the fight.
func _cutscene(i: int, id: String, lines: Array) -> void:
	var e: Dictionary = Game.ENEMIES[id]
	var ctr := _center(i)
	var boss_pos := ctr + Vector2(0, -2 * T)
	if Game.skip_cutscenes:
		_add_enemy(id, boss_pos)
		return
	cutscene = true
	_ui.visible = false
	if Game._bgm:
		Game._bgm.stop()
	var mood: CanvasModulate = find_children("*", "CanvasModulate", false, false)[0]
	var mood_col := mood.color
	var tw := create_tween()
	tw.tween_property(mood, "color", mood_col * Color(0.35, 0.35, 0.45), 0.8)
	var spots := []
	for k in 3:
		var g := glow(boss_pos + Vector2(0, 4), Color(0.75, 0.75, 1.0, 0.28), 70.0 - k * 18.0)
		g.scale.y *= 0.45
		spots.append(g)
	var sc: float = e.scale / 4.0
	var dummy := Game.enemy_sprite(id, 1.0)
	dummy.scale = Vector2(sc, sc)
	dummy.position = boss_pos + Vector2(0, -e.fh * sc / 2.0 + 2.0)
	dummy.modulate.a = 0.0
	_entities.add_child(dummy)
	Game.sfx("thunder")
	create_tween().tween_property(dummy, "modulate:a", 1.0, 0.8)
	player.auto_target = ctr + Vector2(0, 2.5 * T)
	var waited := 0.0
	while player.auto_target != Vector2.INF and waited < 4.0:
		await get_tree().process_frame
		waited += get_process_delta_time()
	player.auto_target = Vector2.INF
	await get_tree().create_timer(0.3).timeout
	var faces := _faces()
	if id == "minotaur":
		var mf := AtlasTexture.new()
		mf.atlas = Game.tex(e.sheet)
		mf.region = Rect2(0, 0, e.fw, e.fh)
		faces["boss"] = mf
		faces["mino"] = true
	else:
		_phase_said[Game.boss_phase()] = true
	# Camera pans over to the boss while they talk.
	var cam := _cam()
	if cam:
		var pan := create_tween()
		pan.tween_property(cam, "offset", (boss_pos - player.global_position) * 0.7, 0.7).set_trans(Tween.TRANS_SINE)
		await pan.finished
	await _talk(lines, faces)
	if cam:
		create_tween().tween_property(cam, "offset", Vector2.ZERO, 0.5)
	# Power-up flash and roar.
	Game.sfx("explosion")
	Game.spawn_vfx(self, "magic", dummy.position, 2.5)
	var fl := create_tween()
	fl.tween_property(dummy, "modulate", Color(3, 3, 3), 0.15)
	fl.tween_property(dummy, "modulate", Color.WHITE, 0.25)
	shake(6.0, 0.6)
	await get_tree().create_timer(0.5).timeout
	for g in spots:
		g.queue_free()
	create_tween().tween_property(mood, "color", mood_col, 0.6)
	dummy.queue_free()
	_add_enemy(id, boss_pos)
	_ui.visible = true
	cutscene = false


const DialogScript := preload("res://scripts/dialog_box.gd")


func _faces() -> Dictionary:
	var boss_face := AtlasTexture.new()
	var e: Dictionary = Game.ENEMIES["demon_lord"]
	boss_face.atlas = Game.tex(e.sheet)
	boss_face.region = Rect2(0, 0, e.fw, e.fh)
	var hero_face := AtlasTexture.new()
	hero_face.atlas = Game.tex(Game.CLASSES[_s.cls].sheet)
	hero_face.region = Rect2(0, 0, 32, 32)
	return {"boss": boss_face, "hero": hero_face}


func _names() -> Dictionary:
	return {"boss": "จอมมาร", "hero": Game.CLASSES[_s.cls].name, "mino": "มิโนทอร์"}


## Undertale-style dialogue (dialog_box.gd) on top of everything.
func _talk(lines: Array, faces: Dictionary, layer := 25) -> void:
	if Game.skip_cutscenes:
		return
	if win_mode:
		await _talk_window(lines, faces)
		return
	var cl := CanvasLayer.new()
	cl.layer = layer
	add_child(cl)
	var box = DialogScript.new()
	box.theme = get_tree().root.theme
	cl.add_child(box)
	var names := _names()
	if faces.has("mino"):
		names["boss"] = "มิโนทอร์"
	await box.say(lines, faces, names)
	cl.queue_free()

# ---------------------------------------------------------------- boss phase 3: window mode
const WIN_SCALE := 2.5
const GLITCH_SHADER := """
shader_type canvas_item;
uniform sampler2D screen_tex : hint_screen_texture, filter_nearest;
uniform float amount = 0.0;
uniform float t = 0.0;
float rnd(vec2 c) { return fract(sin(dot(c, vec2(12.9898, 78.233))) * 43758.5453); }
void fragment() {
	vec2 uv = SCREEN_UV;
	float band = floor(uv.y * 28.0 + t * 9.0);
	if (rnd(vec2(band * 1.7, floor(t * 11.0))) > 1.0 - amount * 0.7) {
		uv.x += (rnd(vec2(band, floor(t * 13.0))) - 0.5) * 0.16 * amount;
	}
	uv.y += sin(uv.x * 40.0 + t * 20.0) * 0.004 * amount;
	float r = texture(screen_tex, uv + vec2(0.014 * amount, 0.0)).r;
	float g = texture(screen_tex, uv).g;
	float b = texture(screen_tex, uv - vec2(0.014 * amount, 0.0)).b;
	vec3 col = vec3(r, g, b) + (rnd(uv * (t + 1.0)) - 0.5) * 0.35 * amount;
	col *= 1.0 - 0.25 * amount * step(0.5, fract(SCREEN_UV.y * 180.0));
	COLOR = vec4(col, 1.0);
}
"""

var win_mode := false
var _wins := {}  # "player" / "boss" -> Window
var _orb_wins: Array = []  # [shot, Window]
var _arena_center := Vector2.ZERO
var _screen_center := Vector2.ZERO
var _win_shake := 0.0
var _win_shake_t := 0.0
var _crash_layer: CanvasLayer
var _win_backdrop: Control
var _boss_ref = null


## Phase 3 entrance: the boss's line, a fake "GAME CRASH!!!", glitching picture, 3 s of black,
## then the hero and the demon lord continue in small separate OS windows (Windowkill style).
func start_window_phase(boss) -> void:
	if win_mode or cutscene:
		return
	_boss_ref = boss
	cutscene = true
	_dialog = true
	for c in _shots.get_children():
		c.queue_free()
	if not _phase_said.get(3, false):
		_phase_said[3] = true
		await _talk([["boss", "ใช้ได้นี่นา ถ้างั้น[color=yellow]เจอนี่หน่อย[/color]"]], _faces())
	if _ended or not is_inside_tree():
		return
	if Game._bgm:
		Game._bgm.stop()
	Game.sfx("bad")
	_crash_layer = CanvasLayer.new()
	_crash_layer.layer = 40
	add_child(_crash_layer)
	var fx := ColorRect.new()
	fx.size = Vector2(960, 540)
	fx.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var mat := ShaderMaterial.new()
	var sh := Shader.new()
	sh.code = GLITCH_SHADER
	mat.shader = sh
	fx.material = mat
	_crash_layer.add_child(fx)
	var msg := Game.label("GAME CRASH!!!", 72, Color("ff2a3a"))
	msg.add_theme_constant_override("outline_size", 14)
	msg.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	msg.position = Vector2(0, 170)
	msg.size = Vector2(960, 100)
	_crash_layer.add_child(msg)
	var err := Game.label("FATAL ERROR 0xDE4D10RD · stage_map.gd: จอมมารไม่ยอมอยู่ในหน้าจอนี้อีกต่อไป\nแรงกดดันของคำสาปทำให้โลกแตกออกเป็นเสี่ยงๆ...", 16, Color("ffb0b0"))
	err.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	err.position = Vector2(0, 280)
	err.size = Vector2(960, 60)
	_crash_layer.add_child(err)
	var t := 0.0
	while t < 2.2:
		if _ended or not is_inside_tree():
			return
		await get_tree().process_frame
		t += get_process_delta_time()
		mat.set_shader_parameter("amount", clampf(t / 1.6, 0.0, 1.0))
		mat.set_shader_parameter("t", t)
		msg.position = Vector2(randf_range(-8, 8) * t, 170 + randf_range(-6, 6) * t)
		if randf() < 0.1:
			Game.sfx(["hit", "bad", "explosion"].pick_random())
	if _ended or not is_inside_tree():
		return
	# Blackout.
	for c in _crash_layer.get_children():
		c.queue_free()
	var black := ColorRect.new()
	black.color = Color.BLACK
	black.size = Vector2(960, 540)
	_crash_layer.add_child(black)
	await get_tree().create_timer(3.0).timeout
	if _ended or not is_inside_tree():
		return
	_crash_layer.queue_free()
	if not Game.skip_cutscenes and DisplayServer.get_name() != "headless":
		_enter_windows()
	await _talk([
		["hero", "อะไรกันน่ะ ทำไม[color=yellow]โลก[/color]มันถึงได้แคบลงแบบนี้"],
		["boss", "โอ้ นี่เจ้ารู้สึกถึงมันด้วยเหรอ ประสบการณ์ไม่ธรรมดาเลย"],
		["hero", "ฉันจะฆ่าแก!"],
	], _faces())
	Game.sfx("thunder")
	Game.play_bgm("boss")
	_banner("— เฟส 3/3 —", Color("ff5a9a"), 30)
	cutscene = false
	_dialog = false


var _main_mode := DisplayServer.WINDOW_MODE_FULLSCREEN
var _title_t := 0.0


func _enter_windows() -> void:
	get_viewport().gui_embed_subwindows = false
	win_mode = true
	_arena_center = _center(_fight_room) if _fight_room >= 0 else player.global_position
	var scr := DisplayServer.window_get_current_screen()
	_screen_center = Vector2(DisplayServer.screen_get_position(scr) + DisplayServer.screen_get_size(scr) / 2)
	_wins.player = _make_win("ผู้กล้า", Vector2i(320, 260))
	_wins.boss = _make_win("จอมมาร", Vector2i(380, 320))
	_update_windows(0.0)
	# The main game window gets out of the way: the player's real desktop is the background.
	_main_mode = DisplayServer.window_get_mode()
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_MINIMIZED)
	_wins.player.grab_focus()

func _make_win(title: String, size: Vector2i, focusable := true) -> Window:
	var w := Window.new()
	w.title = title
	w.size = size
	w.unresizable = true
	w.always_on_top = true
	w.unfocusable = not focusable
	w.world_2d = get_viewport().world_2d
	w.close_requested.connect(func(): Game.sfx("bad"))
	var cam := Camera2D.new()
	cam.zoom = Vector2(WIN_SCALE, WIN_SCALE)
	w.add_child(cam)
	add_child(w)
	cam.make_current()
	w.set_meta("cam", cam)
	return w


func world_to_screen(p: Vector2) -> Vector2:
	return _screen_center + (p - _arena_center) * WIN_SCALE


func screen_to_world(sp: Vector2) -> Vector2:
	return _arena_center + (sp - _screen_center) / WIN_SCALE


func shake_windows(strength: float, dur: float) -> void:
	_win_shake = strength
	_win_shake_t = dur


func _place_win(w: Window, p: Vector2) -> void:
	if not is_instance_valid(w):
		return
	var cam: Camera2D = w.get_meta("cam")
	cam.global_position = p
	var jitter := Vector2.ZERO
	if _win_shake_t > 0.0:
		jitter = Vector2(randf_range(-1, 1), randf_range(-1, 1)) * _win_shake
	w.position = Vector2i(world_to_screen(p) - Vector2(w.size) / 2.0 + jitter)


func _update_windows(delta: float) -> void:
	if not win_mode:
		return
	# F10 = emergency: bring the normal game window back.
	if Input.is_physical_key_pressed(KEY_F10):
		_exit_windows()
		return
	# The HUD is in the minimized main window, so the window titles carry HP.
	_title_t -= delta
	if _title_t <= 0.0:
		_title_t = 0.2
		if is_instance_valid(_wins.get("player")):
			_wins.player.title = "ผู้กล้า — HP %d/%d · MP %d" % [_s.hp, _s.max_hp, _s.mp]
		if is_instance_valid(_wins.get("boss")):
			_wins.boss.title = "จอมมาร — เฟส %d/%d · %d/%d" % [Game.boss_phase(), Game.BOSS_PHASES, Game.data.boss_hp, Game.BOSS_MAX_HP]
	_win_shake_t -= delta
	_place_win(_wins.player, player.hit_pos())
	if _boss_ref != null and is_instance_valid(_boss_ref) and not _boss_ref.dead:
		_place_win(_wins.boss, _boss_ref.hit_pos())
	for ow in _orb_wins.duplicate():
		if not is_instance_valid(ow[0]):
			ow[1].queue_free()
			_orb_wins.erase(ow)
		else:
			_place_win(ow[1], ow[0].position)


## Special bullet in its own little window that homes in on the hero.
## Outside window mode it is just a big homing orb.
func window_orb(o: Vector2, dir: Vector2, speed: float, power: float, source: String) -> void:
	if _shots.get_child_count() > 450:
		return
	var p = ShotScript.new()
	p.vel = dir * speed
	p.hostile = true
	p.power = power
	p.source = source
	p.color = Color("ff2a8a")
	p.radius = 6.0
	p.life = 7.0
	p.curse = true
	p.homing_t = 6.0
	p.position = o
	_shots.add_child(p)
	p.setup(self, {})
	if win_mode and _orb_wins.size() < 8:
		_orb_wins.append([p, _make_win("!!!", Vector2i(110, 110), false)])


func _exit_windows() -> void:
	for k in _wins:
		if is_instance_valid(_wins[k]):
			_wins[k].hide()
			_wins[k].queue_free()
	_wins.clear()
	for ow in _orb_wins:
		if is_instance_valid(ow[1]):
			ow[1].hide()
			ow[1].queue_free()
	_orb_wins.clear()
	if _win_backdrop:
		_win_backdrop.queue_free()
		_win_backdrop = null
	win_mode = false
	get_viewport().gui_embed_subwindows = true
	DisplayServer.window_set_mode(_main_mode if _main_mode != DisplayServer.WINDOW_MODE_MINIMIZED else DisplayServer.WINDOW_MODE_FULLSCREEN)
	DisplayServer.window_move_to_foreground()


func _exit_tree() -> void:
	if win_mode:
		_exit_windows()


func _cam() -> Camera2D:
	for c in player.get_children():
		if c is Camera2D:
			return c
	return null


## Phase 2 of the demon lord: freeze, the scripted lines, a power-up flash.
func boss_power_up(e) -> void:
	if cutscene:
		return
	cutscene = true
	_dialog = true
	for c in _shots.get_children():
		c.queue_free()
	if not _phase_said.get(2, false):
		_phase_said[2] = true
		await _talk(_phase2_lines(), _faces())
	if _ended or not is_inside_tree():
		return
	Game.sfx("thunder")
	shake(6.0, 0.6)
	_banner("— เฟส 2/3 —", Color("ff5a9a"), 30)
	if is_instance_valid(e):
		var fl: Tween = e.create_tween()
		fl.tween_property(e.spr, "self_modulate", Color(3, 1.5, 3), 0.15)
		fl.tween_property(e.spr, "self_modulate", Color(1.0, 0.7, 1.0), 0.4)
	cutscene = false
	_dialog = false


## Window-mode dialogue: the same box in its own always-on-top OS window near the top of the
## desktop, so the fight windows can't cover it. It takes focus for E / Space / click.
func _talk_window(lines: Array, faces: Dictionary) -> void:
	var w := Window.new()
	w.title = "บทสนทนา"
	w.size = Vector2i(880, 170)
	w.unresizable = true
	w.always_on_top = true
	w.borderless = true
	add_child(w)
	var scr := DisplayServer.window_get_current_screen()
	w.position = DisplayServer.screen_get_position(scr) + Vector2i((DisplayServer.screen_get_size(scr).x - 880) / 2, 40)
	var box = DialogScript.new()
	box.theme = get_tree().root.theme
	box.position = Vector2.ZERO
	w.add_child(box)
	box.position = Vector2.ZERO
	w.grab_focus()
	await box.say(lines, faces, _names())
	w.queue_free()
	if is_instance_valid(_wins.get("player")):
		_wins.player.grab_focus()


## Screen shake on the hero's camera.
func shake(strength: float, dur: float) -> void:
	var cam := _cam()
	if cam == null:
		return
	var tw := cam.create_tween()
	for k in int(dur / 0.04):
		tw.tween_property(cam, "offset", Vector2(randf_range(-1, 1), randf_range(-1, 1)) * strength, 0.04)
	tw.tween_property(cam, "offset", Vector2.ZERO, 0.04)


## Boss phase change: taunt, flash, shake.
func boss_phase(e, ph: int) -> void:
	var lines := {2: "เจ้าคิดว่าแค่นี้จะพอหรือ! คำสาปของข้ายังไม่เริ่มเลย!", 3: "ข้าจะไม่ยอม... ให้วงจรนี้จบลงที่เจ้า!"}
	Game.sfx("thunder")
	_banner("— ระยะที่ %d —" % ph, Color("ff5a9a"), 30)
	say_over(e, lines.get(ph, "!"), Color("ff7ab0"))
	shake(5.0, 0.5)
	var fl: Tween = e.create_tween()
	fl.tween_property(e.spr, "self_modulate", Color(3, 2, 3), 0.12)
	fl.tween_property(e.spr, "self_modulate", Color.WHITE, 0.3)


# ---------------------------------------------------------------- combat helpers
func _roll(mult: float, def: float) -> Dictionary:
	var d := float(_s.atk) * mult * randf_range(0.9, 1.1) - def * 0.5
	var crit := randf() < float(Game.CLASSES[_s.cls].crit)
	if crit:
		d *= 1.7
	return {"dmg": maxi(1, roundi(d)), "crit": crit}


func damage_enemy(e, mult: float, ignore_def: bool, knock := Vector2.ZERO, slow := 0.0) -> void:
	if e.dead or _ended:
		return
	var r := _roll(mult, 0.0 if ignore_def else e.def)
	e.hurt(r.dmg, knock)
	if slow > 0.0:
		e.slow_t = slow
	Game.sfx("hit")
	Game.spawn_vfx(self, "hit", e.hit_pos(), 0.5)
	world_text(e.hit_pos() - Vector2(0, e.height / 2.0), ("CRIT %d" if r.crit else "%d") % r.dmg, Color("ffe066") if r.crit else Color.WHITE)
	if e.is_boss():
		var before := Game.boss_phase()
		Game.damage_boss(r.dmg, false)
		_boss_dirty = true
		e.hp = int(Game.data.boss_hp)
		if Game.boss_phase() != before:
			Game.save_game()
		elif e.hp <= 0:
			_boss_last_pos = e.global_position
			e.kill()
			enemies.erase(e)
			_win()
	elif e.hp <= 0:
		_on_kill(e)


func _on_kill(e) -> void:
	e.kill()
	enemies.erase(e)
	Game.sfx("die")
	var xp := roundi(float(e.e.xp) * float(_s.xp_mult))
	var gold := roundi(float(e.e.gold) * float(_s.gold_mult) * randf_range(0.8, 1.2))
	_s.gold = int(_s.gold) + gold
	world_text(e.hit_pos() + Vector2(0, 6), "+%dG" % gold, Color("ffd24a"), 20)
	if randf() < 0.15:
		_spawn_pickup(DROP_TABLE.pick_random(), e.global_position)
	if e.id.begins_with("wrath_"):
		_wrath = null
		_boss_box.visible = false
		_murder(e.title)
		_spawn_pickup("potion", e.global_position + Vector2(10, 0))
		_spawn_pickup("meat", e.global_position + Vector2(-10, 0))
	if Game.gain_xp(xp) > 0:
		Game.sfx("levelup")
		Game.spawn_vfx(self, "heal", player.hit_pos(), 0.6)
		player.mp = float(_s.mp)
		say_over(player, "LEVEL UP! Lv%d" % _s.lv, Color("7ad66b"))


func hurt_player(power: float, source: String, curse := false) -> void:
	if _ended or player == null or player.dead:
		return
	# Mark of sin: +15% damage taken per stack.
	var d: int = player.take_hit(power * (1.0 + 0.15 * int(_s.get("sin", 0))))
	if d < 0:
		# Parried: fully blocked, +20 HP.
		Game.sfx("coin")
		Game.spawn_vfx(self, "hit", player.hit_pos(), 0.7)
		fx_ring(player.hit_pos(), 22.0, Color("ffffff"))
		world_text(player.hit_pos() - Vector2(0, 14), "PARRY! +%d" % player.PARRY_HEAL, Color("8fe8ff"), 24)
		_hud.refresh()
		return
	if d == 0:
		return
	if curse:
		if player.curse_t <= 0.0:
			say_over(player, "ติดคำสาปบาป!", Color("d36bff"))
		player.curse_t = 3.0
	Game.sfx("hurt")
	Game.spawn_vfx(self, "blood", player.hit_pos(), 0.8)
	world_text(player.hit_pos() - Vector2(0, 12), "-%d" % d, Game.C_BAD)
	if int(_s.hp) <= 0:
		_on_death(source)


func _on_death(source: String, raw_cause := false) -> void:
	_ended = true
	player.die()
	Game.sfx("bad")
	if _boss_dirty:
		Game.save_game()
	await get_tree().create_timer(1.6).timeout
	_exit_windows()
	Game.die(source if raw_cause else "ถูก%sสังหาร" % source)
	get_tree().paused = false
	Game.goto("ending")


var _boss_last_pos := Vector2.ZERO


func _win() -> void:
	_ended = true
	_boss_box.visible = false
	for c in _shots.get_children():
		c.queue_free()
	_exit_windows()
	if Game.skip_cutscenes:
		await get_tree().create_timer(0.5).timeout
		Game.win()
		get_tree().paused = false
		Game.goto("ending")
		return
	await _victory_cutscene()
	# The blue screen "restarts" the game: new loop, back to the title.
	Game.win()
	get_tree().paused = false
	Game.goto("title")


## The boss explodes, the world goes black except the two of them, the darkness swallows the
## hero who becomes the next demon lord, and the "game" blue-screens while it resets.
func _victory_cutscene() -> void:
	cutscene = true
	_ui.visible = false
	if Game._bgm:
		Game._bgm.stop()
	var faces := _faces()
	var ct := get_viewport().get_canvas_transform()
	var e: Dictionary = Game.ENEMIES["demon_lord"]
	var bsc: float = e.scale / 4.0 * ZOOM
	# Explosion while he screams.
	_boss_explodes()
	await _talk([["boss", "อ๊าาากกกกก!!!"]], faces, 45)
	# Everything black except the hero and the boss (screen-space copies above a black layer).
	var layer := CanvasLayer.new()
	layer.layer = 30
	add_child(layer)
	var flash := ColorRect.new()
	flash.size = Vector2(960, 540)
	flash.color = Color.WHITE
	layer.add_child(flash)
	var black := ColorRect.new()
	black.size = Vector2(960, 540)
	black.color = Color.BLACK
	black.modulate.a = 0.0
	layer.add_child(black)
	var boss := Game.enemy_sprite("demon_lord", 1.0)
	boss.scale = Vector2(bsc, bsc)
	boss.position = ct * _boss_last_pos + Vector2(0, -e.fh * bsc / 2.0)
	layer.add_child(boss)
	var hero := Game.hero_sprite(_s.cls, ZOOM)
	hero.position = ct * player.global_position + Vector2(0, -14 * ZOOM)
	hero.flip_h = boss.position.x < hero.position.x
	layer.add_child(hero)
	for n in [boss, hero]:
		var g := Sprite2D.new()
		g.texture = _glow_tex
		g.material = _add_mat
		g.modulate = Color(0.7, 0.7, 1.0, 0.35)
		g.scale = Vector2(3.0, 1.2)
		g.position = n.position + Vector2(0, 40)
		layer.add_child(g)
	layer.move_child(boss, -1)
	layer.move_child(hero, -1)
	var tw := create_tween()
	tw.tween_property(flash, "modulate:a", 0.0, 0.6)
	tw.parallel().tween_property(black, "modulate:a", 1.0, 0.8)
	await tw.finished
	await _talk([
		["hero", "มันจบแล้วล่ะ แกแพ้แล้ว"],
		["boss", "หึหึ.."],
		["boss", "ขอบคุณแกมาก ที่[color=yellow]ปลดปล่อย[/color]ข้า"],
		["hero", "หมายความว่าไงน่ะ.."],
		["boss", "ตัวข้าได้ตระหนักรู้ นอกจากโลกใบนี้ ที่จำกัดแบบนี้ ใน[color=yellow]ไฟล์เล็กๆ[/color]แห่งนี้"],
		["hero", "แกพูดถึงเรื่องอะไ-"],
	], faces, 45)
	# The darkness swallows the hero.
	var dark := CPUParticles2D.new()
	dark.position = hero.position
	dark.amount = 60
	dark.lifetime = 1.2
	dark.emission_shape = CPUParticles2D.EMISSION_SHAPE_SPHERE
	dark.emission_sphere_radius = 40.0
	dark.direction = Vector2.UP
	dark.spread = 180.0
	dark.gravity = Vector2(0, -40)
	dark.initial_velocity_min = 20.0
	dark.initial_velocity_max = 60.0
	dark.texture = _glow_tex
	dark.scale_amount_min = 0.3
	dark.scale_amount_max = 0.7
	dark.color = Color(0.45, 0.0, 0.6, 0.8)
	layer.add_child(dark)
	Game.sfx("thunder")
	create_tween().tween_property(hero, "modulate", Color(0.35, 0.05, 0.45), 1.2)
	await _talk([
		["boss", "จงติดอยู่ใน[color=red]พันธนาการ[/color]ของเกมห่วยๆ แบบนี้ไปตลอดกาลซะเถอะ!!"],
		["hero", "อ๊าาาากกกกก"],
	], faces, 45)
	# He becomes the next demon lord.
	Game.sfx("explosion")
	shake(8.0, 0.6)
	var lord := Game.enemy_sprite("demon_lord", 1.0)
	lord.scale = Vector2(bsc, bsc) * 0.8
	lord.position = hero.position + Vector2(0, -20)
	lord.modulate.a = 0.0
	layer.add_child(lord)
	var tf := create_tween()
	tf.tween_property(hero, "modulate:a", 0.0, 0.8)
	tf.parallel().tween_property(lord, "modulate:a", 1.0, 0.8)
	tf.parallel().tween_property(boss, "modulate:a", 0.0, 1.2)
	await tf.finished
	await get_tree().create_timer(1.2).timeout
	await _fake_bsod()


func _boss_explodes() -> void:
	for k in 6:
		Game.spawn_vfx(self, "explosion", _boss_last_pos + Vector2(randf_range(-16, 16), randf_range(-30, 0)), randf_range(1.2, 2.2))
		Game.sfx("explosion")
		shake(7.0, 0.3)
		await get_tree().create_timer(0.25).timeout


## Fake Windows 10 blue screen covering the whole real window (no letterbox), in English like the
## real thing, counting up to 100% before the game "restarts".
func _fake_bsod() -> void:
	var root_win := get_tree().root
	root_win.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_EXPAND
	if DisplayServer.window_get_mode() != DisplayServer.WINDOW_MODE_FULLSCREEN:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
	await get_tree().process_frame
	Input.mouse_mode = Input.MOUSE_MODE_HIDDEN
	var vs := get_viewport().get_visible_rect().size
	var u := vs.y / 720.0  # layout measured on a 1280x720 reference
	var x0 := (vs.x - 1280.0 * u) / 2.0
	var font := SystemFont.new()
	font.font_names = PackedStringArray(["Segoe UI Light", "Segoe UI", "Arial"])
	font.antialiasing = TextServer.FONT_ANTIALIASING_GRAY
	var layer := CanvasLayer.new()
	layer.layer = 100
	add_child(layer)
	var bg := ColorRect.new()
	bg.color = Color(0.0, 0.47, 0.843)
	bg.position = Vector2(-10, -10)
	bg.size = vs + Vector2(20, 20)
	layer.add_child(bg)
	var txt := func(s: String, size: float, at: Vector2, width: float) -> Label:
		var l := Label.new()
		l.text = s
		l.add_theme_font_override("font", font)
		l.add_theme_font_size_override("font_size", int(size * u))
		l.add_theme_color_override("font_color", Color.WHITE)
		l.position = Vector2(x0, 0) + at * u
		if width > 0.0:
			l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			l.custom_minimum_size = Vector2(width * u, 0)
			l.size = Vector2(width * u, 0)
		layer.add_child(l)
		return l
	txt.call(":(", 150, Vector2(128, 70), 0.0)
	txt.call("Your PC ran into a problem and needs to restart. We're\njust collecting some error info, and then we'll restart for\nyou.", 26, Vector2(138, 262), 0.0)
	var pct: Label = txt.call("0% complete", 26, Vector2(138, 398), 0.0)
	var qr := QRCode.new()
	qr.position = Vector2(x0, 0) + Vector2(138, 468) * u
	qr.scale = Vector2(u, u)
	layer.add_child(qr)
	txt.call("For more information about this issue and possible fixes, visit https://www.windows.com/stopcode", 13, Vector2(228, 464), 0.0)
	txt.call("If you call a support person, give them this info:", 11, Vector2(228, 508), 0.0)
	txt.call("Stop code: CRITICAL_PROCESS_DIED", 11, Vector2(228, 530), 0.0)
	var logo := WinLogo.new()
	logo.position = Vector2(x0, 0) + Vector2(966, 266) * u
	logo.scale = Vector2(u, u)
	layer.add_child(logo)
	var p := 0
	while p < 100:
		await get_tree().create_timer(randf_range(0.05, 0.45)).timeout
		p = mini(100, p + randi_range(1, 9))
		pct.text = "%d%% complete" % p
	await get_tree().create_timer(0.8).timeout
	var black := ColorRect.new()
	black.color = Color.BLACK
	black.position = Vector2(-10, -10)
	black.size = vs + Vector2(20, 20)
	layer.add_child(black)
	await get_tree().create_timer(1.0).timeout
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	root_win.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_KEEP


## Fake QR code (finder squares + noise) for the blue screen, 77x77 at the reference scale.
class QRCode extends Node2D:
	func _draw() -> void:
		draw_rect(Rect2(0, 0, 77, 77), Color.WHITE)
		var cell := 77.0 / 25.0
		var rng := RandomNumberGenerator.new()
		rng.seed = 1709
		for y in 21:
			for x in 21:
				var finder := (x < 7 and y < 7) or (x > 13 and y < 7) or (x < 7 and y > 13)
				if finder:
					var fx := x % 14 if x > 13 else x
					var fy := y % 14 if y > 13 else y
					var ring := maxi(absi(fx - 3), absi(fy - 3))
					if ring == 3 or ring <= 1:
						draw_rect(Rect2((x + 2) * cell, (y + 2) * cell, cell, cell), Color(0.0, 0.47, 0.843))
				elif rng.randf() < 0.5:
					draw_rect(Rect2((x + 2) * cell, (y + 2) * cell, cell, cell), Color(0.0, 0.47, 0.843))


## White four-pane Windows logo, skewed like the Windows 10 one.
class WinLogo extends Node2D:
	func _draw() -> void:
		var g := 6.0
		var w := 188.0
		var h := 188.0
		var mx := w * 0.41
		var my := h * 0.5
		var c := Color.WHITE
		draw_colored_polygon(PackedVector2Array([Vector2(0, 18), Vector2(mx - g, 9), Vector2(mx - g, my - g), Vector2(0, my - g)]), c)
		draw_colored_polygon(PackedVector2Array([Vector2(mx, 8), Vector2(w, 0), Vector2(w, my - g), Vector2(mx, my - g)]), c)
		draw_colored_polygon(PackedVector2Array([Vector2(0, my), Vector2(mx - g, my), Vector2(mx - g, h - 9), Vector2(0, h - 18)]), c)
		draw_colored_polygon(PackedVector2Array([Vector2(mx, my), Vector2(w, my), Vector2(w, h), Vector2(mx, h - 8)]), c)

func enemies_near(pos: Vector2, r: float) -> Array:
	return enemies.filter(func(e): return not e.dead and e.hit_pos().distance_to(pos) < r + e.radius)


func hit_arc(o: Vector2, dir: Vector2, r: float, spread: float, mult: float, ignore_def: bool) -> void:
	for e in enemies.duplicate():
		var v: Vector2 = e.hit_pos() - o
		if e.dead or v.length() > r + e.radius:
			continue
		if v.length() < e.radius or absf(dir.angle_to(v)) < spread / 2.0:
			damage_enemy(e, mult, ignore_def, v.normalized() * 90.0)
	for t in npc_targets.duplicate():
		var v: Vector2 = _npc_center(t) - o
		if v.length() < r + 8.0 and (v.length() < 8.0 or absf(dir.angle_to(v)) < spread / 2.0):
			_hit_npc(t, mult)


func hit_circle(o: Vector2, r: float, mult: float, ignore_def: bool, slow := 0.0) -> void:
	for e in enemies.duplicate():
		var v: Vector2 = e.hit_pos() - o
		if not e.dead and v.length() < r + e.radius:
			damage_enemy(e, mult, ignore_def, v.normalized() * 70.0, slow)
	for t in npc_targets.duplicate():
		if _npc_center(t).distance_to(o) < r + 8.0:
			_hit_npc(t, mult)


func shoot(o: Vector2, dir: Vector2, speed: float, mult: float, opts := {}) -> void:
	var p = ShotScript.new()
	p.vel = dir * speed
	p.mult = mult
	p.position = o + dir * 6.0
	_shots.add_child(p)
	p.setup(self, opts)


func enemy_shot(o: Vector2, dir: Vector2, speed: float, power: float, source: String, color: Color, curse := false, homing := 0.0) -> void:
	if _shots.get_child_count() > 450:
		return
	var p = ShotScript.new()
	p.homing_t = homing
	p.curse = curse
	p.vel = dir * speed
	p.hostile = true
	p.power = power
	p.source = source
	p.color = color
	p.radius = 3.0
	p.life = 4.0
	p.position = o
	_shots.add_child(p)
	p.setup(self, {})


func arrow_rain(pos: Vector2, r: float, mult: float, ticks: int) -> void:
	fx_warn(pos, r, 0.35)
	for t in ticks:
		await get_tree().create_timer(0.28, false).timeout
		if _ended:
			return
		Game.sfx("swing")
		for k in 3:
			Game.spawn_vfx(self, "hit", pos + Vector2(randf_range(-r, r), randf_range(-r, r)) * 0.7, 0.5)
		hit_circle(pos, r, mult, false)


func is_open(pos: Vector2) -> bool:
	var c := Vector2i((pos / T).floor())
	return _walk.has(c) and not _closed.has(c)


func nearest_open(to: Vector2, from: Vector2) -> Vector2:
	var p := to
	for i in 20:
		var ok := true
		for off in [Vector2(6, 0), Vector2(-6, 0), Vector2(0, 2), Vector2(0, -12)]:
			if not is_open(p + off):
				ok = false
		if ok:
			return p
		p = p.lerp(from, 0.12)
	return from


# ---------------------------------------------------------------- effects
func world_text(pos: Vector2, text: String, color := Color.WHITE, size := 26) -> void:
	var l := Game.label(text, size, color)
	l.add_theme_constant_override("outline_size", 6)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.size = Vector2(240, 40)
	l.scale = Vector2(0.4, 0.4)
	l.position = pos - Vector2(48, 8)
	_fx.add_child(l)
	var tw := l.create_tween()
	tw.tween_property(l, "position:y", l.position.y - 16.0, 0.7).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(l, "modulate:a", 0.0, 0.7).set_delay(0.3)
	tw.tween_callback(l.queue_free)


func say_over(n: Node2D, text: String, color := Color.WHITE) -> void:
	world_text(n.global_position - Vector2(0, 34), text, color, 22)


func fx_arc(o: Vector2, dir: Vector2, r: float, spread: float, color: Color) -> void:
	var f := Fx.new()
	f.kind = "arc"
	f.position = o
	f.radius = r
	f.dir = dir
	f.spread = spread
	f.color = color
	f.dur = 0.16
	_fx.add_child(f)


func fx_ring(o: Vector2, r: float, color: Color) -> void:
	var f := Fx.new()
	f.kind = "ring"
	f.position = o
	f.radius = r
	f.color = color
	f.dur = 0.3
	_fx.add_child(f)


func fx_line(o: Vector2, dir: Vector2, length: float, dur: float) -> void:
	var f := Fx.new()
	f.kind = "line"
	f.position = o
	f.dir = dir
	f.radius = length
	f.color = Color("ff5a8a")
	f.dur = dur
	_fx.add_child(f)


## Green circle = the only safe spot of an attack.
func fx_safe(o: Vector2, r: float, dur: float) -> void:
	var f := Fx.new()
	f.kind = "warn"
	f.position = o
	f.radius = r
	f.color = Color("5aff8a")
	f.dur = dur
	_fx.add_child(f)


func fx_warn(o: Vector2, r: float, dur: float) -> void:
	var f := Fx.new()
	f.kind = "warn"
	f.position = o
	f.radius = r
	f.color = Color("ff5a5a")
	f.dur = dur
	_fx.add_child(f)


## Short-lived drawn effect: slash arc, expanding ring, or a filling warning circle.
class Fx extends Node2D:
	var kind := "arc"
	var radius := 20.0
	var dir := Vector2.RIGHT
	var spread := PI / 2.0
	var color := Color.WHITE
	var dur := 0.2
	var t := 0.0

	func _process(delta: float) -> void:
		t += delta
		queue_redraw()
		if t >= dur:
			queue_free()

	func _draw() -> void:
		var k := clampf(t / dur, 0.0, 1.0)
		var c := Color(color, 1.0 - k)
		match kind:
			"arc":
				var a := dir.angle()
				draw_arc(Vector2.ZERO, radius * (0.75 + 0.25 * k), a - spread / 2.0, a + spread / 2.0, 20, c, 5.0)
				draw_arc(Vector2.ZERO, radius * (0.55 + 0.25 * k), a - spread / 3.0, a + spread / 3.0, 16, Color(c, c.a * 0.5), 3.0)
			"ring":
				draw_arc(Vector2.ZERO, radius * (0.3 + 0.7 * k), 0.0, TAU, 40, c, 4.0)
				draw_circle(Vector2.ZERO, radius * (0.3 + 0.7 * k), Color(c, c.a * 0.15))
			"line":
				draw_line(Vector2.ZERO, dir * radius, Color(color, 0.25 + 0.45 * k), 2.0 + 6.0 * k)
			"warn":
				draw_circle(Vector2.ZERO, radius * k, Color(color, 0.25))
				draw_arc(Vector2.ZERO, radius, 0.0, TAU, 32, Color(color, 0.7), 1.0)


## Swirl at the end of the stage; active once the last fight is won.
class Portal extends Node2D:
	var active := false
	var t := 0.0

	func _process(delta: float) -> void:
		t += delta
		queue_redraw()

	func _draw() -> void:
		var c := Color("8a5cff") if active else Color(0.4, 0.4, 0.45)
		draw_circle(Vector2.ZERO, 15.0, Color(c, 0.22))
		for i in 3:
			var a := t * (2.0 + i) * (1.0 if active else 0.3)
			draw_arc(Vector2.ZERO, 5.0 + i * 4.0, a, a + PI * 1.3, 16, Color(c, 0.9 - i * 0.2), 2.0)


## Parry button (F) at the bottom right with a cooldown fill and seconds left.
class ParryIcon extends Control:
	var p
	var _icon: TextureRect

	func _process(_delta: float) -> void:
		if _icon == null:
			_icon = TextureRect.new()
			_icon.texture = Game.tex("icons/shield.png")
			_icon.position = Vector2(14, 6)
			_icon.size = Vector2(36, 36)
			_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
			add_child(_icon)
		if p != null:
			_icon.modulate = Color(1, 1, 1, 0.3) if p.parry_cd > 0.0 else Color.WHITE
		queue_redraw()

	func _draw() -> void:
		if p == null:
			return
		var f := get_theme_default_font()
		var r := Rect2(0, 0, 64, 60)
		draw_rect(r, Color(0.08, 0.06, 0.11, 0.85))
		var frac: float = p.parry_cd / p.PARRY_CD
		if frac > 0.0:
			draw_rect(Rect2(0, 60.0 * (1.0 - frac), 64, 60.0 * frac), Color(0, 0, 0, 0.65))
			draw_string(f, Vector2(0, 36), "%.1f" % p.parry_cd, HORIZONTAL_ALIGNMENT_CENTER, 64, 16, Color.WHITE)
		var ready: bool = frac <= 0.0
		draw_rect(r, Color("8fe8ff") if p.parry_t > 0.0 else (Game.C_BORDER if ready else Color("5a5266")), false, 2.0)
		draw_string(f, Vector2(4, 13), "F", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color("f5d76e"))
		draw_string(f, Vector2(0, 56), "ปัดป้อง", HORIZONTAL_ALIGNMENT_CENTER, 64, 12, Game.C_TEXT if ready else Game.C_DIM)


## Bottom bar: M1, 1, 2, 3, Q, R, B (bag) with names, MP costs and cooldown shading.
class SkillBar extends Control:
	var p
	var _icons := []

	func _process(_delta: float) -> void:
		if p != null and _icons.is_empty():
			for i in 4:
				var ic := TextureRect.new()
				ic.texture = Game.tex("skills/%s_%d.png" % [p.cls, i])
				ic.position = Vector2(i * 70 + 44, 2)
				ic.size = Vector2(18, 18)
				ic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
				ic.mouse_filter = Control.MOUSE_FILTER_IGNORE
				add_child(ic)
				_icons.append(ic)
		for i in _icons.size():
			_icons[i].modulate = Color(1, 1, 1, 0.35) if p.cd[i] > 0.0 else Color.WHITE
		queue_redraw()

	func _draw() -> void:
		if p == null:
			return
		var f := get_theme_default_font()
		var keys := ["M1", "1", "2", "3", "Q", "R", "B"]
		for i in 7:
			var r := Rect2(i * 70, 0, 64, 52)
			draw_rect(r, Color(0.08, 0.06, 0.11, 0.85))
			var nm := ""
			var sub := ""
			var ok := true
			var left := 0.0
			var frac := 0.0
			if i < 4:
				var sk: Dictionary = p.kit[i]
				nm = sk.name
				sub = "MP %d" % sk.mp if int(sk.mp) > 0 else ""
				ok = p.mp >= float(sk.mp)
				left = p.cd[i]
				frac = left / float(sk.cd)
			elif i == 4:
				nm = "ยา HP"
				sub = "x%d" % Game.item_count("potion")
				ok = Game.item_count("potion") > 0
			elif i == 5:
				nm = "อีเธอร์"
				sub = "x%d" % Game.item_count("ether")
				ok = Game.item_count("ether") > 0
			else:
				nm = "กระเป๋า"
				sub = "%d/%d ช่อง" % [Game.bag_slots_used(), Game.BAG_SLOTS]
			if frac > 0.0:
				draw_rect(Rect2(r.position.x, r.position.y + r.size.y * (1.0 - frac), r.size.x, r.size.y * frac), Color(0, 0, 0, 0.65))
			draw_rect(r, Game.C_BORDER if ok and left <= 0.0 else Color("5a5266"), false, 2.0)
			draw_string(f, r.position + Vector2(4, 13), keys[i], HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color("f5d76e"))
			draw_string(f, r.position + Vector2(0, 32), nm, HORIZONTAL_ALIGNMENT_CENTER, 64, 12, Game.C_TEXT if ok else Game.C_DIM)
			draw_string(f, r.position + Vector2(0, 47), sub, HORIZONTAL_ALIGNMENT_CENTER, 64, 11, Color("8fb4ff"))
			if left > 0.05:
				draw_string(f, r.position + Vector2(-4, 14), "%.1f" % left, HORIZONTAL_ALIGNMENT_RIGHT, 64, 12, Color.WHITE)
