@tool
extends VBoxContainer

var editor_interface: EditorInterface
var status_label: Label
var semantic_selector: OptionButton


func _ready() -> void:
	name = "地形制作"
	var title := Label.new()
	title.text = "场景战斗地形"
	title.add_theme_font_size_override("font_size", 20)
	add_child(title)
	var hint := Label.new()
	hint.text = "先在 TerrainAuthoringRoot 的 Inspector 选择 Template/Map 和稳定 ID。\n加载后用 Godot 2D 顶点工具编辑；参数、依赖和公开趋势保存在节点 metadata。"
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(hint)
	_add_button("从正式数据加载", _load_authoring)
	_add_button("保存并回写正式数据", _save_authoring)
	add_child(HSeparator.new())
	semantic_selector = OptionButton.new()
	for semantic in ["HardLand", "SightBlocker", "ShallowWater", "ReefOrSandbar", "NavigationChannel", "VisualOnly", "EnvironmentZone", "Minefield", "SafeChannel"]:
		semantic_selector.add_item(semantic)
	add_child(semantic_selector)
	_add_button("新增所选多边形", _add_polygon)
	_add_button("摆放当前岛屿母版", _add_land_instance)
	_add_button("新增设施挂点", _add_anchor)
	_add_button("新增设施布局节点", _add_facility)
	add_child(HSeparator.new())
	for label in ["烘焙世界坐标", "校验几何与可达性", "生成共享导航", "生成小地图", "生成 QA 总览", "运行完整流水线"]:
		_add_button(label, _run_action.bind(label))
	status_label = Label.new()
	status_label.text = "等待操作"
	status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(status_label)


func _add_button(label: String, callback: Callable) -> void:
	var button := Button.new()
	button.text = label
	button.pressed.connect(callback)
	add_child(button)


func _load_authoring() -> void:
	var root: Node = _authoring_root()
	status_label.text = root.load_authoring_data() if root != null else "当前场景没有 TerrainAuthoringRoot。"


func _save_authoring() -> void:
	var root: Node = _authoring_root()
	if root == null:
		status_label.text = "当前场景没有 TerrainAuthoringRoot。"
		return
	var warnings: PackedStringArray = root.get_configuration_warnings()
	if not warnings.is_empty():
		status_label.text = "存在配置警告，未回写：\n%s" % "\n".join(warnings)
		return
	status_label.text = root.save_authoring_data()


func _add_polygon() -> void:
	var root: Node = _authoring_root()
	status_label.text = root.add_semantic_polygon(semantic_selector.get_item_text(semantic_selector.selected)) if root != null else "当前场景没有 TerrainAuthoringRoot。"


func _add_anchor() -> void:
	var root: Node = _authoring_root()
	status_label.text = root.add_facility_anchor() if root != null else "当前场景没有 TerrainAuthoringRoot。"


func _add_land_instance() -> void:
	var root: Node = _authoring_root()
	status_label.text = root.add_land_instance() if root != null else "当前场景没有 TerrainAuthoringRoot。"


func _add_facility() -> void:
	var root: Node = _authoring_root()
	status_label.text = root.add_facility_placement() if root != null else "当前场景没有 TerrainAuthoringRoot。"


func _authoring_root() -> Node:
	if editor_interface == null:
		return null
	var edited_root := editor_interface.get_edited_scene_root()
	if edited_root == null:
		return null
	if edited_root.has_method("load_authoring_data"):
		return edited_root
	for node in edited_root.find_children("*", "Node", true, false):
		if node.has_method("load_authoring_data"):
			return node
	return null


func _run_action(label: String) -> void:
	var commands := {
		"烘焙世界坐标": ["python3", "tools/terrain/bake_terrain_definition.py"],
		"校验几何与可达性": ["python3", "tools/terrain/validate_terrain_definition.py"],
		"生成共享导航": ["python3", "tools/terrain/bake_navigation_graph.py"],
		"生成小地图": ["python3", "tools/terrain/build_minimap_masks.py"],
		"生成 QA 总览": ["python3", "tools/terrain/build_scene_combat_contact_sheet.py"],
	}.get(label, [])
	if label == "运行完整流水线":
		_execute(["python3", "tools/terrain/build_scene_combat_pipeline.py"])
		return
	_execute(commands)


func _execute(command: Array) -> bool:
	if command.is_empty():
		return false
	var output: Array = []
	var arguments: PackedStringArray = []
	for index in range(1, command.size()): arguments.append(str(command[index]))
	var project_root := ProjectSettings.globalize_path("res://")
	var quoted_root := "\"%s\"" % project_root.replace("\"", "\\\"")
	var shell_command := "cd %s && %s %s" % [quoted_root, str(command[0]), " ".join(arguments)]
	var exit_code := OS.execute("/bin/zsh", PackedStringArray(["-lc", shell_command]), output, true)
	status_label.text = ("通过\n" if exit_code == 0 else "失败（%d）\n" % exit_code) + "\n".join(output).left(1200)
	return exit_code == 0
