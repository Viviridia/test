GLOBAL_LIST_EMPTY(custom_fermentation_recipes)

/obj/structure/fermentation_keg
	name = "fermentation keg"
	desc = "A simple keg that is meant for making booze."

	icon = 'icons/obj/brewing.dmi'
	icon_state = "barrel_tapless"

	density = TRUE
	anchored = FALSE

	/// The sound of fermentation
	var/datum/looping_sound/boiling/soundloop
	/// The volume of the barrel sounds
	var/sound_volume = 25
	var/open_icon_state = "barrel_tapless_open"
	var/tapped_icon_state = "barrel_tapped_ready"

	//After brewing we can sell or bottle, this is for the latter
	var/ready_to_bottle = FALSE
	var/brewing = FALSE

	///our currently needed crops
	var/list/recipe_crop_stocks
	///our currently selected recipe
	var/datum/brewing_recipe/selected_recipe
	///our made item which we clear once its no longer ready to bottle
	var/made_item

	var/age_start_time = 0

	var/tapped = FALSE

	var/selecting_recipe = FALSE

	var/heated = FALSE
	///machines heat in kelvin
	var/heat = 300
	///our start_time
	var/start_time
	///our brew progress time
	var/heated_progress_time
	///when our heat can decay
	var/heat_decay = 0

/obj/structure/fermentation_keg/Initialize()
	. = ..()
	create_reagents(900, NO_REACT | AMOUNT_VISIBLE | REFILLABLE | DRAINABLE) //on agv it should be 120u for water then rest can be other needed chemicals
	recipe_crop_stocks = list()

	soundloop = new(src, brewing)
	soundloop.volume = sound_volume

	if(heated)
		START_PROCESSING(SSobj, src)

/obj/structure/fermentation_keg/Destroy()
	if(soundloop)
		QDEL_NULL(soundloop)
	if(selected_recipe)
		QDEL_NULL(selected_recipe)
	recipe_crop_stocks.Cut()
	return ..()

/obj/structure/fermentation_keg/update_overlays()
	. = ..()
	if(!reagents?.total_volume)
		return

	if(icon_state != open_icon_state)
		return
	var/used_alpha = mix_alpha_from_reagents(reagents.reagent_list)
	. += mutable_appearance(
		icon,
		"filling",
		color = mix_color_from_reagents(reagents.reagent_list),
		alpha = used_alpha,
	)
	var/datum/reagent/master = reagents.get_master_reagent()
	if(master?.glows)
		. += emissive_appearance(icon, "filling", alpha = used_alpha)

/obj/structure/fermentation_keg/attack_hand_secondary(mob/user, params)
	. = ..()
	if(. == SECONDARY_ATTACK_CANCEL_ATTACK_CHAIN)
		return
	if(!ready_to_bottle && selected_recipe && !brewing)
		user.visible_message("[user] starts emptying out [src].", "You start emptying out [src].")
		if(!do_after(user, 5 SECONDS, src))
			return SECONDARY_ATTACK_CANCEL_ATTACK_CHAIN
		clear_keg(TRUE)
		return SECONDARY_ATTACK_CANCEL_ATTACK_CHAIN

	if(!brewing && (!selected_recipe || ready_to_bottle))
		if(!shopping_run(user))
			return SECONDARY_ATTACK_CANCEL_ATTACK_CHAIN

/obj/structure/fermentation_keg/AltClick(mob/user)
	. = ..()
	if(!user.Adjacent(src))
		return

	if(!brewing && ready_to_bottle)
		if(try_tapping(user))
			return

/obj/structure/fermentation_keg/attack_hand(mob/user)
	if((user.used_intent == /datum/intent/grab) || user.cmode)
		return ..()
	if(!selected_recipe)
		to_chat(user, span_warning("No recipe has been set yet!"))
		return ..()

	if(try_n_brew(user))
		start_brew()
		to_chat(user, span_info("[src] begins brewing [selected_recipe.name]."))
	..()

/obj/structure/fermentation_keg/attackby(obj/item/I, mob/user)
	if(istype(I, /obj/item/reagent_containers) && tapped && (user.used_intent.type == /datum/intent/fill))
		if(try_filling(user, I))
			return

	if(heated)
		if(istype(I, /obj/item/ore/coal) || istype(I, /obj/item/grown/log/tree))
			refuel(I, user)
			return

	if(ready_to_bottle)
		if(selected_recipe.after_finish_attackby(user, I, src))
			create_items()
			return

	var/list/produce_list = list()
	var/list/storage_list = list()

	if(I.type in selected_recipe?.needed_items)
		produce_list |= I

	if(I.type in selected_recipe?.needed_crops)
		produce_list |= I

	if(istype(I, /obj/item/storage))
		produce_list |= I.contents
		storage_list |= I.contents

	var/dumps = FALSE
	for(var/obj/item/reagent_containers/food/G in produce_list)
		if(G.type in selected_recipe?.needed_crops)
			if(recipe_crop_stocks[G.type] >= selected_recipe?.needed_crops[G.type])
				continue
			recipe_crop_stocks[G.type]++
			if(G in storage_list)
				dumps = TRUE
				SEND_SIGNAL(G.loc, COMSIG_TRY_STORAGE_TAKE, G, get_turf(src), TRUE)
			qdel(G)

	for(var/obj/item/item in produce_list)
		if(item.type in selected_recipe?.needed_items)
			if(recipe_crop_stocks[item.type] >= selected_recipe?.needed_items[item.type])
				continue
			var/amount = recipe_crop_stocks[item.type] || 0
			var/added_item = 1
			recipe_crop_stocks[item.type] = amount + added_item
			if(item in storage_list)
				dumps = TRUE
				SEND_SIGNAL(item.loc, COMSIG_TRY_STORAGE_TAKE, item, get_turf(src), TRUE)
			qdel(item)

	if(dumps)
		user.visible_message("[user] dumps some things into [src].", "You dump some things into [src].")

	. = ..()
	update_appearance(UPDATE_OVERLAYS)

/obj/structure/fermentation_keg/examine(mob/user)
	. =..()
	if(heated)
		. += "Internal Temperature of around [heat - 271.3]C."
	if(ready_to_bottle)
		. += span_boldnotice("[made_item]")
		if(age_start_time)
			. += "Aged for [(world.time - age_start_time) * 0.1] Seconds.\n"
		if(!tapped)
			. += span_blue("Alt-Click on the Barrel to Tap it.")

	else if(selected_recipe)
		var/message = "Currently making: [selected_recipe.name].\n"

		//time
		if(selected_recipe.brew_time)
			var/multiplier = 1
			if(heated && !selected_recipe.heat_required)
				multiplier = 0.5
			if((selected_recipe.brew_time * multiplier) >= 1 MINUTES)
				message += "Once set, will take [(selected_recipe.brew_time / 600) * multiplier] Minutes.\n"
			else
				message += "Once set, will take [(selected_recipe.brew_time / 10) & multiplier] Seconds.\n"

		//How many are brewed
		if(selected_recipe.brewed_amount)
			message += "Will produce [selected_recipe.brewed_amount] bottles when finished or [FLOOR((selected_recipe.brewed_amount * selected_recipe.per_brew_amount)/ 3 , 1)] oz.\n"

		if(selected_recipe.brewed_item && selected_recipe.brewed_item_count)
			var/name_to_use = selected_recipe.secondary_name
			if(!name_to_use)
				name_to_use = selected_recipe.name
			message += "Will produce [name_to_use] x [selected_recipe.brewed_item_count] when finished.\n"

		if(selected_recipe.helpful_hints)
			message += "[selected_recipe.helpful_hints].\n"

		. += span_blue("Right-Click on the Barrel to clear it.")
		/*
		if(istype(selected_recipe, /datum/brewing_recipe/custom_recipe))
			var/datum/brewing_recipe/custom_recipe/recipe = selected_recipe
			message += "Recipe Created By:[recipe.made_by]"
		. += message
		*/
		. += message
	else
		. += span_blue("Right-Click on the Barrel to select a recipe.")


/obj/structure/fermentation_keg/proc/get_prereq_amount(datum/reagent/reagent)
	var/static/list/reagent_list = list()
	if(!length(reagent_list))
		for(var/datum/brewing_recipe/recipe as anything in subtypesof(/datum/brewing_recipe))
			reagent_list |= recipe.reagent_to_brew
			reagent_list[recipe.reagent_to_brew] = recipe.per_brew_amount * recipe.brewed_amount
	if(reagent in reagent_list)
		return reagent_list[reagent]
	return 0

/obj/structure/fermentation_keg/proc/shopping_run(mob/user)
	if(brewing)
		return
	if(selecting_recipe)
		return
	selecting_recipe = TRUE
	addtimer(VARSET_CALLBACK(src, selecting_recipe, FALSE), 5 SECONDS)

	var/list/options = list()
	for(var/path in subtypesof(/datum/brewing_recipe))
		var/datum/brewing_recipe/recipe = path
		var/datum/reagent/prereq = initial(recipe.pre_reqs)
		if(!heated && initial(recipe.heat_required))
			continue

		if((prereq == null) || (reagents.has_reagent(prereq, get_prereq_amount(prereq))))
			options[initial(recipe.name)] = recipe


	for(var/datum/brewing_recipe/recipe in GLOB.custom_fermentation_recipes)
		var/prereq = recipe.pre_reqs
		if((!ready_to_bottle && prereq == null) || (selected_recipe?.reagent_to_brew == prereq && ready_to_bottle))
			options[recipe.name] = recipe

	if(options.len == 0)
		return

	var/choice = input(user,"What brew do you want to make?", name) as null|anything in options

	if(!choice)
		return

	var/choice_to_spawn = options[choice]

	/*
	if(istype(choice_to_spawn, /datum/brewing_recipe/custom_recipe))
		selected_recipe = choice_to_spawn
	else
		selected_recipe = new choice_to_spawn
	*/
	selected_recipe = new choice_to_spawn
	selecting_recipe = FALSE

	//Second stage brewing gives no refunds! - This is intented design to help make it so folks dont quit halfway through and still get a rebate
	ready_to_bottle = FALSE
	sellprice = 25
	if(open_icon_state)
		icon_state = open_icon_state
	update_appearance(UPDATE_OVERLAYS)
	return TRUE

//Remove only chemicals
/obj/structure/fermentation_keg/proc/clear_keg_reagents()
	if(reagents)
		//consume consume consume consume
		reagents.clear_reagents()

//Remove and reset
/obj/structure/fermentation_keg/proc/clear_keg(force = FALSE)
	if(brewing)
		return FALSE

	if(!force && ready_to_bottle)
		return FALSE

	if(reagents)
		reagents.clear_reagents()

	ready_to_bottle = FALSE
	made_item = null
	if(open_icon_state)
		icon_state = open_icon_state
	update_appearance(UPDATE_OVERLAYS)

	recipe_crop_stocks.Cut()
	age_start_time = 0
	start_time = 0

	sellprice = 25
	tapped = FALSE

	if(force)
		selected_recipe = null

	return TRUE

/obj/structure/fermentation_keg/proc/start_brew()
	brewing = TRUE

	for(var/obj/item/reagent_containers/food/item as anything in selected_recipe.needed_crops)
		if(!(item in recipe_crop_stocks))
			return
		var/amount = recipe_crop_stocks[item] || 0
		recipe_crop_stocks[item] = amount - selected_recipe.needed_crops[item]

	for(var/obj/item/item as anything in selected_recipe.needed_items)
		if(!(item in recipe_crop_stocks))
			return
		var/amount = recipe_crop_stocks[item] || 0
		recipe_crop_stocks[item] = amount - selected_recipe.needed_items[item]

	clear_keg_reagents()

	soundloop.start()
	if(!heated)
		addtimer(CALLBACK(src, PROC_REF(end_brew)), selected_recipe.brew_time)
	if(heated && !selected_recipe.heat_required)
		addtimer(CALLBACK(src, PROC_REF(end_brew)), selected_recipe.brew_time * 0.5)
	icon_state = initial(icon_state)
	start_time = world.time
	update_appearance(UPDATE_OVERLAYS)

/obj/structure/fermentation_keg/proc/end_brew()
	if(!heated)
		icon_state = "barrel_tapless_ready"
	update_appearance(UPDATE_OVERLAYS)
	soundloop.stop()
	ready_to_bottle = TRUE
	brewing = FALSE
	sellprice = selected_recipe.sell_value
	made_item = selected_recipe.name
	reagents.add_reagent(selected_recipe.reagent_to_brew, selected_recipe.brewed_amount * selected_recipe.per_brew_amount)

	start_time = 0
	heated_progress_time = 0
	if(selected_recipe.ages)
		age_start_time = world.time

/obj/structure/fermentation_keg/proc/try_n_brew(mob/user)
	var/ready = TRUE
	if(!selected_recipe)
		if(user)
			to_chat(user, span_notice("You need to set a booze to brew!"))
		ready = FALSE

	if(brewing)
		if(user)
			to_chat(user, span_notice("This keg is already brewing a mix!"))
		ready = FALSE
		return ready

	//Crops
	for(var/obj/item/reagent_containers/food/needed_crop as anything in selected_recipe.needed_crops)
		if(recipe_crop_stocks[needed_crop] < selected_recipe.needed_crops[needed_crop])
			if(user)
				to_chat(user, span_notice("This keg lacks [initial(needed_crop.name)]!"))
				ready = FALSE

	for(var/obj/item/needed_item as anything in selected_recipe.needed_items)
		if(recipe_crop_stocks[needed_item] < selected_recipe.needed_items[needed_item])
			if(user)
				to_chat(user, span_notice("This keg lacks [initial(needed_item.name)]!"))
				ready = FALSE

	for(var/datum/reagent/required_chem as anything in selected_recipe.needed_reagents)
		if(selected_recipe.needed_reagents[required_chem] > reagents.get_reagent_amount(required_chem))
			if(user)
				to_chat(user, span_notice("The keg's unable to brew well lacking [initial(required_chem.name)]!"))
				ready = FALSE

	return ready

/obj/structure/fermentation_keg/proc/refuel(obj/item/item, mob/user)
	user.visible_message("[user] starts refueling [src].", "You start refueling [src].")
	if(!do_after(user, 1.5 SECONDS, src))
		return
	var/burn_time = 4 MINUTES
	var/burn_temp = 300
	if(istype(item, /obj/item/ore/coal))
		burn_time *= 1.5
		burn_temp *= 1.5

	heat_decay = world.time + burn_time
	heat = min(1000, burn_temp + heat)
	qdel(item)

/obj/structure/fermentation_keg/random/water
	name = "water barrel"

/obj/structure/fermentation_keg/random/water/Initialize()
	. = ..()
	reagents.add_reagent(/datum/reagent/water, rand(0,900))


/obj/structure/fermentation_keg/random/beer/Initialize()
	. = ..()
	reagents.add_reagent(/datum/reagent/consumable/ethanol/beer, rand(0,900))

/obj/structure/fermentation_keg/water
	name = "water barrel"

/obj/structure/fermentation_keg/water/Initialize()
	. = ..()
	reagents.add_reagent(/datum/reagent/water,900)

/obj/structure/fermentation_keg/beer/Initialize()
	. = ..()
	reagents.add_reagent(/datum/reagent/consumable/ethanol/beer,900)

/obj/structure/fermentation_keg/proc/create_items()
	if(!ready_to_bottle)
		return

	ready_to_bottle = FALSE
	made_item = null
	tapped = FALSE
	age_start_time = 0
	brewing = FALSE
	sellprice = 25
	heated_progress_time = 0
	start_time = 0
	if(open_icon_state)
		icon_state = open_icon_state
	update_appearance(UPDATE_OVERLAYS)

	if(selected_recipe.brewed_item)
		var/items_given
		for(items_given= 0, items_given < selected_recipe.brewed_item_count, items_given++)
			new selected_recipe.brewed_item(get_turf(src))
	selected_recipe = null

/obj/structure/fermentation_keg/proc/try_tapping(mob/user)
	if(tapped)
		return
	visible_message("[user] starts tapping [src].", "You start tapping [src].")
	if(!do_after(user, 4 SECONDS, src))
		return
	tapped = TRUE
	if(tapped_icon_state)
		icon_state = tapped_icon_state
	sellprice = 0

/obj/structure/fermentation_keg/proc/try_filling(mob/user, obj/item/reagent_containers/container)
	if(!tapped || !reagents.total_volume)
		return FALSE

	visible_message("[user] starts pouring from [src].", "You start pouring from [src].")
	if(!do_after(user, 1 SECONDS, src))
		return FALSE

	var/datum/reagent/brewed_reagent = selected_recipe.reagent_to_brew
	if(selected_recipe.ages)
		var/time = world.time - age_start_time
		for(var/path in selected_recipe.age_times)
			if(time > selected_recipe.age_times[path])
				brewed_reagent = path

	var/transfer_amount = min(container.reagents.maximum_volume - container.reagents.total_volume, reagents.get_reagent_amount(brewed_reagent))
	if(transfer_amount > 0)
		reagents.trans_id_to(container, brewed_reagent, transfer_amount)
		return TRUE
	return FALSE

/obj/structure/fermentation_keg/process()
	if(accepts_water_input && input && selected_recipe && !brewing && !ready_to_bottle)
		var/datum/reagent/incoming_reagent = input.carrying_reagent
		if((incoming_reagent in selected_recipe.needed_reagents))
			var/datum/reagent/reagent = reagents.get_reagent(incoming_reagent)
			var/reagents_needed = selected_recipe.needed_reagents[incoming_reagent]
			reagents_needed -= reagent?.volume

			var/transfer_amount = min(input.water_pressure, reagents_needed)
			reagents.add_reagent(incoming_reagent, transfer_amount)


	if(brewing && selected_recipe.heat_required)
		var/end_time = world.time + (selected_recipe.brew_time - heated_progress_time)
		if(world.time > end_time)
			end_brew()
		if((heat > selected_recipe.heat_required))
			heated_progress_time += world.time - start_time
		start_time = world.time

	if(heat_decay < world.time)
		heat = max(300, heat-5)


/obj/item/reagent_containers/glass/bottle/brewing_bottle
	name = "bottle"
	desc = "A bottle with a cork."
	icon =  'icons/obj/bottle.dmi'
	icon_state = "brew_bottle"
	volume = 50
	can_label_bottle = FALSE

	var/glass_name
	var/glass_desc

/obj/item/reagent_containers/glass/bottle/brewing_bottle/afterattack(atom/target, mob/user, proximity_flag, click_parameters)
	. = ..()
	if(target.type in (typesof(/obj/item/reagent_containers/glass) - typesof(/obj/item/reagent_containers/glass/bottle)))
		if(glass_name)
			target.name = glass_name
		if(glass_desc)
			target.desc = glass_desc
	if(reagents.total_volume <= 0)
		glass_desc = null
		glass_name = null

/obj/structure/fermentation_keg/MouseDrop_T(atom/over, mob/living/user)
	if(!istype(over, /obj/structure/fermentation_keg))
		return
	if(!Adjacent(over))
		return
	if(!Adjacent(user))
		return
	var/obj/structure/fermentation_keg/keg = over
	if(selected_recipe)
		if(keg.tapped)
			if(!(keg.selected_recipe.reagent_to_brew in selected_recipe.needed_reagents))
				return

			var/datum/reagent/reagent = reagents.get_reagent(keg.selected_recipe.reagent_to_brew)
			var/reagents_needed = selected_recipe.needed_reagents[keg.selected_recipe.reagent_to_brew]
			reagents_needed -= reagent?.volume

			if(!reagents_needed)
				return

			var/transfer_amount = min(reagents.maximum_volume - reagents.total_volume, keg.reagents.total_volume)

			user.visible_message("[user] starts to pour [keg] into [src]." , "You start to pour [keg] in [src].")
			if(!do_after(user, 5 SECONDS, keg))
				return
			reagents.add_reagent(selected_recipe.reagent_to_brew, transfer_amount)
			if(!keg.reagents.total_volume)
				keg.clear_keg(TRUE)

		else
			for(var/datum/reagent/reagent in keg.reagents.reagent_list)
				if(!(reagent.type in selected_recipe.needed_reagents))
					continue
				var/datum/reagent/keg_reagent = reagents.get_reagent(reagent.type)
				var/reagents_needed = selected_recipe.needed_reagents[reagent.type]
				reagents_needed -= keg_reagent?.volume
				if(!reagents_needed)
					return

				var/transfer_amount = min(reagents_needed, reagent.volume)
				user.visible_message("[user] starts to pour [keg] into [src]." , "You start to pour [keg] in [src].")
				if(!do_after(user, 5 SECONDS, keg))
					return
				reagents.add_reagent(reagent.type, transfer_amount)
				keg.reagents.remove_reagent(reagent.type, transfer_amount)
	else
		if(!keg.tapped)
			return
		user.visible_message("[user] starts to pour [keg] into [src]." , "You start to pour [keg] in [src].")
		if(!do_after(user, 5 SECONDS, keg))
			return
		keg.reagents.trans_to(reagents, keg.reagents.total_volume)
		keg.clear_keg(TRUE)

/obj/structure/fermentation_keg/distiller
	name = "copper distiller"

	icon = 'icons/obj/distillery.dmi'
	icon_state = "distillery"
	tapped_icon_state = null
	open_icon_state = null

	anchored = TRUE
	heated = TRUE

	accepts_water_input = TRUE

/obj/structure/fermentation_keg/distiller/valid_water_connection(direction, obj/structure/water_pipe/pipe)
	if(direction == SOUTH)
		input = pipe
		return TRUE
	return FALSE

/obj/structure/fermentation_keg/distiller/setup_water()
	var/turf/north_turf = get_step(src, NORTH)
	input = locate(/obj/structure/water_pipe) in north_turf

/obj/structure/fermentation_keg/distiller/return_rotation_chat(atom/movable/screen/movable/mouseover/mouseover)
	mouseover.maptext_height = 96
	if(!input)
		return {"<span style='font-size:8pt;font-family:"Pterra";color:#808000;text-shadow:0 0 1px #fff, 0 0 2px #fff, 0 0 30px #e60073, 0 0 40px #e60073, 0 0 50px #e60073, 0 0 60px #e60073, 0 0 70px #e60073;' class='center maptext '>
			NO INPUT"}

	return {"<span style='font-size:8pt;font-family:"Pterra";color:#808000;text-shadow:0 0 1px #fff, 0 0 2px #fff, 0 0 30px #e60073, 0 0 40px #e60073, 0 0 50px #e60073, 0 0 60px #e60073, 0 0 70px #e60073;' class='center maptext '>
			Pressure: [input.water_pressure]
			Fluid: [input.carrying_reagent ? initial(input.carrying_reagent.name) : "Nothing"]</span>"}
