extends RefCounted

const INK := Color("#234956")
const MUTED := Color("#627e88")
const TEAL := Color("#256b78")
const GOLD := Color("#edc982")
const PAPER := Color("#f5fafb")

static func panel(fill := PAPER, radius := 16, margin := 18) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = fill
	style.set_corner_radius_all(radius)
	style.set_border_width_all(1)
	style.border_color = Color("#cbdde1")
	style.shadow_color = Color(0.03, 0.13, 0.18, 0.12)
	style.shadow_size = 6
	style.shadow_offset = Vector2(0, 3)
	for side in [SIDE_LEFT, SIDE_TOP, SIDE_RIGHT, SIDE_BOTTOM]:
		style.set_content_margin(side, margin)
	return style

static func make_theme() -> Theme:
	var result := Theme.new()
	result.default_font_size = 20
	for type in ["Label", "Button", "OptionButton", "CheckButton", "CheckBox", "LineEdit", "RichTextLabel"]:
		result.set_color("font_color", type, INK)
		result.set_color("font_hover_color", type, INK)
		result.set_color("font_pressed_color", type, INK)
		result.set_color("font_focus_color", type, INK)
		result.set_color("font_disabled_color", type, MUTED)
	for type in ["Button", "OptionButton", "LineEdit"]:
		result.set_stylebox("normal", type, panel(Color("#f6fbfc"), 12, 14))
		result.set_stylebox("hover", type, panel(Color("#e2f1f4"), 12, 14))
		var selected := panel(Color("#fff2d5"), 12, 14)
		selected.border_color = GOLD
		result.set_stylebox("pressed", type, selected)
		result.set_stylebox("disabled", type, panel(Color("#e8eef0"), 12, 14))
		var focus := panel(Color(0, 0, 0, 0), 12, 14)
		focus.border_color = TEAL
		focus.set_border_width_all(3)
		focus.shadow_size = 0
		result.set_stylebox("focus", type, focus)
	result.set_color("font_placeholder_color", "LineEdit", MUTED)
	result.set_stylebox("panel", "PanelContainer", panel())
	result.set_stylebox("panel", "PopupMenu", panel())
	result.set_stylebox("hover", "PopupMenu", panel(Color("#e2f1f4"), 8, 8))
	result.set_color("font_color", "PopupMenu", INK)
	result.set_color("font_hover_color", "PopupMenu", INK)
	result.set_stylebox("panel", "TooltipPanel", panel(Color("#f5fafb"), 10, 12))
	result.set_color("font_color", "TooltipLabel", INK)
	result.set_font_size("font_size", "TooltipLabel", 18)
	return result

static func primary(button: Button) -> void:
	for state in ["normal", "hover", "pressed", "focus"]:
		var fill := TEAL if state == "normal" else Color("#347f8c")
		var style := panel(fill, 12, 16)
		style.border_color = GOLD if state == "focus" else fill
		button.add_theme_stylebox_override(state, style)
		button.add_theme_color_override("font_%s_color" % state, Color.WHITE)
	button.add_theme_color_override("font_color", Color.WHITE)

static func label(text: String, pixels := 20, color := INK) -> Label:
	var result := Label.new()
	result.text = text
	result.add_theme_font_size_override("font_size", pixels)
	result.add_theme_color_override("font_color", color)
	return result

# Chamfered enamel plates, compass engraving and rank marks remain crisp at any size.
static func cover_button(button: Button, hero := false) -> void:
	var naval_style = preload("res://scripts/presentation/naval_button_style.gd")
	for state in ["normal", "hover", "pressed", "disabled", "focus"]:
		var active: bool = state in ["hover", "pressed", "focus"]
		var style = naval_style.new()
		style.hero = hero
		style.focus_only = state == "focus"
		style.fill = Color("#285967") if active else Color("#173c4b")
		style.fill.a = 0.96 if active else 0.88
		style.edge = Color("#f3d99b") if active else Color("#bcae83")
		style.content_margin_left = 62 if hero else 18
		style.content_margin_right = 62 if hero else 18
		style.content_margin_top = 14
		style.content_margin_bottom = 14
		button.add_theme_stylebox_override(state, style)
	for key in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		button.add_theme_color_override(key, Color("#fff4db"))
	# Compact controls retain the vector treatment; illustrated caps need label space.
	if hero or button.custom_minimum_size.x >= 180:
		menu_button(button, "primary" if hero else "secondary")

static func menu_button(button: Button, family := "primary") -> void:
	var loop := Engine.get_main_loop() as SceneTree
	if loop == null:
		return
	var registry := loop.root.get_node_or_null("DataRegistry")
	if registry == null:
		return
	var states := {"normal": "primary_normal", "hover": "primary_hover", "pressed": "primary_pressed", "hover_pressed": "primary_pressed", "disabled": "disabled"}
	if family == "secondary":
		states.merge({"normal": "secondary_normal", "hover": "primary_hover", "pressed": "secondary_selected", "hover_pressed": "secondary_selected"}, true)
	elif family == "light":
		states.merge({"normal": "light_normal", "hover": "light_hover", "pressed": "secondary_selected", "hover_pressed": "secondary_selected"}, true)
	# Resolve all resources before overriding anything, preserving the complete fallback.
	var textures := {}
	for state in states:
		var path: String = registry.assets.ui_asset_path("ui.button.naval_" + states[state])
		if path.is_empty() or not ResourceLoader.exists(path):
			return
		var texture := load(path) as Texture2D
		if texture == null:
			return
		textures[state] = texture
	for state in textures:
		var style = preload("res://scripts/presentation/menu_button_texture_style.gd").new()
		style.texture = textures[state]
		style.content_margin_left = 68 if family == "primary" else 48
		style.content_margin_right = style.content_margin_left
		style.content_margin_top = 12
		style.content_margin_bottom = 12
		button.add_theme_stylebox_override(state, style)
	# Focus is a transparent overlay, never an opaque atlas plaque over the current state.
	var focus := panel(Color.TRANSPARENT, 12, 0)
	focus.border_color = Color("#8dd9e8")
	focus.set_border_width_all(2)
	focus.shadow_size = 0
	button.add_theme_stylebox_override("focus", focus)
	for key in ["font_color", "font_hover_color", "font_pressed_color", "font_hover_pressed_color", "font_focus_color"]:
		button.add_theme_color_override(key, INK if family == "light" else Color("#fff4db"))
	if family == "light":
		button.add_theme_color_override("font_pressed_color", Color("#fff4db"))
		button.add_theme_color_override("font_hover_pressed_color", Color("#fff4db"))
	button.add_theme_color_override("font_disabled_color", Color("#eef2f5"))
