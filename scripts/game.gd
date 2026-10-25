@tool
extends Node
## Global game state (autoload "Game").
## Holds the 3 one-life save slots, the boss HP shared across every slot,
## karma passed from one life to the next, data tables, audio and UI helpers.

const SAVE_PATH := "user://saves.json"
const A := "res://game_assets/"
const BOSS_MAX_HP := 1000
const BOSS_PHASES := 3
const SLOT_COUNT := 3

# ---------------------------------------------------------------- data tables
# Hero sheets: rows idle / attack / hurt / die, 32x32 frames, frame counts below.
const CLASSES := {
	"knight": {
		"name": "อัศวิน", "sheet": "characters/knight.png", "counts": [2, 7, 2, 6],
		"hp": 1200, "mp": 20, "atk": 140, "def": 8, "crit": 0.08,
		"grow": {"hp": 14, "mp": 4, "atk": 3, "def": 2},
		"skill": "ฟันทะลวง", "skill_desc": "ฟันแรง 2.2 เท่า (MP 8)", "skill_mp": 8,
		# Real-time kit: index 0 = M1, 1..3 = keys 1, 2, 3.
		"skills": [
			{"name": "ฟันดาบ", "desc": "ฟันเป็นวงหน้าตัว", "mp": 0, "cd": 0.38},
			{"name": "พุ่งฟันทะลวง", "desc": "พุ่งไปทางเมาส์ ฟันทุกตัวที่ขวาง 2.2 เท่า", "mp": 8, "cd": 3.0},
			{"name": "หมุนดาบ", "desc": "ฟันรอบตัว 1.6 เท่า", "mp": 10, "cd": 5.0},
			{"name": "โล่ศักดิ์สิทธิ์", "desc": "รับดาเมจลด 70% 4 วิ ฟื้น HP 15%", "mp": 12, "cd": 12.0},
		],
	},
	"ranger": {
		"name": "นักธนู", "sheet": "characters/ranger.png", "counts": [2, 6, 2, 6],
		"hp": 950, "mp": 25, "atk": 160, "def": 5, "crit": 0.25,
		"grow": {"hp": 11, "mp": 4, "atk": 4, "def": 1},
		"skill": "ยิงสามดอก", "skill_desc": "ยิง 3 ดอกสุ่มเป้า ดอกละ 0.8 เท่า (MP 8)", "skill_mp": 8,
		"skills": [
			{"name": "ยิงธนู", "desc": "ยิงลูกธนูไปทางเมาส์", "mp": 0, "cd": 0.3},
			{"name": "ยิงสามดอก", "desc": "ยิงกระจาย 3 ดอก ดอกละ 0.9 เท่า", "mp": 6, "cd": 2.0},
			{"name": "กลิ้งหลบ", "desc": "กลิ้งไปทางที่เดิน อมตะชั่วครู่", "mp": 5, "cd": 2.5},
			{"name": "ฝนธนู", "desc": "ธนูตกใส่จุดเมาส์ 5 ระลอก", "mp": 14, "cd": 8.0},
		],
	},
	"wizard": {
		"name": "จอมเวท", "sheet": "characters/wizard.png", "counts": [2, 7, 2, 7],
		"hp": 880, "mp": 50, "atk": 120, "def": 4, "crit": 0.1,
		"grow": {"hp": 9, "mp": 8, "atk": 3, "def": 1},
		"skill": "ลูกไฟ", "skill_desc": "เผาศัตรูทุกตัว 1.6 เท่า ทะลุเกราะ (MP 10)", "skill_mp": 10,
		"skills": [
			{"name": "ลูกเวท", "desc": "ยิงลูกเวทไปทางเมาส์", "mp": 0, "cd": 0.4},
			{"name": "ลูกไฟ", "desc": "ลูกไฟระเบิดเป็นวง 1.8 เท่า ทะลุเกราะ", "mp": 9, "cd": 2.5},
			{"name": "วาร์ป", "desc": "เทเลพอร์ตไปจุดเมาส์", "mp": 8, "cd": 4.0},
			{"name": "น้ำแข็งพิฆาต", "desc": "ระเบิดน้ำแข็งรอบตัว 2 เท่า ศัตรูช้าลง", "mp": 18, "cd": 9.0},
		],
	},
}

const CONTROLS_TEXT := "WASD เดิน · คลิกซ้าย โจมตี · 1 2 3 สกิล · Q ยา HP · R อีเธอร์ · F ปัดป้อง · B กระเป๋า · E โต้ตอบ · Esc เมนู · F11 เต็มจอ"
# Survival: food and water drain with play time (per second); eating / drinking restores.
const FOOD_DRAIN := 1.0 / 6.0
const WATER_DRAIN := 1.0 / 4.0

# ---------------------------------------------------------------- items / bag
## Bag = slot.bag {item id: count}. 20 slots, each holding a stack of up to 9 of one item.
const BAG_SLOTS := 20
const STACK := 9
const ITEM_ORDER := ["potion", "ether", "herb", "fruit", "bread", "meat", "water", "juice"]
const ITEM_DEFS := {
	"potion": {"name": "ยา HP", "icon": "icons/potion.png", "desc": "ฟื้น HP 50% (ปุ่มลัด Q)", "heal": 0.5},
	"ether": {"name": "อีเธอร์", "icon": "icons/ether.png", "desc": "ฟื้น MP จนเต็ม (ปุ่มลัด R)", "mana": 1.0},
	"herb": {"name": "สมุนไพร", "icon": "items/herb.png", "desc": "ฟื้น HP 15%", "heal": 0.15},
	"fruit": {"name": "ผลไม้ป่า", "icon": "icons/food.png", "desc": "อาหาร +25", "food": 25.0},
	"bread": {"name": "ขนมปัง", "icon": "items/bread.png", "desc": "อาหาร +45", "food": 45.0},
	"meat": {"name": "เนื้อย่าง", "icon": "items/meat.png", "desc": "อาหาร +70 และ HP +10%", "food": 70.0, "heal": 0.1},
	"water": {"name": "กระติกน้ำ", "icon": "icons/water.png", "desc": "น้ำ +40", "water": 40.0},
	"juice": {"name": "น้ำผลไม้", "icon": "items/juice.png", "desc": "น้ำ +30 และอาหาร +10", "water": 30.0, "food": 10.0},
}


## The slot's bag, migrating the old potions / ethers / foods / waters counters on first use.
func bag(s: Dictionary = {}) -> Dictionary:
	if s.is_empty():
		s = slot()
	if not s.has("bag"):
		s.bag = {"potion": int(s.get("potions", 0)), "ether": int(s.get("ethers", 0)),
			"fruit": int(s.get("foods", 0)), "water": int(s.get("waters", 0))}
		for k in ["potions", "ethers", "foods", "waters"]:
			s.erase(k)
	return s.bag


func item_count(id: String) -> int:
	return int(bag().get(id, 0))


func bag_slots_used() -> int:
	var n := 0
	for id in bag():
		n += ceili(float(int(bag()[id])) / STACK)
	return n


## Adds n of an item; returns false (and adds nothing) when the bag has no room.
func add_item(id: String, n := 1) -> bool:
	var b := bag()
	var have := int(b.get(id, 0))
	var extra := ceili(float(have + n) / STACK) - ceili(float(have) / STACK)
	if bag_slots_used() + extra > BAG_SLOTS:
		return false
	b[id] = have + n
	return true


func remove_item(id: String, n := 1) -> bool:
	var b := bag()
	if int(b.get(id, 0)) < n:
		return false
	b[id] = int(b[id]) - n
	if int(b[id]) <= 0:
		b.erase(id)
	return true


## Consumes one item and applies its effect to the slot. Returns a short message, "" if unused.
func use_item(id: String) -> String:
	var s := slot()
	var d: Dictionary = ITEM_DEFS.get(id, {})
	if d.is_empty() or item_count(id) <= 0:
		return ""
	if d.has("heal") and not d.has("food") and int(s.hp) >= int(s.max_hp):
		return "HP เต็มอยู่แล้ว"
	if d.has("mana") and int(s.mp) >= int(s.max_mp):
		return "MP เต็มอยู่แล้ว"
	remove_item(id)
	var parts := []
	if d.has("heal"):
		var h := roundi(float(s.max_hp) * float(d.heal))
		s.hp = mini(int(s.max_hp), int(s.hp) + h)
		parts.append("HP +%d" % h)
	if d.has("mana"):
		s.mp = int(s.max_mp)
		parts.append("MP MAX")
	if d.has("food"):
		s.food = minf(100.0, float(s.get("food", 100.0)) + float(d.food))
		parts.append("อาหาร +%d" % int(d.food))
	if d.has("water"):
		s.water = minf(100.0, float(s.get("water", 100.0)) + float(d.water))
		parts.append("น้ำ +%d" % int(d.water))
	return " ".join(parts)

# kind "mini": 32px sheet like heroes (faces right, gets flipped). kind "big": 3-frame front strip.
const ENEMIES := {
	"slime": {"name": "สไลม์", "kind": "mini", "sheet": "monsters/slime.png", "counts": [7, 5, 2, 5],
		"hp": 30, "atk": 8, "def": 1, "xp": 10, "gold": 8},
	"skeleton": {"name": "โครงกระดูก", "kind": "mini", "sheet": "monsters/skeleton.png", "counts": [2, 6, 2, 6],
		"hp": 44, "atk": 11, "def": 3, "xp": 15, "gold": 12},
	"wraith": {"name": "วิญญาณร้าย", "kind": "mini", "sheet": "monsters/wraith.png", "counts": [5, 5, 2, 7],
		"hp": 52, "atk": 14, "def": 3, "xp": 22, "gold": 15},
	"wolf": {"name": "หมาป่าหิมะ", "kind": "big", "sheet": "monsters/wolf1.png", "fw": 65, "fh": 66, "scale": 2.0,
		"hp": 36, "atk": 10, "def": 2, "xp": 12, "gold": 9},
	"golem": {"name": "โกเลมหิน", "kind": "big", "sheet": "monsters/golem1.png", "fw": 47, "fh": 50, "scale": 2.4,
		"hp": 80, "atk": 13, "def": 8, "xp": 28, "gold": 18},
	"lizard": {"name": "มนุษย์กิ้งก่า", "kind": "big", "sheet": "monsters/lizardman1.png", "fw": 47, "fh": 50, "scale": 2.4,
		"hp": 60, "atk": 15, "def": 4, "xp": 24, "gold": 16},
	"minotaur": {"name": "มิโนทอร์ ผู้เฝ้าป้อม", "kind": "big", "sheet": "monsters/minotaur.png", "fw": 47, "fh": 50, "scale": 3.4,
		"hp": 230, "atk": 19, "def": 6, "xp": 110, "gold": 90, "special": "พุ่งชน", "special_mult": 1.8, "special_chance": 0.25},
	# Villagers that turn on a sinful hero (strip sheets like the NPCs, red tinted in enemy.gd).
	"wrath_merchant": {"name": "พ่อค้าผู้โกรธเกรี้ยว", "kind": "big", "sheet": "npcs/merchant.png", "fw": 26, "fh": 36, "scale": 5.0,
		"hp": 300, "atk": 20, "def": 5, "xp": 90, "gold": 120},
	"wrath_beggar": {"name": "ขอทานผู้ถูกสาป", "kind": "big", "sheet": "npcs/beggar.png", "fw": 26, "fh": 36, "scale": 5.0,
		"hp": 260, "atk": 22, "def": 3, "xp": 90, "gold": 60},
	"wrath_king": {"name": "ผู้ใหญ่บ้านผู้โกรธเกรี้ยว", "kind": "big", "sheet": "npcs/king.png", "fw": 26, "fh": 36, "scale": 5.0,
		"hp": 340, "atk": 20, "def": 6, "xp": 100, "gold": 100},
	"demon_lord": {"name": "จอมมาร", "kind": "big", "sheet": "monsters/lich.png", "fw": 47, "fh": 50, "scale": 4.2,
		"hp": BOSS_MAX_HP, "atk": 28, "def": 9, "xp": 0, "gold": 0, "special": "คำสาปแห่งการเกิดใหม่", "special_mult": 1.7, "special_chance": 0.35},
}

const STAGES := [
	{"name": "ด่าน 1 · ทุ่งหญ้าชายแดน", "bg": "backgrounds/stage1.png", "sil": "backgrounds/sil_ruins.png",
		"enemies": ["slime", "wolf", "skeleton"], "bgm": "stage"},
	{"name": "ด่าน 2 · ป้อมร้างมิโนทอร์", "bg": "backgrounds/stage2.png", "sil": "backgrounds/sil_castle.png",
		"enemies": ["skeleton", "wraith", "golem", "lizard"], "bgm": "stage"},
	{"name": "ด่าน 3 · ปราสาทจอมมาร", "bg": "backgrounds/stage3.png", "sil": "backgrounds/sil_spikes.png",
		"enemies": ["wraith", "golem"], "bgm": "boss"},
]

const NODE_INFO := {
	"battle": {"name": "มอนสเตอร์", "icon": "icons/sword.png"},
	"event": {"name": "เหตุการณ์สุ่ม", "icon": "icons/scroll.png"},
	"shop": {"name": "ร้านค้า", "icon": "icons/coin.png"},
	"grave": {"name": "หลุมศพชาติก่อน", "icon": "icons/skull.png"},
	"rest": {"name": "กองไฟพักแรม", "icon": "icons/heart.png"},
	"miniboss": {"name": "มินิบอส", "icon": "icons/shield.png"},
	"boss": {"name": "จอมมาร", "icon": "icons/crown.png"},
	"quest": {"name": "บ้านชาวบ้าน", "icon": "icons/scroll.png"},
}

# ---------------------------------------------------------------- state
var data: Dictionary = {}
var slot_index := -1
## Set before changing to scenes/ending.tscn: "death", "victory" or "all_dead".
var ending_mode := ""
var ending_info: Dictionary = {}
var ui_font: Font
## Tests set this to skip boss cutscenes.
var skip_cutscenes := false

var _bgm: AudioStreamPlayer
var _bgm_name := ""
var _sfx: Array[AudioStreamPlayer] = []


func _ready() -> void:
	randomize()
	if Engine.is_editor_hint():
		# Tool mode: only data is needed so scenes can draw a preview in the editor.
		load_game()
		return
	# Keeps music and the shop/event overlays alive while the stage is paused.
	process_mode = Node.PROCESS_MODE_ALWAYS
	_bgm = AudioStreamPlayer.new()
	_bgm.volume_db = -10.0
	add_child(_bgm)
	for i in 6:
		var p := AudioStreamPlayer.new()
		p.volume_db = -6.0
		add_child(p)
		_sfx.append(p)
	get_tree().root.theme = _make_theme()
	load_game()
	# Fullscreen by default (not when embedded in the editor's Game tab or headless).
	if _can_fullscreen():
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)


func _can_fullscreen() -> bool:
	if DisplayServer.get_name() == "headless":
		return false
	if Engine.has_method("is_embedded_in_editor") and Engine.call("is_embedded_in_editor"):
		return false
	return true


## F11 toggles fullscreen.
func _input(event: InputEvent) -> void:
	if Engine.is_editor_hint():
		return
	if event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_F11 and _can_fullscreen():
		var full := DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED if full else DisplayServer.WINDOW_MODE_FULLSCREEN)


# ---------------------------------------------------------------- save / load
func new_data() -> Dictionary:
	var slots := []
	for i in SLOT_COUNT:
		slots.append({"state": "empty"})
	return {
		"version": 1,
		"loop": 1,
		"boss_hp": BOSS_MAX_HP,
		# Demon lord has three HP bars (each phase starts with a fresh bar), shared by every life.
		"boss_phase": 1,
		"karma": 0,
		"graves": [],
		"slots": slots,
		"lives_used": 0,
		"prev_lord": "",
		"last_ending": "",
	}


func load_game() -> void:
	data = new_data()
	if not FileAccess.file_exists(SAVE_PATH):
		return
	var f := FileAccess.open(SAVE_PATH, FileAccess.READ)
	var parsed = JSON.parse_string(f.get_as_text())
	if parsed is Dictionary and parsed.has("slots"):
		for k in parsed:
			data[k] = parsed[k]


func save_game() -> void:
	if Engine.is_editor_hint():
		return
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	f.store_string(JSON.stringify(data, "\t"))


func slot() -> Dictionary:
	if Engine.is_editor_hint() and (slot_index < 0 or data.slots[slot_index].state != "active"):
		return _preview_slot()
	return data.slots[slot_index]


var _preview: Dictionary = {}


## Fake life used by the editor preview of in-run scenes.
func _preview_slot() -> Dictionary:
	if _preview.is_empty():
		_preview = {
			"state": "active", "cls": "knight", "life": 1, "lv": 3, "xp": 20,
			"hp": 110, "max_hp": 148, "mp": 20, "max_mp": 28, "atk": 20, "def": 12,
			"gold": 120, "stage": 0, "node": 1,
			"food": 70.0, "water": 25.0, "bag": {"potion": 2, "ether": 1, "fruit": 1, "water": 1, "meat": 1},
			"route": ["battle", "event", "shop", "battle"],
			"karma_at_birth": 0, "xp_mult": 1.0, "gold_mult": 1.0, "enemy_mult": 1.0, "extra_foes": 0,
			"boss_dmg": 0, "deeds": [], "pending_event": "", "pending_foes": ["slime", "skeleton"],
		}
	return _preview


## Remaining strength over all bars (1.0 = untouched phase 1, 0.0 = dead).
func boss_ratio() -> float:
	var bar := clampf(float(data.boss_hp) / BOSS_MAX_HP, 0.0, 1.0)
	return (float(BOSS_PHASES - boss_phase()) + bar) / BOSS_PHASES


func boss_phase() -> int:
	return int(data.get("boss_phase", 1))


## The boss gets weaker the less HP it has left (shared over every slot).
func boss_power() -> float:
	return lerpf(0.55, 1.2, boss_ratio()) * (1.0 + 0.15 * (int(data.loop) - 1))


func karma_text(k: int) -> String:
	if k > 0:
		return "ความดี +%d" % k
	if k < 0:
		return "ความชั่ว %d" % k
	return "ไม่บาป"


## Picking an empty slot means being born: the class is random, the run starts right away.
func birth(i: int) -> void:
	if has_living():
		return
	slot_index = i
	var keys := CLASSES.keys()
	var cls: String = keys[randi() % keys.size()]
	var c: Dictionary = CLASSES[cls]
	var k := int(data.karma)
	data.lives_used = int(data.lives_used) + 1
	var s := {
		"state": "active", "cls": cls, "life": int(data.lives_used), "lv": 1, "xp": 0,
		"hp": c.hp, "max_hp": c.hp, "mp": c.mp, "max_mp": c.mp, "atk": c.atk, "def": c.def,
		"gold": 30, "stage": 0, "node": 0, "route": [],
		"food": 100.0, "water": 100.0, "bag": {"potion": 2, "ether": 1, "fruit": 1, "water": 1},
		"karma_at_birth": k, "xp_mult": 1.0, "gold_mult": 1.0, "enemy_mult": 1.0, "extra_foes": 0,
		"boss_dmg": 0, "deeds": [], "pending_event": "",
	}
	if k > 0:
		# Good deeds of the past life: a gentler, richer start.
		s.gold += 25 * k
		s.bag.potion = int(s.bag.potion) + k
		s.max_hp += 10 * k
		s.hp = s.max_hp
	elif k < 0:
		# Bad deeds: more monsters, more XP but less gold.
		s.extra_foes = mini(-k, 2)
		s.xp_mult = 1.0 + 0.25 * -k
		s.gold_mult = maxf(0.4, 1.0 - 0.2 * -k)
		s.enemy_mult = 1.0 + 0.05 * -k
	data.karma = 0
	data.slots[i] = s
	build_route()
	save_game()


func build_route() -> void:
	var s := slot()
	var st := int(s.stage)
	var r: Array = []
	match st:
		0:
			r = ["battle", "event", "shop", "battle"]
			for n in int(s.extra_foes):
				r.insert(1, "battle")
		1:
			r = ["battle", "shop", "event", "battle", "miniboss"]
			if int(s.extra_foes) >= 2:
				r.insert(0, "battle")
		2:
			r = ["rest", "boss"]
	for g in data.graves:
		if int(g.stage) == st:
			r.insert(1, "grave")
			break
	s.route = r
	s.node = 0
	# Side rooms (shop / event / grave / rest) can be visited in any order, once each.
	s.used = []
	s.event_kinds = {}
	s.visit = ""
	s.quest_state = {}
	s.picked = []


## True once the side room at route index k has been used up this stage.
func is_used(k: int) -> bool:
	for x in slot().get("used", []):
		if int(x) == k:
			return true
	return false


## Called by event.gd when a side room's event is finished.
func mark_visited() -> void:
	var s := slot()
	if not s.has("used"):
		s.used = []
	s.used.append(int(s.get("visit_k", -1)))
	s.visit = ""
	s.pending_event = ""
	save_game()


func current_node() -> String:
	var s := slot()
	if str(s.get("visit", "")) != "":
		return s.visit
	if int(s.node) < s.route.size():
		return s.route[int(s.node)]
	return ""


func advance_node() -> void:
	var s := slot()
	s.node = mini(int(s.node) + 1, s.route.size())
	s.pending_event = ""
	if int(s.node) >= s.route.size() and int(s.stage) < STAGES.size() - 1:
		s.stage = int(s.stage) + 1
		build_route()
	save_game()


func xp_to_next(lv: int) -> int:
	return 20 + lv * 25


## Returns number of levels gained.
func gain_xp(amount: int) -> int:
	var s := slot()
	var c: Dictionary = CLASSES[s.cls]
	s.xp = int(s.xp) + amount
	var ups := 0
	while int(s.xp) >= xp_to_next(int(s.lv)):
		s.xp = int(s.xp) - xp_to_next(int(s.lv))
		s.lv = int(s.lv) + 1
		s.max_hp = int(s.max_hp) + int(c.grow.hp)
		s.max_mp = int(s.max_mp) + int(c.grow.mp)
		s.atk = int(s.atk) + int(c.grow.atk)
		s.def = int(s.def) + int(c.grow.def)
		s.hp = mini(int(s.max_hp), int(s.hp) + int(s.max_hp * 0.3))
		s.mp = int(s.max_mp)
		ups += 1
	return ups


## Real-time fights pass save=false and save in batches themselves.
func damage_boss(amount: int, save := true) -> void:
	data.boss_hp = maxi(0, int(data.boss_hp) - amount)
	if int(data.boss_hp) <= 0 and boss_phase() < BOSS_PHASES:
		# Bar emptied: the next phase starts with a full bar.
		data.boss_phase = boss_phase() + 1
		data.boss_hp = BOSS_MAX_HP
	slot().boss_dmg = int(slot().boss_dmg) + amount
	if save:
		save_game()


## Death locks the slot for good, leaves a grave for the next lives and
## ends the cycle if every slot is now dead.
func die(cause: String) -> void:
	var s := slot()
	var stage_i := int(s.stage)
	s.state = "dead"
	s.cause = cause
	s.died_stage = stage_i
	data.graves.append({"stage": stage_i, "gold": int(s.gold) / 2, "cls": s.cls, "life": s.life, "atk": 2 + int(s.lv)})
	ending_info = {"slot": slot_index, "cls": s.cls, "cause": cause, "stage": stage_i, "lv": s.lv, "boss_dmg": s.boss_dmg}
	if all_dead():
		ending_mode = "all_dead"
		data.last_ending = "all_dead"
		start_new_cycle(false)
	else:
		ending_mode = "death"
		save_game()


## Only one hero may be alive at a time.
func has_living() -> bool:
	for s in data.slots:
		if s.state == "active":
			return true
	return false


func all_dead() -> bool:
	for s in data.slots:
		if s.state != "dead":
			return false
	return true


## Boss dead: the hero inherits the curse. Every slot unlocks and a new loop begins
## with the old hero as the new demon lord.
func win() -> void:
	var s := slot()
	ending_info = {"slot": slot_index, "cls": s.cls, "lv": s.lv, "loop": data.loop, "boss_dmg": s.boss_dmg}
	ending_mode = "victory"
	data.prev_lord = s.cls
	data.last_ending = "victory"
	start_new_cycle(true)


## Unlocks every slot. A victory starts the next loop with a slightly stronger lord;
## a total wipe heals the lord back to full.
func start_new_cycle(victory: bool) -> void:
	var keep_lord: String = data.prev_lord
	var loop := int(data.loop)
	var last: String = data.last_ending
	var lives := int(data.lives_used)
	data = new_data()
	data.loop = loop + 1 if victory else loop
	data.prev_lord = keep_lord
	data.last_ending = last
	data.lives_used = lives
	save_game()


func boss_title() -> String:
	if data.prev_lord != "":
		return "จอมมาร (อดีต%s)" % CLASSES[data.prev_lord].name
	return "จอมมาร"


# ---------------------------------------------------------------- audio
func play_bgm(name: String) -> void:
	if _bgm == null:
		return
	if name == _bgm_name and _bgm.playing:
		return
	_bgm_name = name
	var st: AudioStream = load(A + "bgm/" + name + ".ogg")
	if st is AudioStreamOggVorbis:
		st.loop = true
	_bgm.stream = st
	_bgm.play()


func sfx(name: String) -> void:
	if _sfx.is_empty():
		return
	var st: AudioStream = load(A + "sfx/" + name + ".wav")
	for p in _sfx:
		if not p.playing:
			p.stream = st
			p.play()
			return
	_sfx[0].stream = st
	_sfx[0].play()


# ---------------------------------------------------------------- UI helpers
const C_BG := Color("1a1424")
const C_PANEL := Color("2a2038")
const C_BORDER := Color("c9a227")
const C_TEXT := Color("f2e8cf")
const C_DIM := Color("8a7f99")
const C_HP := Color("d64545")
const C_MP := Color("4573d6")
const C_GOOD := Color("7ad66b")
const C_BAD := Color("e0525a")


func _make_theme() -> Theme:
	var t := Theme.new()
	var f := SystemFont.new()
	f.font_names = PackedStringArray(["Leelawadee UI", "Leelawadee", "Tahoma", "Noto Sans Thai", "Sarabun", "sans-serif"])
	f.antialiasing = TextServer.FONT_ANTIALIASING_GRAY
	ui_font = f
	t.default_font = f
	t.default_font_size = 18
	t.set_color("font_color", "Label", C_TEXT)
	t.set_color("default_color", "RichTextLabel", C_TEXT)
	t.set_stylebox("panel", "PanelContainer", panel_style())
	t.set_stylebox("panel", "Panel", panel_style())
	t.set_stylebox("normal", "Button", _btn_style(Color("3b2d52")))
	t.set_stylebox("hover", "Button", _btn_style(Color("54406f")))
	t.set_stylebox("pressed", "Button", _btn_style(Color("6b5290")))
	t.set_stylebox("disabled", "Button", _btn_style(Color("2a2433"), Color("4a4458")))
	t.set_stylebox("focus", "Button", StyleBoxEmpty.new())
	t.set_color("font_color", "Button", C_TEXT)
	t.set_color("font_hover_color", "Button", Color.WHITE)
	t.set_color("font_disabled_color", "Button", C_DIM)
	t.set_stylebox("background", "ProgressBar", _flat(Color("120d18"), Color("000000"), 1))
	t.set_stylebox("fill", "ProgressBar", _flat(C_HP))
	t.set_constant("separation", "VBoxContainer", 6)
	t.set_constant("separation", "HBoxContainer", 8)
	return t


func _flat(bg: Color, border := Color(0, 0, 0, 0), bw := 0) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.set_border_width_all(bw)
	return s


func panel_style(bg := C_PANEL, border := C_BORDER) -> StyleBoxFlat:
	var s := _flat(Color(bg, 0.94), border, 3)
	s.set_content_margin_all(10)
	s.shadow_color = Color(0, 0, 0, 0.5)
	s.shadow_size = 4
	return s


func _btn_style(bg: Color, border := C_BORDER) -> StyleBoxFlat:
	var s := _flat(bg, border, 2)
	s.content_margin_left = 14
	s.content_margin_right = 14
	s.content_margin_top = 6
	s.content_margin_bottom = 6
	return s


func label(text: String, size := 18, color := C_TEXT) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_outline_color", Color.BLACK)
	l.add_theme_constant_override("outline_size", 4 if size >= 22 else 0)
	return l


func button(text: String, cb: Callable, size := 18) -> Button:
	var b := Button.new()
	b.text = text
	b.add_theme_font_size_override("font_size", size)
	b.pressed.connect(func():
		sfx("click")
		cb.call())
	return b


func bar(color: Color, w := 200.0, h := 14.0) -> ProgressBar:
	var p := ProgressBar.new()
	p.show_percentage = false
	p.custom_minimum_size = Vector2(w, h)
	p.add_theme_stylebox_override("fill", _flat(color))
	return p


func tex(path: String) -> Texture2D:
	return load(A + path)


func icon(path: String, size := 32.0) -> TextureRect:
	var r := TextureRect.new()
	r.texture = tex(path)
	r.custom_minimum_size = Vector2(size, size)
	r.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	r.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	return r


## Full-screen background: mosaic picture + silhouette strip + darkening.
func add_background(parent: Control, bg_path: String, sil_path := "", tint := Color(1, 1, 1)) -> void:
	var bg := TextureRect.new()
	bg.texture = tex(bg_path)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bg.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	bg.modulate = tint
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(bg)
	if sil_path != "":
		var sil := Sprite2D.new()
		sil.texture = tex(sil_path)
		sil.centered = false
		sil.scale = Vector2(3, 3)
		sil.position = Vector2(0, 400 - sil.texture.get_height() * 3)
		sil.modulate = Color(0, 0, 0, 0.75)
		parent.add_child(sil)


## Builds SpriteFrames for a hero/mini-monster sheet (rows idle/attack/hurt/die, 32px).
func mini_frames(sheet: String, counts: Array) -> SpriteFrames:
	var t := tex(sheet)
	var sf := SpriteFrames.new()
	sf.remove_animation("default")
	var names := ["idle", "attack", "hurt", "die"]
	var speeds := [4.0, 12.0, 8.0, 9.0]
	for row in names.size():
		var n: String = names[row]
		sf.add_animation(n)
		sf.set_animation_speed(n, speeds[row])
		sf.set_animation_loop(n, n == "idle")
		for i in int(counts[row]):
			var at := AtlasTexture.new()
			at.atlas = t
			at.region = Rect2(i * 32, row * 32, 32, 32)
			sf.add_frame(n, at)
	return sf


## Builds SpriteFrames for a 3-frame front-facing strip (big monsters / NPCs).
func strip_frames(sheet: String, fw: int, fh: int) -> SpriteFrames:
	var t := tex(sheet)
	var sf := SpriteFrames.new()
	sf.remove_animation("default")
	sf.add_animation("idle")
	sf.set_animation_speed("idle", 4.0)
	sf.set_animation_loop("idle", true)
	for i in [0, 1, 2, 1]:
		var at := AtlasTexture.new()
		at.atlas = t
		at.region = Rect2(i * fw, 0, fw, fh)
		sf.add_frame("idle", at)
	return sf


func hero_sprite(cls: String, sc := 4.0) -> AnimatedSprite2D:
	var c: Dictionary = CLASSES[cls]
	var s := AnimatedSprite2D.new()
	s.sprite_frames = mini_frames(c.sheet, c.counts)
	s.scale = Vector2(sc, sc)
	s.play("idle")
	return s


func npc_sprite(name: String, sc := 3.0) -> AnimatedSprite2D:
	var s := AnimatedSprite2D.new()
	s.sprite_frames = strip_frames("npcs/%s.png" % name, 26, 36)
	s.scale = Vector2(sc, sc)
	s.play("idle")
	return s


func enemy_sprite(id: String, sc_mul := 1.0) -> AnimatedSprite2D:
	var e: Dictionary = ENEMIES[id]
	var s := AnimatedSprite2D.new()
	if e.kind == "mini":
		s.sprite_frames = mini_frames(e.sheet, e.counts)
		s.flip_h = true
		s.scale = Vector2(4, 4) * sc_mul
	else:
		s.sprite_frames = strip_frames(e.sheet, e.fw, e.fh)
		s.scale = Vector2(e.scale, e.scale) * sc_mul
	s.play("idle")
	return s


## One-shot VFX from a horizontal strip.
func spawn_vfx(parent: Node, name: String, pos: Vector2, sc := 2.0) -> void:
	var sizes := {"hit": Vector2(58, 19), "explosion": Vector2(48, 48), "heal": Vector2(96, 96), "magic": Vector2(48, 48), "blood": Vector2(21, 21)}
	var sz: Vector2 = sizes[name]
	var t := tex("vfx/%s.png" % name)
	var sf := SpriteFrames.new()
	sf.set_animation_loop("default", false)
	sf.set_animation_speed("default", 18.0)
	for i in int(t.get_width() / sz.x):
		var at := AtlasTexture.new()
		at.atlas = t
		at.region = Rect2(i * sz.x, 0, sz.x, sz.y)
		sf.add_frame("default", at)
	var s := AnimatedSprite2D.new()
	s.sprite_frames = sf
	s.position = pos
	s.scale = Vector2(sc, sc)
	s.z_index = 10
	parent.add_child(s)
	s.play("default")
	s.animation_finished.connect(s.queue_free)


func float_text(parent: Node, text: String, pos: Vector2, color := Color.WHITE, size := 26) -> void:
	var l := label(text, size, color)
	l.add_theme_constant_override("outline_size", 6)
	l.position = pos - Vector2(30, 0)
	l.z_index = 20
	parent.add_child(l)
	var tw := l.create_tween()
	tw.tween_property(l, "position:y", pos.y - 60, 0.8).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(l, "modulate:a", 0.0, 0.8).set_delay(0.3)
	tw.tween_callback(l.queue_free)


func goto(scene: String) -> void:
	if Engine.is_editor_hint():
		return
	get_tree().change_scene_to_file("res://scenes/%s.tscn" % scene)


func wait(sec: float) -> void:
	await get_tree().create_timer(sec).timeout
