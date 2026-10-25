@tool
extends Control
## Wandering merchant. Prices rise a little per stage.
## Opened as an overlay from the stage; emits closed when the player leaves.

signal closed

const ITEMS := [
	{"id": "bread", "name": "ขนมปัง", "desc": "ใส่กระเป๋า · อาหาร +45", "icon": "items/bread.png", "price": 10, "bag": true},
	{"id": "water", "name": "กระติกน้ำ", "desc": "ใส่กระเป๋า · น้ำ +40", "icon": "icons/water.png", "price": 6, "bag": true},
	{"id": "potion", "name": "ยา HP", "desc": "ใส่กระเป๋า · ฟื้น HP 50%", "icon": "icons/potion.png", "price": 20, "bag": true},
	{"id": "ether", "name": "อีเธอร์", "desc": "ฟื้น MP จนเต็ม", "icon": "icons/ether.png", "price": 18, "bag": true},
	{"id": "sword", "name": "ลับคมอาวุธ", "desc": "ATK +4 ถาวร", "icon": "icons/sword.png", "price": 55},
	{"id": "armor", "name": "เสริมเกราะ", "desc": "DEF +3 ถาวร", "icon": "icons/armor.png", "price": 45},
	{"id": "heart", "name": "ผลไม้แห่งชีวิต", "desc": "HP สูงสุด +20 และฟื้น HP เต็ม", "icon": "icons/heart.png", "price": 50},
]

var _hud
var _msg: Label
var _buttons: Array = []


func _ready() -> void:
	var s := Game.slot()
	var st: Dictionary = Game.STAGES[int(s.stage)]
	Game.play_bgm("title")
	Game.add_background(self, st.bg, st.sil, Color(0.6, 0.55, 0.5))
	_hud = preload("res://scripts/hud.gd").new()
	_hud.position = Vector2(10, 8)
	_hud.size = Vector2(940, 60)
	add_child(_hud)
	var merchant := Game.npc_sprite("merchant", 4.0)
	merchant.position = Vector2(150, 260)
	add_child(merchant)
	var say := PanelContainer.new()
	say.position = Vector2(40, 360)
	say.size = Vector2(250, 90)
	add_child(say)
	_msg = Game.label("พ่อค้า: \"เจ้าดูคุ้นหน้าจัง... เหมือนเคยมาซื้อของเมื่อชาติก่อน\"", 15)
	_msg.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_msg.custom_minimum_size = Vector2(230, 0)
	say.add_child(_msg)

	var panel := PanelContainer.new()
	panel.position = Vector2(320, 90)
	panel.size = Vector2(620, 380)
	add_child(panel)
	var v := VBoxContainer.new()
	panel.add_child(v)
	v.add_child(Game.label("ร้านค้าพเนจร", 24, Color("f5d76e")))
	for it in ITEMS:
		var row := HBoxContainer.new()
		row.add_child(Game.icon(it.icon, 40))
		var col := VBoxContainer.new()
		col.add_theme_constant_override("separation", 0)
		col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		col.add_child(Game.label(it.name, 18))
		col.add_child(Game.label(it.desc, 14, Game.C_DIM))
		row.add_child(col)
		var price := _price(it)
		var b := Game.button("%d G" % price, func(): _buy(it), 16)
		b.custom_minimum_size = Vector2(100, 0)
		b.set_meta("price", price)
		row.add_child(b)
		_buttons.append(b)
		v.add_child(row)
	var leave := Game.button("ออกจากร้าน ▶", func(): closed.emit(), 18)
	leave.position = Vector2(780, 484)
	add_child(leave)
	_refresh()


func _price(it: Dictionary) -> int:
	# The mark of sin: the merchant charges a sinner 50% more.
	var sin_k := 1.5 if int(Game.slot().get("sin", 0)) > 0 else 1.0
	return roundi(it.price * (1.0 + 0.25 * int(Game.slot().stage)) * sin_k)


func _buy(it: Dictionary) -> void:
	var s := Game.slot()
	var p := _price(it)
	if int(s.gold) < p:
		Game.sfx("bad")
		_msg.text = "พ่อค้า: \"เงินไม่พอหรอกพ่อหนุ่ม\""
		return
	if it.get("bag", false):
		if not Game.add_item(it.id):
			Game.sfx("bad")
			_msg.text = "พ่อค้า: \"กระเป๋าเจ้าเต็มแล้วนะ\""
			return
		s.gold = int(s.gold) - p
		Game.sfx("coin")
		_msg.text = "พ่อค้า: \"ขอบใจ! ใช้ให้คุ้มล่ะ\""
		Game.save_game()
		_refresh()
		return
	s.gold = int(s.gold) - p
	match it.id:
		"sword":
			s.atk = int(s.atk) + 4
		"armor":
			s.def = int(s.def) + 3
		"heart":
			s.max_hp = int(s.max_hp) + 20
			s.hp = int(s.max_hp)
	Game.sfx("coin")
	_msg.text = "พ่อค้า: \"ขอบใจ! ใช้ให้คุ้มล่ะ\""
	Game.save_game()
	_refresh()


func _refresh() -> void:
	_hud.refresh()
	for b in _buttons:
		b.disabled = int(Game.slot().gold) < int(b.get_meta("price"))
