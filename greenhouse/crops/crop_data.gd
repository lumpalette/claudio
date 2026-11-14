class_name CropData
extends Resource

## Ficha de un cultivo. Cada .tres (carrot, lettuce, dwarf_tomato) es una copia llena de esto.

@export var id: String = ""                 ## "carrot", "lettuce", "dwarf_tomato"
@export var display_name: String = ""       ## Nombre que ve el jugador: "Zanahoria"
@export var days_to_harvest: int = 3        ## Noches regadas para estar lista
@export var portions: int = 2               ## Raciones de comida al cosechar
@export var oxygen_per_night: int = 3       ## Oxígeno que aporta cada noche si está viva
@export_multiline var fun_fact: String = "" ## Dato curioso al cosechar

@export_group("Sprites")
@export var seed_texture: Texture2D
@export var sprout_texture: Texture2D
@export var grown_texture: Texture2D
@export var ready_texture: Texture2D
@export var withered_texture: Texture2D
