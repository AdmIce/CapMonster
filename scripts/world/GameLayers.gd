class_name GameLayers
extends RefCounted
## Single definition of the physics layers. Every collider in the game sets its
## layer/mask through these constants so the bit meanings never drift.

const WORLD := 1 << 0        ## static geometry: ground, props, walls
const PLAYER := 1 << 1       ## the player body
const CREATURE := 1 << 2     ## wild creature bodies
const INTERACT := 1 << 3     ## interactable trigger areas (npc, gate, heal point)
const AGGRO := 1 << 4        ## wild creature detection areas
