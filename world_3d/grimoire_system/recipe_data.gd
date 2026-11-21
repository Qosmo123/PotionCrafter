@tool
class_name RecipeData
extends Resource
## A grimoire entry: a *target signature* measured on emergent results, plus
## suggested ingredients and the formula it illustrates. Recipes never drive
## the simulation; the RecipeBook only recognises when a vessel's contents
## match the signature. Secret recipes stay hidden behind a riddle until then.

enum Category { SCIENCE, FANTASY, SECRET, FUN }

@export var recipe_id: StringName = &""
@export var title: String = ""
@export var category: Category = Category.SCIENCE
## Equation or formula shown in the book, e.g. "CH₃COOH + NaHCO₃ → …".
@export var formula: String = ""
@export_multiline var description: String = ""
## Shown instead of everything else while a secret recipe is undiscovered.
@export var riddle: String = ""
@export var ingredients: PackedStringArray = PackedStringArray()
@export var method_steps: PackedStringArray = PackedStringArray()
## Signature: trait name -> [min, max]. Traits are listed in RecipeBook.measure().
## "fraction:<substance_id>" is that substance's mole fraction.
@export var condition_traits: PackedStringArray = PackedStringArray()
@export var condition_min: PackedFloat32Array = PackedFloat32Array()
@export var condition_max: PackedFloat32Array = PackedFloat32Array()
