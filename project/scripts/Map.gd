extends Node2D
## Mapa del mundo de Age of Nations.
##
## Mapa plano equirectangular con relieve (SRTM), paises coloreados y fronteras.
## Arrastrar para mover, pellizcar/rueda para zoom, tocar un pais para verlo.

const META_PATH := "res://game/data/world_meta.json"
const PROVINCES_PATH := "res://game/data/world_provinces.json"
const TERRAIN_PATH := "user://world_terrain.png"
const RELIEF_URL := "https://github.com/diegodiego999diego-crypto/Age-Of-Nations/releases/download/relief-v1/world_terrain.png"
const TERRAIN_PX := Vector2(2048, 1024)
const RELIEF_ALPHA := 0.72

const MIN_ZOOM := 0.4
const MAX_ZOOM := 8.0
const ZOOM_STEP := 1.18
const PAN_SPEED := 700.0
const TAP_MAX_DRAG := 14.0

var world_size := Vector2(512.0, 256.0)
var countries: Array = []
var country_polys: Array = []

var camera: Camera2D
var hud_info: Label
var info_panel: PanelContainer
var info_label: Label

var dragging := false
var drag_start_mouse := Vector2.ZERO
var drag_start_cam := Vector2.ZERO
var dragged_total := 0.0
var selected_country := -1


func _ready() -> void:
	print("Map scene loaded. Age of Nations begins.")
	_load_meta()
	_load_provinces()
	_build_camera()
	_build_world()
	_build_hud()


func _load_meta() -> void:
	if not FileAccess.file_exists(META_PATH):
		push_warning("Falta %s" % META_PATH)
		return
	var data = JSON.parse_string(FileAccess.get_file_as_string(META_PATH))
	if typeof(data) == TYPE_DICTIONARY and data.has("world_width"):
		world_size = Vector2(float(data["world_width"]), float(data["world_height"]))


func _load_provinces() -> void:
	if not FileAccess.file_exists(PROVINCES_PATH):
		push_warning("Falta %s" % PROVINCES_PATH)
		return
	var data = JSON.parse_string(FileAccess.get_file_as_string(PROVINCES_PATH))
	if typeof(data) != TYPE_DICTIONARY:
		return
	countries = data.get("countries", [])
	for c in countries:
		var polys: Array = []
		for poly in c.get("polygons", []):
			for ring in poly:
				var pts := PackedVector2Array()
				var i := 0
				while i + 1 < ring.size():
					pts.append(Vector2(float(ring[i]), float(ring[i + 1])))
					i += 2
				if pts.size() >= 3:
					polys.append(pts)
		country_polys.append(polys)
	print("Paises cargados: %d" % countries.size())


func _build_camera() -> void:
	camera = Camera2D.new()
	camera.name = "Camera2D"
	camera.position = world_size * 0.5
	camera.zoom = Vector2(0.6, 0.6)
	camera.limit_left = 0
	camera.limit_top = 0
	camera.limit_right = int(world_size.x)
	camera.limit_bottom = int(world_size.y)
	add_child(camera)
	camera.make_current()


func _build_world() -> void:
	var bg := ColorRect.new()
	bg.name = "Ocean"
	bg.color = Color(0.06, 0.11, 0.2)
	bg.position = -Vector2(400, 300)
	bg.size = world_size + Vector2(800, 600)
	bg.z_index = -10
	add_child(bg)

	_build_polygon_map()
	terrain_sprite = Sprite2D.new()
	terrain_sprite.name = "Terrain"
	terrain_sprite.centered = false
	terrain_sprite.position = Vector2.ZERO
	terrain_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	terrain_sprite.modulate = Color(1, 1, 1, RELIEF_ALPHA)
	terrain_sprite.z_index = -5
	terrain_sprite.scale = Vector2(world_size.x / TERRAIN_PX.x, world_size.y / TERRAIN_PX.y)
	terrain_sprite.visible = false
	add_child(terrain_sprite)
	_load_cached_terrain()
	if terrain_sprite.texture == null:
		_download_terrain()


var terrain_sprite: Sprite2D = null
var downloading := false
var download_status: Label = null


## Carga el relieve ya cacheado en el almacenamiento de la app (si existe).
func _load_cached_terrain() -> void:
	if not FileAccess.file_exists(TERRAIN_PATH):
		return
	var img := Image.new()
	if img.load(TERRAIN_PATH) != OK:
		return
	terrain_sprite.texture = ImageTexture.create_from_image(img)
	terrain_sprite.visible = true


## Descarga el relieve desde GitHub Releases la primera vez (sin empaquetarlo en el APK).
func _download_terrain() -> void:
	if downloading:
		return
	downloading = true
	if download_status:
		download_status.text = "Descargando relieve del mundo..."
	var http := HTTPRequest.new()
	http.timeout = 300.0
	add_child(http)
	http.request_completed.connect(_on_terrain_downloaded.bind(http))
	var err := http.request(RELIEF_URL)
	if err != OK:
		push_warning("No se pudo iniciar la descarga del relieve: %d" % err)
		downloading = false


func _on_terrain_downloaded(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray, http: HTTPRequest) -> void:
	downloading = false
	http.queue_free()
	if result != HTTPRequest.RESULT_SUCCESS or code != 200:
		push_warning("Descarga del relieve fallida (result %d, http %d); se juega con el mapa de paises" % [result, code])
		if download_status:
			download_status.text = "Sin relieve (offline)"
		return
	var img := Image.new()
	if img.load_png_from_buffer(body) != OK:
		push_warning("Imagen de relieve corrupta")
		return
	img.save_png(TERRAIN_PATH)
	terrain_sprite.texture = ImageTexture.create_from_image(img)
	terrain_sprite.visible = true
	if download_status:
		download_status.text = ""
	print("Relieve del mundo cargado (%d KB)" % (body.size() / 1024))


func _build_polygon_map() -> void:
	for idx in country_polys.size():
		var c: Dictionary = countries[idx]
		var col: Array = c.get("color", [150, 150, 150])
		for ring in country_polys[idx]:
			var poly := Polygon2D.new()
			poly.polygon = ring
			poly.color = Color8(int(col[0]), int(col[1]), int(col[2]))
			add_child(poly)


func _build_hud() -> void:
	var layer := CanvasLayer.new()
	layer.name = "HUD"
	add_child(layer)

	var top := PanelContainer.new()
	top.position = Vector2(12, 12)
	layer.add_child(top)
	var vb := VBoxContainer.new()
	top.add_child(vb)
	var title := Label.new()
	title.text = "AGE OF NATIONS"
	title.add_theme_font_size_override("font_size", 22)
	vb.add_child(title)
	hud_info = Label.new()
	hud_info.add_theme_font_size_override("font_size", 13)
	hud_info.text = "%d paises" % countries.size()
	vb.add_child(hud_info)

	download_status = Label.new()
	download_status.add_theme_font_size_override("font_size", 12)
	download_status.modulate = Color(1, 0.9, 0.6, 0.9)
	download_status.position = Vector2(12, 86)
	layer.add_child(download_status)

	info_panel = PanelContainer.new()
	info_panel.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	info_panel.anchor_left = 1.0
	info_panel.anchor_right = 1.0
	info_panel.offset_left = -260
	info_panel.offset_right = -12
	info_panel.offset_top = 12
	info_panel.visible = false
	layer.add_child(info_panel)
	info_label = Label.new()
	info_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info_panel.add_child(info_label)

	var back := Button.new()
	back.text = "Menu"
	back.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	back.anchor_left = 1.0
	back.anchor_top = 1.0
	back.anchor_right = 1.0
	back.anchor_bottom = 1.0
	back.offset_left = -110
	back.offset_right = -12
	back.offset_top = -62
	back.offset_bottom = -12
	back.pressed.connect(_on_back_pressed)
	layer.add_child(back)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		_on_mouse_button(event)
	elif event is InputEventMouseMotion:
		_on_mouse_motion(event)
	elif event is InputEventScreenTouch:
		_on_touch(event)
	elif event is InputEventScreenDrag:
		_on_drag(event)
	elif event is InputEventMagnifyGesture:
		_zoom_at(event.position, event.factor)
	elif event is InputEventPanGesture:
		camera.position -= event.delta * 12.0 / camera.zoom.x


func _on_mouse_button(e: InputEventMouseButton) -> void:
	if e.button_index == MOUSE_BUTTON_LEFT:
		if e.pressed:
			dragging = true
			dragged_total = 0.0
			drag_start_mouse = e.position
			drag_start_cam = camera.position
		else:
			if dragging and dragged_total < TAP_MAX_DRAG:
				_pick(e.position)
			dragging = false
	elif e.pressed and e.button_index == MOUSE_BUTTON_WHEEL_UP:
		_zoom_at(e.position, ZOOM_STEP)
	elif e.pressed and e.button_index == MOUSE_BUTTON_WHEEL_DOWN:
		_zoom_at(e.position, 1.0 / ZOOM_STEP)


func _on_mouse_motion(e: InputEventMouseMotion) -> void:
	if not dragging:
		return
	dragged_total += e.relative.length()
	camera.position = drag_start_cam - (e.position - drag_start_mouse) / camera.zoom.x


func _on_touch(e: InputEventScreenTouch) -> void:
	if e.pressed:
		dragging = true
		dragged_total = 0.0
		drag_start_mouse = e.position
		drag_start_cam = camera.position
	else:
		if dragged_total < TAP_MAX_DRAG:
			_pick(e.position)
		dragging = false


func _on_drag(e: InputEventScreenDrag) -> void:
	if not dragging:
		return
	dragged_total += e.relative.length()
	camera.position = drag_start_cam - (e.position - drag_start_mouse) / camera.zoom.x


func _process(delta: float) -> void:
	var move := Vector2.ZERO
	if Input.is_key_pressed(KEY_LEFT) or Input.is_action_pressed("ui_left"):
		move.x -= 1
	if Input.is_key_pressed(KEY_RIGHT) or Input.is_action_pressed("ui_right"):
		move.x += 1
	if Input.is_key_pressed(KEY_UP) or Input.is_action_pressed("ui_up"):
		move.y -= 1
	if Input.is_key_pressed(KEY_DOWN) or Input.is_action_pressed("ui_down"):
		move.y += 1
	if move != Vector2.ZERO:
		camera.position += move.normalized() * PAN_SPEED * delta / camera.zoom.x


func _zoom_at(_screen_pos: Vector2, factor: float) -> void:
	var before := camera.get_global_mouse_position()
	var z := clampf(camera.zoom.x * factor, MIN_ZOOM, MAX_ZOOM)
	camera.zoom = Vector2(z, z)
	var after := camera.get_global_mouse_position()
	camera.position += before - after
	_update_info()


func _pick(screen_pos: Vector2) -> void:
	var world_pos := camera.get_canvas_transform().affine_inverse() * screen_pos
	var hit := -1
	for i in country_polys.size():
		for ring in country_polys[i]:
			if Geometry2D.is_point_in_polygon(world_pos, ring):
				hit = i
				break
		if hit >= 0:
			break
	selected_country = hit
	if hit >= 0:
		var c: Dictionary = countries[hit]
		var col: Array = c.get("color", [220, 220, 220])
		var iso := String(c.get("iso_a3", ""))
		info_label.text = "%s %s\n%s" % [
			String(c.get("name", "?")),
			"" if iso == "" or iso == "-99" else "(" + iso + ")",
			String(c.get("continent", "")),
		]
		info_label.add_theme_color_override("font_color", Color8(int(col[0]), int(col[1]), int(col[2])))
		info_panel.visible = true
	else:
		info_panel.visible = false
	_update_info()


func _update_info() -> void:
	if hud_info == null:
		return
	var sel := ""
	if selected_country >= 0 and selected_country < countries.size():
		sel = String(countries[selected_country].get("name", "")) + "  |  "
	hud_info.text = "%s%d paises  |  zoom %.2fx" % [sel, countries.size(), camera.zoom.x]


func _on_back_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/MainMenu.tscn")
