tool
extends Popup


onready var filter = $Panel/MarginContainer/VBoxContainer/MarginContainer2/HSplitContainer/VBoxContainer/HBoxContainer/Filter
onready var item_list = $Panel/MarginContainer/VBoxContainer/MarginContainer2/HSplitContainer/VBoxContainer/MarginContainer/HBoxContainer/ItemList
onready var file_tree = $Panel/MarginContainer/VBoxContainer/MarginContainer2/HSplitContainer/Tree
onready var copy_path_button =$Panel/MarginContainer/VBoxContainer/MarginContainer2/HSplitContainer/VBoxContainer/HBoxContainer/Button

# save the file after you made changes in the inspector; reenable the plugin in the project settings or reopen the project to apply the update 
export (bool) var collapse_paths_when_full = true # collapse paths when the tree fills the entire popup
export (Color) var file_tree_selection_color = Color.aquamarine # #80ffd4

var scenes : Dictionary # holds all scenes wether they are open or not; Key: file_name, Value: file_path
var scripts : Dictionary # holds all scripts wether they are open or not; Key: file_name, Value: Scripts
var file_tree_paths : Array # holds the file_paths to the scripts and scenes in the item_list to build the file_tree structure; kinda duplicate/overlap code
var file_items : Dictionary # holds all the TreeItems of the scripts/scenes in the tree
var current_file # switch between the last 2 opened files (only when opened with this plugin)
var last_file # switch between the last 2 opened files (only when opened with this plugin)

var PLUGIN : EditorPlugin
var INTERFACE : EditorInterface
var EDITOR : ScriptEditor
var FILE_SYSTEM : EditorFileSystem


func _ready() -> void:
	_initialize()


func _initialize() -> void:
	connect("popup_hide", self, "_on_popup_hide")
	filter.connect("text_changed", self, "_on_filter_text_changed")
	filter.connect("text_entered", self, "_on_filter_text_entered")
	item_list.connect("item_selected", self, "_on_item_list_selected")
	item_list.connect("item_activated", self, "_on_item_list_activated")
	file_tree.connect("item_activated", self, "_on_item_tree_activated")
	file_tree.connect("item_selected", self, "_on_item_tree_selected")
	copy_path_button.connect("pressed", self, "_on_copy_button_pressed")
	FILE_SYSTEM.connect("filesystem_changed", self, "_on_filesystem_changed")
	_update_file_dictionaries(FILE_SYSTEM.get_filesystem()) 


# global keyboard shortcuts
func _unhandled_key_input(event: InputEventKey) -> void:
	if event.as_text() == "Control+E" and event.is_pressed() and visible and not filter.text and filter.has_focus():
		# switch between the last two opened files (only when opened via this plugin)
		if scripts.has(last_file):
			_switch_to_scene_tab_of(scripts[last_file])
			_open_script(scripts[last_file])
		elif scenes.has(last_file):
			_open_scene(scenes[last_file])
		hide()
	elif event.as_text() == "Control+E" and event.is_pressed():
		rect_size = Vector2(800, 900)
		popup_centered()
		_update_popup_list()


func _on_filesystem_changed() -> void:
	scenes.clear()
	scripts.clear()
	_update_file_dictionaries(FILE_SYSTEM.get_filesystem())


func _on_copy_button_pressed() -> void:
	var file_name = file_tree.get_selected().get_text(0)
	var path = scenes[file_name] if scenes.has(file_name) else scripts[file_name].resource_path
	OS.clipboard = path
	hide()


func _on_popup_hide() -> void:
	filter.clear()


func _on_item_list_selected(index : int) -> void:
	_update_tree_colors()
	call_deferred("_selection", index)


func _on_item_list_activated(index : int) -> void:
	_open_selection()


func _on_item_tree_selected() -> void:
	var file_name = file_tree.get_selected().get_text(0)
	for item in item_list.get_item_count():
		if item_list.get_item_text(item).ends_with(file_name):
			item_list.select(item)
	_update_tree_colors()
	item_list.ensure_current_is_visible()


func _on_item_tree_activated() -> void:
	_open_selection()


func _on_filter_text_changed(new_txt : String) -> void:
	_update_popup_list()


func _on_filter_text_entered(new_txt : String) -> void:
	_open_selection()


func _open_selection() -> void:
	var selection = item_list.get_selected_items()
	if selection:
		var selected = item_list.get_item_text(selection[0])
		var selected_file_name = selected.split("  ::  ")[1] 
		if selected_file_name.findn(".gd") != -1 or selected_file_name.findn(".vs") != -1: 
			_switch_to_scene_tab_of(scripts[selected_file_name])
			_open_script(scripts[selected_file_name])
		else: 
			_open_scene(scenes[selected_file_name])
	hide()


# open the scene a script is attached to. Only works if the script is attached to the scene root.
# I dont know how expensive the constant loading/freeing of scenes is
func _switch_to_scene_tab_of(script : Script) -> void:
	for scene_name in scenes:
		var scene_path = scenes[scene_name]
		var scene = load(scene_path).instance()
		if scene.get_script() == script:
			scene.queue_free()
			INTERFACE.open_scene_from_path(scene_path)
			return
		scene.queue_free()


func _open_script(script : Script) -> void:
	INTERFACE.edit_resource(script)
	INTERFACE.call_deferred("set_main_screen_editor", "Script")
	if not current_file:
		current_file = script.resource_path.get_file()
	else:
		last_file = current_file
		current_file = script.resource_path.get_file()


func _open_scene(path : String) -> void:
	INTERFACE.open_scene_from_path(path)
	INTERFACE.call_deferred("set_main_screen_editor", "3D") if INTERFACE.get_edited_scene_root() is Spatial else INTERFACE.call_deferred("set_main_screen_editor", "2D")
	if not current_file:
		current_file = path.get_file()
	else:
		last_file = current_file
		current_file = path.get_file()


# not sure about performance when constantly iterating over the file structures (especially with large number of files)...
func _update_file_dictionaries(folder : EditorFileSystemDirectory) -> void:
	for file in folder.get_file_count():
		var file_path = folder.get_file_path(file)
		var file_type = FILE_SYSTEM.get_file_type(file_path)
			
		if file_type.findn("Script") != -1:
			scripts[folder.get_file(file)] = load(file_path)
			
		elif file_type.findn("Scene") != -1: 
			scenes[folder.get_file(file)] = file_path
		
	for subdir in folder.get_subdir_count():
		_update_file_dictionaries(folder.get_subdir(subdir))


# search happens only on the actual file name
func _update_popup_list() -> void:
	file_tree_paths.clear()
	item_list.clear()
	var search_string = filter.text
		
	# typing " X" (where X is an integer) at the end of the search_string jumps to that item in the item_list
	var quickselect_line = 0 
	var quickselect_index = search_string.find_last(" ")
	if quickselect_index != -1 and not search_string.ends_with(" "):
		quickselect_line = search_string.substr(quickselect_index + 1)
		if quickselect_line.is_valid_integer():
			search_string.erase(quickselect_index + 1, String(quickselect_line).length())
		
	if search_string.begins_with("a "):
		_add_scripts(search_string.substr(2).strip_edges(), scripts)
		_add_scenes(search_string.substr(2).strip_edges(), scenes)
	elif search_string.begins_with("ac ") or search_string.begins_with("ca "):
		_add_scripts(search_string.substr(3).strip_edges(), scripts)
	elif search_string.begins_with("as ") or search_string.begins_with("sa "):
		_add_scenes(search_string.substr(3).strip_edges(), scenes)
	elif search_string.begins_with("c "):
		_add_scripts(search_string.substr(2).strip_edges(), EDITOR.get_open_scripts())
	elif search_string.begins_with("s "):
		_add_scenes(search_string.substr(2).strip_edges(), INTERFACE.get_open_scenes())
	else:
		_add_scripts(search_string.strip_edges(), EDITOR.get_open_scripts())
		_add_scenes(search_string.strip_edges(), INTERFACE.get_open_scenes())
		
	item_list.sort_items_by_text()
	_count_list()
	quickselect_line = clamp(quickselect_line as int, 0, item_list.get_item_count() - 1)
	call_deferred("_selection", quickselect_line)
	call_deferred("_update_tree_structure", file_tree_paths)


func _selection(index : int) -> void:
	if index != -1:
		item_list.select(index)
		call_deferred("_selection_file_tree")
	item_list.ensure_current_is_visible()


func _selection_file_tree() -> void:
	var selection = item_list.get_selected_items()
	if selection:
		var file_name = item_list.get_item_text(selection[0]).split("  ::  ")[1]
		file_items[file_name].select(0)
	file_tree.ensure_cursor_is_visible()


func _add_scripts(search_string : String, script_list) -> void:
	var script_icon = INTERFACE.get_base_control().get_icon("Script", "EditorIcons")
	for script in script_list:
		var script_name = script.resource_path.get_file() if script_list is Array else script
		if search_string:
			if script_name.findn(search_string) != -1:
				file_tree_paths.push_back(scripts[script_name].resource_path)
				item_list.add_item(script_name, script_icon)
		else:
			file_tree_paths.push_back(scripts[script_name].resource_path)
			item_list.add_item(script_name, script_icon)


func _add_scenes(search_string : String, scene_list) -> void:
	var scene_icon = INTERFACE.get_base_control().get_icon("PackedScene", "EditorIcons")
	for scene in scene_list:
		var scene_path = scene if scene_list is Array else scenes[scene]
		var scene_name = scene_path.get_file() if scene_list is Array else scene
		if search_string:
			if scene_name.findn(search_string) != -1:
				file_tree_paths.push_back(scene_path)
				item_list.add_item(scene_name, scene_icon)
		else:
			item_list.add_item(scene_name, scene_icon)
			file_tree_paths.push_back(scene_path)


func _count_list() -> void:
	for item in item_list.get_item_count():
		item_list.set_item_text(item, String(item) + "  ::  " + item_list.get_item_text(item))


func _update_tree_structure(file_paths : Array) -> void:
	file_tree.clear()
	file_items.clear()
	var selection = item_list.get_selected_items()
	if selection:
		var file_path_of_selection = item_list.get_item_text(selection[0]).split("  ::  ")[1]
		file_path_of_selection = scenes[file_path_of_selection] if scenes.has(file_path_of_selection) else scripts[file_path_of_selection].resource_path
			
		var root = file_tree.create_item()
		root.set_text(0, "res://")
		root.set_selectable(0, false)
		for scene_path in file_paths:
			var curr_selection = false
			if scene_path == file_path_of_selection:
				curr_selection = true
			scene_path.erase(0, 6)
			var current_parent = file_tree.get_root()
			var current_dir = file_tree.get_root().get_children()
			var file_or_folder_names = scene_path.split("/")
			# travel through the tree and create the folders according to the scene_paths to a file, if they don't exist.
			while true:
				# if the current directory doesn't exit, it means all the following folders of the scene_path need to be created as well
				if not current_dir:
					while file_or_folder_names:
						var new_item = file_tree.create_item(current_parent)
						new_item.set_text(0, file_or_folder_names[0])
						file_or_folder_names.remove(0)
						# case: file creation
						if file_or_folder_names.size() == 0:
							var script_icon = INTERFACE.get_base_control().get_icon("Script", "EditorIcons")
							var scene_icon = INTERFACE.get_base_control().get_icon("PackedScene", "EditorIcons")
							new_item.set_icon(0, script_icon if new_item.get_text(0).findn(".gd") != -1 or new_item.get_text(0).findn(".vs") != -1 else scene_icon)
							file_items[new_item.get_text(0)] = new_item
						# case: more folders
						else:
							current_parent = new_item
							new_item.set_selectable(0, false) 
					break # reaching this, it means the entire path for the current file has been created
				# if the current directiory exists, we just travel through the TreeItems matching the file_path
				if current_dir.get_text(0) == file_or_folder_names[0]:
					file_or_folder_names.remove(0)
					current_parent = current_dir
					current_dir = current_dir.get_children()
				else:
					current_dir = current_dir.get_next()
	call_deferred("_update_tree_colors")


func _update_tree_colors() -> void:
	_reset_colors(file_tree.get_root())
	var curr_selected = file_tree.get_selected()
	if curr_selected:
		var selected_path = scenes[curr_selected.get_text(0)] if scenes.has(curr_selected.get_text(0)) else scripts[curr_selected.get_text(0)].resource_path
		selected_path.erase(0, 6)
		_color_path(selected_path.split("/"))


func _reset_colors(currrent_dir : TreeItem) -> void:
	if currrent_dir:
		currrent_dir.set_custom_color(0, Color(0.63, 0.63, 0.63, 1))
		var current_child : TreeItem = currrent_dir.get_children()
		while current_child:
			if collapse_paths_when_full and file_tree.get_child(4).visible: # 4th child = VScrollBar
				current_child.collapsed = true
			_reset_colors(current_child)
			current_child = current_child.get_next()


func _color_path(file_or_folder : PoolStringArray) -> void:
	var current_dir = file_tree.get_root().get_children()
	file_tree.get_root().set_custom_color(0, file_tree_selection_color)
	while file_or_folder.size():
		if current_dir.get_text(0) == file_or_folder[0]:
			if current_dir.get_children() and collapse_paths_when_full:
				current_dir.collapsed = false
			current_dir.set_custom_color(0, file_tree_selection_color) if file_or_folder.size() > 1 else current_dir.set_custom_color(0, Color.white)
			file_or_folder.remove(0)
			current_dir = current_dir.get_children()
		else:
			current_dir = current_dir.get_next()
	if collapse_paths_when_full:
		call_deferred("_selection_file_tree")