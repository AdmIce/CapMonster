extends Node
## Autoload: GameLog
##
## Single entry point for engine-side logging so every message carries a channel
## tag ([Battle], [Save], ...) and can be filtered without hunting down prints.

enum Channel {
	SYSTEM,
	DATA,
	SAVE,
	WORLD,
	CREATURE,
	BATTLE,
	CAPTURE,
	IDLE,
	QUEST,
	UI,
}

const CHANNEL_NAMES := {
	Channel.SYSTEM: "System",
	Channel.DATA: "Data",
	Channel.SAVE: "Save",
	Channel.WORLD: "World",
	Channel.CREATURE: "Creature",
	Channel.BATTLE: "Battle",
	Channel.CAPTURE: "Capture",
	Channel.IDLE: "Idle",
	Channel.QUEST: "Quest",
	Channel.UI: "UI",
}

## Channels muted at runtime. Kept as a set so the debug menu can toggle them.
var muted: Dictionary = {}
## Verbose messages are dropped entirely in release builds.
var verbose_enabled: bool = OS.is_debug_build()


func info(channel: Channel, message: String) -> void:
	if muted.has(channel):
		return
	print("[%s] %s" % [CHANNEL_NAMES[channel], message])


func verbose(channel: Channel, message: String) -> void:
	if not verbose_enabled or muted.has(channel):
		return
	print("[%s] %s" % [CHANNEL_NAMES[channel], message])


func warn(channel: Channel, message: String) -> void:
	push_warning("[%s] %s" % [CHANNEL_NAMES[channel], message])
	print("[%s] WARNING: %s" % [CHANNEL_NAMES[channel], message])


func error(channel: Channel, message: String) -> void:
	push_error("[%s] %s" % [CHANNEL_NAMES[channel], message])
	printerr("[%s] ERROR: %s" % [CHANNEL_NAMES[channel], message])


func set_channel_muted(channel: Channel, is_muted: bool) -> void:
	if is_muted:
		muted[channel] = true
	else:
		muted.erase(channel)
