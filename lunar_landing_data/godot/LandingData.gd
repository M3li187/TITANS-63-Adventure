extends Node
## Copy the complete lunar_landing_data folder into your Godot project's root.
## Add this script to a Node. All resources are local; no API key is required.

@export var data_folder := "res://lunar_landing_data/data/"
var reference: Dictionary = {}
var scenario_data: Dictionary = {}
var fuel_percent := 100.0
var power_percent := 100.0
var time_remaining_minutes := 20.0
var landing_aborted := false


func _ready() -> void:
	reference = read_json(data_folder + "nasa_reference.json")
	scenario_data = read_json(data_folder + "scenarios.json")
	reset_resources()


func read_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		push_error("Missing data file: " + path)
		return {}
	var parser := JSON.new()
	var error := parser.parse(FileAccess.get_file_as_string(path))
	if error != OK or not parser.data is Dictionary:
		push_error("Invalid JSON dictionary: " + path)
		return {}
	return parser.data as Dictionary


func reset_resources() -> void:
	var initial: Dictionary = scenario_data.get("initial_resources", {})
	fuel_percent = float(initial.get("fuel_percent", 100))
	power_percent = float(initial.get("power_percent", 100))
	time_remaining_minutes = float(initial.get("time_remaining_minutes", 20))
	landing_aborted = false


func get_scenario(id: String) -> Dictionary:
	for item in scenario_data.get("scenarios", []):
		if item["id"] == id:
			return item
	return {}


func apply_choice(scenario_id: String, choice_id: String) -> Dictionary:
	if landing_aborted:
		return {}
	var scenario := get_scenario(scenario_id)
	for choice in scenario.get("choices", []):
		if choice["id"] != choice_id:
			continue
		if choice["effect"] == "safe_abort":
			landing_aborted = true
			return choice
		var cost: Dictionary = choice["cost"]
		fuel_percent = maxf(0.0, fuel_percent - float(cost["fuel_percentage_points"]))
		power_percent = maxf(0.0, power_percent - float(cost["power_percentage_points"]))
		time_remaining_minutes = maxf(0.0, time_remaining_minutes - float(cost["time_minutes"]))
		return choice
	return {}
