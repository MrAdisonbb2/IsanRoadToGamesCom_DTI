@tool
extends PanelContainer
## Top bar with the current life's stats and the shared boss HP.

var _info: Label
var _hp: ProgressBar
var _mp: ProgressBar
var _hp_l: Label
var _mp_l: Label
var _items: Label
var _food: ProgressBar
var _water: ProgressBar
var _boss: ProgressBar
var _boss_l: Label


func _ready() -> void:
	add_theme_stylebox_override("panel", Game.panel_style())
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	add_child(row)
	var s := Game.slot()
	var face := Control.new()
	face.custom_minimum_size = Vector2(40, 40)
	var spr := Game.hero_sprite(s.cls, 1.6)
	spr.position = Vector2(20, 18)
	face.add_child(spr)
	row.add_child(face)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 2)
	row.add_child(col)
	_info = Game.label("", 16)
	col.add_child(_info)
	_items = Game.label("", 14, Game.C_DIM)
	col.add_child(_items)
	var bars := VBoxContainer.new()
	bars.add_theme_constant_override("separation", 2)
	row.add_child(bars)
	var h1 := HBoxContainer.new()
	_hp = Game.bar(Game.C_HP, 120, 14)
	_hp_l = Game.label("", 14)
	h1.add_child(Game.label("HP", 14))
	h1.add_child(_hp)
	h1.add_child(_hp_l)
	bars.add_child(h1)
	var h2 := HBoxContainer.new()
	_mp = Game.bar(Game.C_MP, 120, 14)
	_mp_l = Game.label("", 14)
	h2.add_child(Game.label("MP", 14))
	h2.add_child(_mp)
	h2.add_child(_mp_l)
	bars.add_child(h2)
	# Survival bars: food (orange) and water (light blue).
	var needs := VBoxContainer.new()
	needs.add_theme_constant_override("separation", 2)
	row.add_child(needs)
	var h3 := HBoxContainer.new()
	_food = Game.bar(Color("e08a2c"), 80, 12)
	_food.max_value = 100
	h3.add_child(Game.label("อาหาร", 13, Color("ffb347")))
	h3.add_child(_food)
	needs.add_child(h3)
	var h4 := HBoxContainer.new()
	_water = Game.bar(Color("5ec8f2"), 80, 12)
	_water.max_value = 100
	h4.add_child(Game.label("น้ำ", 13, Color("7fd4ff")))
	h4.add_child(_water)
	needs.add_child(h4)
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(sp)
	var bcol := VBoxContainer.new()
	bcol.add_theme_constant_override("separation", 2)
	row.add_child(bcol)
	_boss_l = Game.label("", 14, Color("d9a0ff"))
	bcol.add_child(_boss_l)
	_boss = Game.bar(Color("9b3fd1"), 160, 12)
	bcol.add_child(_boss)
	refresh()


func refresh() -> void:
	var s := Game.slot()
	var c: Dictionary = Game.CLASSES[s.cls]
	_info.text = "ชีวิตที่ %d · %s Lv%d   ATK %d  DEF %d" % [s.life, c.name, s.lv, s.atk, s.def]
	var sin := int(s.get("sin", 0))
	if sin > 0:
		_info.text += "   ตราบาป x%d" % sin
	_info.add_theme_color_override("font_color", Color("ff9ad5") if sin > 0 else Game.C_TEXT)
	_items.text = "เงิน %dG · ยา %d · อีเธอร์ %d · XP %d/%d" % [s.gold, int(Game.bag(s).get("potion", 0)), int(Game.bag(s).get("ether", 0)), s.xp, Game.xp_to_next(int(s.lv))]
	_food.value = float(s.get("food", 100.0))
	_water.value = float(s.get("water", 100.0))
	_hp.max_value = s.max_hp
	_hp.value = s.hp
	_hp_l.text = "%d/%d" % [s.hp, s.max_hp]
	_mp.max_value = s.max_mp
	_mp.value = s.mp
	_mp_l.text = "%d/%d" % [s.mp, s.max_mp]
	_boss.max_value = Game.BOSS_MAX_HP
	_boss.value = Game.data.boss_hp
	_boss_l.text = "%s เฟส %d/3 · %d%% (ร่วมทุกชีวิต)" % [Game.boss_title(), Game.boss_phase(), roundi(float(Game.data.boss_hp) / Game.BOSS_MAX_HP * 100)]
