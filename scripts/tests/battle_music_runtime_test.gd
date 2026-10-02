extends SceneTree
var checks := 0
var failures: Array[String] = []
func _init(): call_deferred("run")
func check(value: bool, message: String):
	checks += 1
	if not value: failures.append(message)
func run():
	var music = root.get_node("MusicManager")
	check(music.battle_tracks.size() == 8, "eight adopted battle/result tracks")
	check(music.tracks.size() == 5, "title queue remains isolated")
	for id in music.battle_tracks:
		var track: Dictionary = music.battle_tracks[id]
		var resource = load(track.path)
		check(resource is AudioStreamOggVorbis and absf(resource.get_length() - float(track.duration)) < 0.1, "engine decode " + id)
		check(FileAccess.get_sha256(track.path) == track.sha256, "runtime hash " + id)
		check(FileAccess.get_sha256("res://assets/audio/music/source/" + id + "/source.wav") == track.source_sha256, "source hash " + id)
	music.enter_title(); music.advance(12); music.toggle_pause()
	var saved_queue: Array = music.queue.duplicate()
	music.enter_battle("level.tutorial.t01")
	check(music.battle_id in ["battle_watchful_route_v1", "battle_gentle_companions_v1"], "tutorial restrained pool")
	music.advance(2); music.advance(10)
	check(music.battle_position == 10 and music.title_paused, "title pause cannot pause battle")
	music.sync_battle("Paused", {}); music.advance(2)
	check(music.battle_position == 12 and is_equal_approx(music.duck_gain, 0.35), "pause ducks without stopping clock")
	music.sync_battle("Running", {}); music.advance(2)
	check(is_equal_approx(music.duck_gain, 1), "resume restores volume")
	var id: String = music.battle_id
	for cycle in range(3):
		music.advance(float(music.battle_tracks[id].duration))
		check(music.battle_id == id and music.battle_position == 0, "same song loops through long battle")
	for index in range(15):
		var previous: String = music.battle_id
		music.enter_battle("level.prototype_3v3")
		check(music.battle_id != previous and music.battle_id != "battle_finale_distant_decisive_v1", "normal battles avoid repetition and finale")
	music.enter_battle("level.challenge.l05")
	check(music.battle_id == "battle_finale_distant_decisive_v1", "L05 finale")
	for pair in [["player", "victory"], ["enemy", "defeat"], ["", ""]]:
		music.enter_battle("level.prototype_3v3")
		var result := {"winner_faction": pair[0], "reason": "TIME_LIMIT"}
		music.sync_battle("Finished", result)
		check(music.battle_id.is_empty() if pair[1].is_empty() else music.battle_tracks[music.battle_id].category == pair[1], "authoritative result mapping")
		music.advance(1); music.advance(4)
		music.sync_battle("Finished", result)
		check(music.transition_remaining == 0, "repeated result does not restart")
		music.advance(100)
		check(music.battle_id.is_empty(), "unmarked result aftermath remains quiet")
	music.enter_battle("level.prototype_3v3")
	music.sync_battle("Finished", {"winner_faction": "player", "reason": "LEVEL_TECHNICAL_LIMIT"})
	check(music.battle_id.is_empty(), "invalid result never celebrates")
	music.enter_battle("level.prototype_3v3")
	music.sync_battle("Finished", {"winner_faction": "player"})
	music.enter_battle("level.prototype_3v3"); music.advance(2)
	check(music.battle_state == "battle" and music.battle_tracks[music.battle_id].category == "battle", "retry cancels pending result")
	music.enter_title(); music.advance(10)
	check(music.battle_state.is_empty() and music.title_paused and music.queue.size() == saved_queue.size() - 1, "return restores title queue/pause and cancels transition")
	music.toggle_pause()
	# Exercise real player scheduling with Dummy audio, including paused title release.
	for i in range(2):
		var player := AudioStreamPlayer.new()
		music.add_child(player)
		music.channels.append({"player":player,"gain":0.0,"from":0.0,"target":0.0,"elapsed":0.0,"duration":0.0})
	music.device_enabled = true
	var title_tracks: Dictionary = music.tracks
	music.tracks = {}
	music.enter_battle("level.prototype_3v3"); music.advance(2)
	check(music.current_channel >= 0, "battle audio works without title assets")
	music.leave_battle(); music.tracks = title_tracks
	music.enter_title()
	music.next_track(); music.toggle_pause()
	music.enter_battle("level.prototype_3v3"); music.advance(2)
	check(not music.channels[music.current_channel].player.stream_paused, "actual battle voice ignores title pause")
	check(music.channels.filter(func(c): return c.player.playing).size() == 1, "one battle voice after handoff")
	music.sync_battle("Finished", {"winner_faction":"enemy"}); music.advance(1)
	check(music.channels[music.current_channel].player.stream == music.streams[music.battle_id], "actual result stream handoff")
	music.leave_battle()
	check(music.channels.all(func(c): return not c.player.playing), "exit releases voices")
	music.device_enabled = false
	# Real scene entry/restart/exit uses the same lifecycle.
	var battle = load("res://scenes/battle/prototype_battle.tscn").instantiate()
	root.add_child(battle); await process_frame
	check(music.battle_state == "battle", "scene starts battle music")
	battle._restart_battle()
	check(music.battle_state == "battle", "scene retry starts new music session")
	battle.queue_free(); await process_frame
	check(music.battle_state.is_empty(), "scene exit clears music")
	for failure in failures: push_error(failure)
	print("BATTLE_MUSIC %d/%d passed" % [checks - failures.size(), checks])
	quit(0 if failures.is_empty() else 1)
