#    Copyright (C) 2018  Rob Nugen
#
#    This program is free software: you can redistribute it and/or modify
#    it under the terms of the GNU General Public License as published by
#    the Free Software Foundation, either version 3 of the License, or
#    (at your option) any later version.
#
#    This program is distributed in the hope that it will be useful,
#    but WITHOUT ANY WARRANTY; without even the implied warranty of
#    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#    GNU General Public License for more details.
#
#    You should have received a copy of the GNU General Public License
#    along with this program.  If not, see <http://www.gnu.org/licenses/>.

extends Node2D

const forcelevel0 = false
export var easywin = false

const Buttons = preload("res://subscenes/Buttons.gd")
const StarsAfterLevel = preload("res://subscenes/LevelEndedStars.tscn")
const LevelRequirements = preload("res://subscenes/LevelRequirements.tscn")
const SwipeShape = preload("res://subscenes/SwipeShape.tscn")

# gravity is what pulls the piece down slowly
var GRAVITY_TIMEOUT = 1     # fake constant that will change with level
const MIN_TIME  = 0.07		# wait at least this long between processing inputs
const MIN_DROP_MODE_TIME = 0.004   # wait this long between move-down when in drop_mode
# mganetism pulls the pieces down quickly after swipes have erased pieces below them
const MAGNETISM_TIME = 0.2504

var current_level	= null	# will hold level definition
var level_over_reason = 0	# remember why we lost so we can slowly end the level, telling each overlay why we lost
var level_num = 0			# will hold integer of level number
var elapsed_time = 10		# pretend it has been 10 seconds so input can definitely be processed upon start
var time_label				# will display time remain

var input_x_direction	# -1 = left; 0 = stay; 1 = right
var input_y_direction	# -1 = down; 0 = stay; 1 = up, but not implemented
var drop_mode = false   # true = drop the player
var gravity_called = false # true = move down 1 unit via gravity

var player_position			# Vector2 of slot player is in
var player					# Two (2) tiles: (player and shadow)
var stars_after_level		# Show stars after level is over
var buttons					# Steering Pad / Start buttons
var level_reqs				# HUD showing level requirements
var clicked_this_piece_type = 0				# set when swipe is started
var swipe_mode= false			# if true, then we are swiping
var swipe_array = []			# the pieces in the swipe
var swipe_shape = null			# will animate shape user swiped

var wasted_swipes = 0

func _ready():
	self.stars_after_level = StarsAfterLevel.instance()
	self.stars_after_level.set_game_scene(self)
	add_child(self.stars_after_level)

	self.buttons = Buttons.new()			# Buttons pre/post level
	# buttons are kinda like a HUD but for input, not output
	self.buttons.set_game_scene(self)
	add_child(self.buttons)

	Helpers.game_scene = self		# so Players know where to appear
	time_label = get_node("LevelTimer/LevelTimerLabel")
	stop_level_timer()

	# tell the Magnetism timer to call Helpers.magnetism_called (every MAGNETISM_TIME seconds)
	get_node("Magnetism").connect("timeout", get_node("/root/Helpers"), "magnetism_called", [])

	level_reqs = LevelRequirements.instance()
	level_reqs.set_game_scene(self)
	add_child(level_reqs)

	# TODO: add START button overlay
	# which will trigger this call:
	requested_play_level(Helpers.requested_level)

func requested_replay_level():
	requested_play_level(Helpers.requested_level)

func requested_next_level():
	Helpers.requested_level = Helpers.requested_level + 1
	requested_play_level(Helpers.requested_level)

func requested_play_level(level):
	start_level(level)

func start_level(level_num):
	self.wasted_swipes = 0	# wasted swipes will count against bonus
	set_process(false)		# not sure that this actually helps
	grok_input(false)		# don't allow keyboard input during display of requirements
	self.level_num = level_num
	if forcelevel0:
		self.level_num = 0

	var levelGDScript = LevelDatabase.getExistingLevelGDScript(self.level_num)
	current_level = levelGDScript.new()		# load() gets a GDScript and new() instantiates it
	# now that we have loaded the level, we can tell the game how it wants us to run
	if self.easywin:
		current_level.debug_level = 1
		current_level.fill_level = true
	Helpers.grok_level(current_level)	# so we have level info available everywhere
	GRAVITY_TIMEOUT = current_level.gravity_timeout

	# TODO deal with the case that the current board is smaller then previous level
	# in which case the slots_across will be too small to clear everything
	Helpers.clear_game_board()

	level_reqs.show_finger_ka(current_level.show_finger)
	level_reqs.level_requires(current_level.level_requirements)
	buttons.prepare_to_play_level(self.level_num)


# turn input off for all children while display requirements / show cut scenes and the like
func grok_input(boolean):
	buttons.grok_input(boolean)

func continue_start_level():
	# magnetism makes the nailed pieces fall (all pieces in board{})
	start_magnetism()

	# if level timer runs out the level is lost
	start_level_timer()

	# Fill the level halfway, if max_tiles_avail allows it
	if current_level.fill_level:
		fill_game_board()
	new_player()

func fill_game_board():
	# top corner is 0,0
	for across in range(Helpers.slots_across):
		for down in range(Helpers.slots_down/2, Helpers.slots_down):
			player_position = Vector2(across, down)

			if Helpers.instantiatePlayer(player_position):
				# lock player into position on Helpers.board{}
				nail_player()
			else:
				print("no more tiles available to fill game board!")

func new_player():
	# turn off drop mode
	drop_mode = false
	stop_moving()

	# select top center position
	player_position = Vector2(Helpers.slots_across/2, 0)
	# check game over
	if Helpers.board[Vector2(player_position.x, player_position.y)] != null:
		_level_over_prep(G.LEVEL_NO_ROOM)
		return

	if Helpers.instantiatePlayer(player_position):
		player.set_show_shadow(true)
		set_process(true)		# allows players to move
		grok_input(true)		# now we can give keyboard input
		start_gravity_timer()
	else:
		print("no more tiles available to play game!")

#######################################################
#
#  Level is over, so we need to turn everything off
#  Then show the player the results (asynchronously)
func _level_over_prep(reason):
	self.level_over_reason = reason
	grok_input(false)	# buttons.level_ended will turn on buttons again

	# gray out block sprites if existing
	stop_magnetism()
	stop_gravity_timer()
	stop_level_timer()
	var existing_sprites = get_tree().get_nodes_in_group("players")
	for sprite in existing_sprites:
		sprite.level_ended()
	self._show_stuff_after_level(self.level_over_reason)

#######################################################
#
#    Need to collect all data to determine number of stars
#    Then send that info to be displayed asynchronously
func _show_stuff_after_level(reason):
	var collect_info_for_stars = {'reason':reason,
									'level':self.level_num,
									'num_tiles':self.level_reqs.num_tiles_required,
									'waste_swipes':self.wasted_swipes
								}
	self.stars_after_level.show_stuff_after_level(collect_info_for_stars)

#######################################################
#
#  	signal catcher
func _on_level_over_stars_displayed():
	self.level_over_stars_were_displayed()

func level_over_stars_were_displayed():
	self._level_over_display_buttons(self.level_over_reason)

func _level_over_display_buttons(reason):
	buttons.level_ended(reason)

# this is only to handle orphaned swipes
func _on_OrphanSwipeCatcher_input_event( viewport, event, shape_idx ):
	if event is InputEventMouseButton:
		if event.button_index == 1:
			if !event.pressed:
				piece_unclicked()

func _process(delta):

	if gravity_called:
		input_y_direction = 1

	time_label.set_text(str(int(get_node("LevelTimer").get_time_left())))

	# if it has not been long enough, get out of here
	if (not drop_mode and elapsed_time < MIN_TIME) or (drop_mode and elapsed_time < MIN_DROP_MODE_TIME):
		elapsed_time += delta
		return

	# it has been long enough, so reset the timer before processing
	elapsed_time = 0

	if drop_mode:
		# turn on drop mode
		input_y_direction = 1

	# if we can move, move
	if check_movable(input_x_direction, 0):
		move_player(input_x_direction, 0)
	elif check_movable(0, input_y_direction):
		move_player(0, input_y_direction)
	else:
		if input_y_direction > 0:
			nail_player()
			new_player()

	# now that gravity has done its job, we can turn it off
	if gravity_called:
		input_y_direction = 0
		gravity_called = false

func check_movable(x, y):
	# x is side to side motion.  -1 = left   1 = right
	if x == -1 or x == 1:
		# check border
		if player_position.x + x >= Helpers.slots_across or player_position.x + x < 0:
			return false
		# check collision
		if Helpers.board[Vector2(player_position.x+x, player_position.y)] != null:
			return false
		return true
	# y is up down motion.  1 = down     -1 = up, but key is not connected
	if y == -1 or y == 1:
		# check border
		if player_position.y + y >= Helpers.slots_down or player_position.y + y < 0:
			return false
		if Helpers.board[Vector2(player_position.x, player_position.y+1)] != null:
			return false
		return true

func stop_moving():
	input_x_direction = 0
	input_y_direction = 0

func _gravity_says_its_time():
	gravity_called = true

func start_gravity_timer():
	var le_timer = get_node("GravityTimer")
	le_timer.set_wait_time(GRAVITY_TIMEOUT)
	le_timer.start()

func stop_gravity_timer():
	var le_timer = get_node("GravityTimer")
	le_timer.stop()

func start_level_timer():
	var le_timer = get_node("LevelTimer")
	le_timer.set_wait_time(current_level.time_limit_in_sec)
	le_timer.start()

func stop_level_timer():
	var le_timer = get_node("LevelTimer")
	le_timer.stop()

func start_magnetism():
	var magneto = get_node("Magnetism")
	magneto.set_wait_time(MAGNETISM_TIME)
	magneto.start()

func stop_magnetism():
	var magneto = get_node("Magnetism")
	magneto.stop()

# move player
func move_player(x, y):
	player_position.x += x
	player_position.y += y
	player.set_player_position(player_position)

# nail player to board
func nail_player():
	set_process(false)			# disable motion until next player is created
	set_process_input(false)	# ignore touches until next player is created
	stop_gravity_timer()
	player.nail_player()		# let player do what it needs when it's nailed

	# tell board{} where the player is
	Helpers.board[Vector2(player_position.x, player_position.y)] = player		## this is the piece so we can find it later

func piece_clicked(position, piece_type):
	var swipe_length = swipe_array.size()
	if swipe_length == 1:
		# probably a duplicate click
		return
	clicked_this_piece_type = piece_type
	VisibleSwipeOverlay.set_swipe_color(TileDatabase.tiles[piece_type].ITEM_COLOR)
	swipe_mode = true
	swipe_array.append(position)
	Helpers.board[position].highlight()

func piece_unclicked():
	# make sure the swipe is long enough to count (per level basis)
	if swipe_array.size() < current_level.min_swipe_len:
		for pos in swipe_array:
			Helpers.board[pos].unhighlight()
	# the swipe is long enough
	else:
		if Helpers.debug_level > 0:
			ShapeShifter.givenSwipe_showArray(swipe_array)
		var swipe_name = ShapeShifter.givenSwipe_lookupName(swipe_array)

		var dimensions = ShapeShifter.getSwipeDimensions(swipe_array)
		# figure out if the swipe is required
		var swipe_was_required = level_reqs.swiped_piece(swipe_name)

		swipe_shape = SwipeShape.instance()
		swipe_shape.set_shape(ShapeShifter.getBitmapOfSwipeCoordinates(swipe_array),clicked_this_piece_type)
		swipe_shape.set_position(Helpers.slot_to_pixels(dimensions["topleft"], 1, false))		# change false to true to debug position. 1 is xfactor (larger pushes to right and fucks shit up)
		add_child(swipe_shape)
		if swipe_was_required:
			swipe_shape.connect("shrunk_shape",self,"shrank_required_shape")
			# after swipe, move shape to correct/required shape location
			swipe_shape.shrink_shape(level_reqs.required_swipe_location(swipe_name))
		else:
			swipe_shape.connect("flew_away", self, "inc_wasted_swipe_counter")
			swipe_shape.fly_away_randomly()
			self.wasted_swipes = self.wasted_swipes + 1
		# TODO add animation swipe_shape.animate()
		for pos in swipe_array:
			if Helpers.board[pos] != null:
				Helpers.board[pos].unhighlight()  # restore color so the effect is pretty.  Only needed while the highlight is black
				Helpers.board[pos].remove_yourself()
	swipe_array.clear()
	swipe_mode = false

func inc_wasted_swipe_counter():
	print("wasted this many swipes: ", self.wasted_swipes)		# should be displayed on screen
	print("Add a coutner for that number on the screen")
	HUD.get_node('WastedSwipeCount').set_value(self.wasted_swipes)

func piece_entered(position, piece_type):
	if not swipe_mode:
		return
	if clicked_this_piece_type != piece_type:
		return
	# ensure the position is adjacent to the last item in the array
	if not adjacent(swipe_array.back(), position):
		return
	if position == swipe_array[swipe_array.size()-2]:
		# we back tracked
		var old_last = swipe_array.back()
		swipe_array.pop_back()
		Helpers.board[old_last].unhighlight()
	else:
		swipe_array.append(position)
		Helpers.board[position].highlight()
	VisibleSwipeOverlay.draw_this_swipe(swipe_array,TileDatabase.tiles[piece_type].ITEM_COLOR)

func adjacent(pos1, pos2):
	# https://www.gamedev.net/forums/topic/516685-best-algorithm-to-find-adjacent-tiles/?tab=comments#comment-4359055
	var xOffsets = [ 0, 1, 0, -1]
	var yOffsets = [-1, 0, 1,  0]

	var i = 0
	var offset_pos2 = Vector2(-99,-99)
	while i < xOffsets.size():
		offset_pos2 = Vector2(pos2.x + xOffsets[i], pos2.y + yOffsets[i])
		if pos1 == offset_pos2:
			return true
		i = i + 1
	return false

func piece_exited(position, piece_type):
	# mouse moved out of a tile
	# but we only care if it moved into a tile
	pass

func shrank_required_shape():
	swipe_shape.queue_free()
	level_reqs.clarify_requirements()

func _on_LevelWon():
	_level_over_prep(G.LEVEL_WIN)

func _on_LevelTimer_timeout():
	_level_over_prep(G.LEVEL_NO_TIME)
