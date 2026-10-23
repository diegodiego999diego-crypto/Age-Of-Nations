extends Control

func _ready():
    # Conectar la señal del botón "Start Game" a la función _on_start_button_pressed
    $StartButton.pressed.connect(_on_start_button_pressed)

func _on_start_button_pressed():
    # Cambiar a la escena del mapa
    get_tree().change_scene_to_file("res://scenes/Map.tscn")