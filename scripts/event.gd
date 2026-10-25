@tool
extends Control
## Story / random event nodes: beggar, shrine, chest, campfire and graves of past lives.
## Beggar choices change the karma that the NEXT life is born with.
## Opened as an overlay from the stage; emits closed once the event is done.

signal closed

var _s: Dictionary
var _hud
var _title: Label
var _body: Label
var _opts: VBoxContainer
var _npc_holder: Node2D
var _done := false


func _ready() -> void:
	_s = Game.slot()
	var st: Dictionary = Game.STAGES[int(_s.stage)]
	Game.play_bgm("stage")
	Game.add_background(self, st.bg, st.sil, Color(0.7, 0.7, 0.75))
	_hud = preload("res://scripts/hud.gd").new()
	_hud.position = Vector2(10, 8)
	_hud.size = Vector2(940, 60)
	add_child(_hud)
	var hero := Game.hero_sprite(_s.cls, 4.0)
	hero.position = Vector2(110, 300)
	add_child(hero)
	_npc_holder = Node2D.new()
	_npc_holder.position = Vector2(240, 290)
	add_child(_npc_holder)

	var panel := PanelContainer.new()
	panel.position = Vector2(340, 90)
	panel.size = Vector2(600, 420)
	add_child(panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	panel.add_child(v)
	_title = Game.label("", 26, Color("f5d76e"))
	v.add_child(_title)
	_body = Game.label("", 17)
	_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_body.custom_minimum_size = Vector2(570, 150)
	v.add_child(_body)
	_opts = VBoxContainer.new()
	v.add_child(_opts)

	var kind := Game.current_node()
	if kind == "event":
		if _s.pending_event == "":
			var roll := randf()
			if int(_s.stage) == 0:
				_s.pending_event = "beggar" if roll < 0.6 else ("shrine" if roll < 0.8 else "chest")
			else:
				_s.pending_event = ["beggar", "shrine", "chest"][randi() % 3]
			Game.save_game()
		kind = _s.pending_event
	if Engine.is_editor_hint():
		kind = "beggar"
	call("_ev_" + kind)


func _opt(text: String, cb: Callable, enabled := true) -> void:
	var b := Game.button(text, cb, 17)
	b.disabled = not enabled
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	_opts.add_child(b)


func _finish(text: String, sound := "coin") -> void:
	Game.sfx(sound)
	Game.save_game()
	_hud.refresh()
	_body.text = text
	for c in _opts.get_children():
		c.queue_free()
	_opt("ไปต่อ ▶", func():
		# Guard against double clicks advancing the route twice.
		if _done:
			return
		_done = true
		Game.mark_visited()
		closed.emit())


## The beggar shares what little food and water he has with those who help him.
func _gift() -> void:
	_give("fruit")
	_give("water")


## Puts an item in the bag; a full bag gets 10G instead.
func _give(id: String) -> void:
	if not Game.add_item(id):
		_s.gold = int(_s.gold) + 10


func _karma(delta: int) -> void:
	Game.data.karma = clampi(int(Game.data.karma) + delta, -3, 3)
	_s.deeds.append("good" if delta > 0 else "evil")


func _npc(name: String) -> void:
	_npc_holder.add_child(Game.npc_sprite(name, 4.0))


func _prop(icon: String) -> void:
	var r := Sprite2D.new()
	r.texture = Game.tex(icon)
	r.scale = Vector2(5, 5)
	r.position = Vector2(0, 30)
	_npc_holder.add_child(r)


# ---------------------------------------------------------------- events
func _ev_beggar() -> void:
	_npc("beggar")
	_title.text = "ขอทานริมทาง"
	_body.text = "ชายชราในผ้าคลุมยื่นมือสั่นเทามาหาคุณ \"เมตตาด้วยเถิดท่านผู้กล้า...\"\nใต้ผ้าคลุมมีถุงเงินและขวดยาซ่อนอยู่\n\n(การตัดสินใจนี้จะส่งผลต่อชีวิตถัดไปของคุณในเซฟอื่น)"
	_opt("ให้เงิน 15G  (กรรมดี)", func():
		_s.gold = int(_s.gold) - 15
		_gift()
		_karma(1)
		_finish("ขอทานยิ้มทั้งน้ำตา \"ขอให้ชาติหน้าท่านพบแต่สิ่งดีงาม\"\n\nกรรมดี +1 · ชีวิตถัดไปจะเกิดมาพร้อมเงินและยามากขึ้น\nขอทานแบ่งเสบียงให้: ผลไม้ป่า 1 และกระติกน้ำ 1", "heal"), int(_s.gold) >= 15)
	_opt("แบ่งยาให้ 1 ขวด  (กรรมดี)", func():
		Game.remove_item("potion")
		_gift()
		_karma(1)
		_finish("ขอทานดื่มยาแล้วลุกขึ้นยืนได้ \"บุญคุณนี้ข้าจะจำไปทุกชาติ\"\n\nกรรมดี +1 · ชีวิตถัดไปจะเกิดมาพร้อมเงินและยามากขึ้น\nขอทานแบ่งเสบียงให้: ผลไม้ป่า 1 และกระติกน้ำ 1", "heal"), Game.item_count("potion") > 0)
	_opt("เดินผ่านไป", func(): _finish("คุณเดินผ่านไปเงียบๆ ไม่มีอะไรเปลี่ยนแปลง", "click"))
	_opt("เชือดเอาของ  (กรรมชั่ว)", func():
		_s.gold = int(_s.gold) + 40
		_give("potion")
		_give("fruit")
		_give("water")
		_karma(-1)
		Game.spawn_vfx(self, "blood", Vector2(240, 290), 4.0)
		for c in _npc_holder.get_children():
			c.modulate = Color(0.4, 0.1, 0.1, 0.6)
		_finish("คุณได้เงิน 40G ยา 1 ขวด ผลไม้ป่า 1 และกระติกน้ำ 1...\nเสียงหัวเราะแผ่วเบาดังมาจากทางเหนือ \"เจ้าก็เหมือนข้านั่นแหละ\"\n\nกรรมชั่ว -1 · ชีวิตถัดไปจะเจอมอนสเตอร์มากขึ้น ได้ XP เยอะแต่เงินน้อยลง", "bad"))


func _ev_shrine() -> void:
	_prop("icons/crown.png")
	_title.text = "แท่นบูชาเทพีที่ถูกลืม"
	_body.text = "แท่นหินเก่าแก่ส่องแสงจางๆ มีจารึกว่า \"ผู้ที่เกิดซ้ำ จงสวดเพื่อลืม\""
	_opt("สวดภาวนา", func():
		if randf() < 0.65:
			_s.hp = int(_s.max_hp)
			_s.mp = int(_s.max_mp)
			Game.spawn_vfx(self, "heal", Vector2(110, 300), 1.6)
			_finish("แสงอุ่นโอบล้อมตัวคุณ HP และ MP ฟื้นเต็ม", "heal")
		else:
			_s.hp = maxi(1, int(_s.hp) - roundi(_s.max_hp * 0.15))
			_s.atk = int(_s.atk) + 2
			Game.spawn_vfx(self, "magic", Vector2(110, 300), 3.0)
			_finish("แสงกลายเป็นสีม่วงหม่น... HP ลด 15% แต่พลังมืดทำให้ ATK +2", "bad"))
	_opt("จากไป", func(): _finish("คุณไม่ไว้ใจเทพที่ถูกลืม จึงเดินจากมา", "click"))


func _ev_chest() -> void:
	var chest := Sprite2D.new()
	chest.texture = Game.tex("icons/key.png")
	chest.scale = Vector2(4, 4)
	_npc_holder.add_child(chest)
	_title.text = "หีบสมบัติกลางทาง"
	_body.text = "หีบไม้เก่าวางอยู่กลางทาง ดูเหมือนรอให้ใครสักคนมาเปิด"
	_opt("เปิดหีบ", func():
		if randf() < 0.7:
			var g := randi_range(30, 60)
			_s.gold = int(_s.gold) + g
			_give("ether")
			_finish("ข้างในมีเงิน %dG และอีเธอร์ 1 ขวด!" % g)
		else:
			var d := roundi(_s.max_hp * 0.2)
			_s.hp = maxi(1, int(_s.hp) - d)
			Game.spawn_vfx(self, "explosion", Vector2(240, 290), 3.0)
			_finish("กับดัก! หีบระเบิด เสีย HP %d" % d, "explosion"))
	_opt("ไม่เปิด", func(): _finish("คุณปล่อยหีบไว้อย่างนั้น", "click"))


func _ev_rest() -> void:
	_prop("icons/heart.png")
	_title.text = "กองไฟหน้าปราสาท"
	_body.text = "คืนสุดท้ายก่อนบุกปราสาท คุณหลับไปข้างกองไฟ...\nในฝัน คุณเห็นตัวเองนั่งบนบัลลังก์มืด สวมมงกุฎของจอมมาร"
	_opt("พักผ่อน (ฟื้น HP/MP เต็ม)", func():
		_s.hp = int(_s.max_hp)
		_s.mp = int(_s.max_mp)
		Game.spawn_vfx(self, "heal", Vector2(110, 300), 1.6)
		_finish("คุณตื่นขึ้นพร้อมพลังเต็มเปี่ยม แต่ความฝันนั้นยังติดตา...", "heal"))


func _ev_grave() -> void:
	var g: Dictionary = {}
	for x in Game.data.graves:
		if int(x.stage) == int(_s.stage):
			g = x
			break
	if g.is_empty():
		_finish("ที่นี่ว่างเปล่า", "click")
		return
	var spr := Game.hero_sprite(g.cls, 4.0)
	spr.play("die")
	spr.frame = spr.sprite_frames.get_frame_count("die") - 1
	spr.pause()
	spr.modulate = Color(0.5, 0.6, 0.8, 0.7)
	_npc_holder.add_child(spr)
	_title.text = "หลุมศพของชีวิตที่ %d" % g.life
	_body.text = "ร่างไร้วิญญาณของ%s นอนอยู่ตรงนี้... ใบหน้านั้นคือใบหน้าของคุณเอง\nชีวิตก่อนของคุณตายที่นี่ และทิ้งของไว้ให้" % Game.CLASSES[g.cls].name
	_opt("เก็บของที่ระลึก (เงิน %dG, ATK +%d)" % [g.gold, g.atk], func():
		_s.gold = int(_s.gold) + int(g.gold)
		_s.atk = int(_s.atk) + int(g.atk)
		Game.data.graves.erase(g)
		_finish("คุณรับอาวุธและเงินของตัวเองในชาติก่อนมา ความแค้นของมันไหลเข้าสู่ตัวคุณ"))
	_opt("สวดส่งวิญญาณ (ฟื้น HP 40%, กรรมดี)", func():
		_s.hp = mini(int(_s.max_hp), int(_s.hp) + roundi(_s.max_hp * 0.4))
		_karma(1)
		Game.data.graves.erase(g)
		_finish("วิญญาณยิ้มให้แล้วสลายไปเป็นแสง กรรมดี +1", "heal"))
