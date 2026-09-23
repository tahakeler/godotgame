class_name UserDataGuard
extends Node

## Stops a headless test run from leaving the player's real save data changed.
##
## Settings and personal bests live in user://settings.cfg and
## user://records.cfg. Several manual tests round-trip settings with probe
## values, submit fake runs, or delete records outright, because that is the
## only way to test those systems. `./tools/check.sh` sidesteps the risk by
## pointing HOME at a private directory for the whole gate, but a test run
## directly — by a developer or another agent, which happens constantly — has
## no such isolation and writes straight into the real user:// directory.
##
## This node snapshots the exact bytes of both files the moment it is
## created, before the test that installed it has had a chance to touch
## either one, and writes those bytes back byte-for-byte the moment it leaves
## the tree. A file that did not exist before the test is deleted again
## rather than left behind. This makes the restore unconditional: it does not
## matter whether the test that ran remembered to undo its own writes, only
## that this node was installed before anything could write.

## The two files every test in this suite is capable of disturbing. Listed
## here once so a third file at risk in the future only needs adding here.
const WATCHED_PATHS := [
	"user://settings.cfg",
	"user://records.cfg",
]

## Path -> PackedByteArray snapshot, or null if the path had no file yet.
## Keyed by path rather than a parallel array so restore cannot mismatch a
## path against the wrong snapshot.
var _snapshots: Dictionary = {}
var _restored := false


func _init() -> void:
	for path in WATCHED_PATHS:
		_snapshots[path] = _read_bytes(path)


## NOTIFICATION_EXIT_TREE fires while quit() tears the tree down, which is
## how every manual test ends. NOTIFICATION_PREDELETE is also handled, and
## the _restored flag makes handling both harmless, in case a caller frees
## this node directly instead of going through quit().
func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE or what == NOTIFICATION_EXIT_TREE:
		_restore()


## Attaches one guard to `root`, or does nothing if one is already there.
## Idempotent so every call site that wants to be sure userdata is protected
## can call this without coordinating with whoever else might have already
## installed one for the same test run.
static func install(root: Node) -> void:
	if root == null:
		return
	if root.get_node_or_null("UserDataGuard") != null:
		return

	var guard := UserDataGuard.new()
	guard.name = "UserDataGuard"
	root.add_child(guard)


## Returns the file's raw bytes, or null if there is no file at `path`.
func _read_bytes(path: String):
	if not FileAccess.file_exists(path):
		return null

	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return null

	return file.get_buffer(file.get_length())


func _restore() -> void:
	if _restored:
		return
	_restored = true

	for path in WATCHED_PATHS:
		var original = _snapshots[path]

		if original == null:
			# There was no file here before the test. If one exists now, the
			# test created it, and the player's userdata directory should end
			# up exactly as it started.
			if FileAccess.file_exists(path):
				DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
			continue

		var file := FileAccess.open(path, FileAccess.WRITE)
		if file == null:
			push_error("UserDataGuard could not restore %s — it may be left changed." % path)
			continue

		file.store_buffer(original)
