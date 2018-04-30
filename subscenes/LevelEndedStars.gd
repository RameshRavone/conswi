extends Node2D

var game_scene

#######################################################
#
#   So  when finished, we know who we're gonna call
func set_game_scene(my_game_scene):
	game_scene = my_game_scene

func _ready():
	# Called every time the node is added to the scene.
	# Initialization here
	pass

#######################################################
#
#  	This will be public to the GD star_display.gd
func star_display_show_end_level(info_for_star_calculation, level_num): # maybe level_num should be in info_for_star_calculation, but it still needs to go to next function
	_calculate_stars_for_level(info_for_star_calculation, level_num)
	var game = self			# when star_display and therefore this function is in different .gd, it will need to call game
	self.game_scene._on_level_over_stars_displayed()		# fake signal emitted by star_display.gd

#######################################################
#
#  	This will be private to the GD star_display.gd
func _calculate_stars_for_level(info_for_star_calculation, level_num):
	var existing_sprites = get_tree().get_nodes_in_group("players")
	var num_stars = randi()%3+1
	print("remaining pieces: ", existing_sprites.size())
	Savior.save_num_stars(G.TYPE_DOG, level_num, num_stars)
