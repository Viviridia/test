/datum/buildmode_mode/mapgen
	key = "mapgen"

	use_corner_selection = TRUE
	var/generator_path

/datum/buildmode_mode/mapgen/show_help(client/c)
	to_chat(c, "<span class='notice'>***********************************************************</span>")
	to_chat(c, "<span class='notice'>Left Mouse Button on turf/obj/mob      = Select corner</span>")
	to_chat(c, "<span class='notice'>Right Mouse Button on buildmode button = Select generator</span>")
	to_chat(c, "<span class='notice'>***********************************************************</span>")

/datum/buildmode_mode/mapgen/change_settings(client/c)
	var/list/gen_paths = subtypesof(/datum/mapGenerator)
	var/list/options = list()
	for(var/datum/mapGenerator/MP as anything in gen_paths)
		options[initial(MP.buildmode_name)] = MP
	var/type = input(c,"Select Generator Type","Type") as null|anything in options
	if(!type)
		return

	generator_path = options[type]
	deselect_region()

/datum/buildmode_mode/mapgen/handle_click(client/c, params, obj/object)
	if(isnull(generator_path))
		to_chat(c, "<span class='warning'>Select generator type first.</span>")
		deselect_region()
		return
	..()

/datum/buildmode_mode/mapgen/handle_selected_area(client/c, params)
	var/list/modifiers = params2list(params)
	var/left_click = LAZYACCESS(modifiers, LEFT_CLICK)

	if(left_click)
		var/datum/mapGenerator/G = new generator_path
		G.defineRegion(cornerA, cornerB, 1)
		highlight_region(G.map)
		var/confirm = alert("Are you sure you want to run the map generator?", "Run generator", "Yes", "No")
		if(confirm == "Yes")
			G.generate()
		log_admin("Build Mode: [key_name(c)] ran the map generator '[G.buildmode_name]' in the region from [AREACOORD(cornerA)] to [AREACOORD(cornerB)]")
