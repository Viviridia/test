/**
 * Find a compatible, living partner, if we're also alone.
 */
/datum/ai_behavior/find_partner
	/// Range to look.
	var/range = 7
	/// Maximum number of children
	var/max_children = 3

/datum/ai_behavior/find_partner/perform(seconds_per_tick, datum/ai_controller/controller, target_key, partner_types_key, child_types_key)
	. = ..()
	max_children = controller.blackboard[BB_MAX_CHILDREN] || max_children
	var/mob/pawn_mob = controller.pawn
	var/list/partner_types = controller.blackboard[partner_types_key]
	var/list/child_types = controller.blackboard[child_types_key]
	var/mob/living/living_pawn = controller.pawn

	var/children = 0
	for(var/mob/living/other in oview(range, pawn_mob))

		if(children >= max_children)
			finish_action(controller, FALSE)
			return

		if(other.stat != CONSCIOUS) //Check if it's conscious FIRST.
			continue

		if(is_type_in_list(other, child_types)) //Check for children SECOND.
			children++
			continue

		if(!is_type_in_list(other, partner_types) || !HAS_TRAIT(other, TRAIT_MOB_BREEDER))
			continue

		if(other.ckey)
			continue

		if(!other.ai_controller?.blackboard[BB_BREED_READY])
			continue

		if(isanimal(other))
			var/mob/living/simple_animal/other_animal = other
			if(other_animal.food < other_animal.food_max * 0.15)
				continue

		if(other.gender != living_pawn.gender && !(other.flags_1 & HOLOGRAM_1)) //Better safe than sorry ;_;
			controller.set_blackboard_key(target_key, other)
			finish_action(controller, TRUE)
			return

	finish_action(controller, FALSE)


/**
 * Reproduce.
 */
/datum/ai_behavior/make_babies
	behavior_flags = AI_BEHAVIOR_REQUIRE_MOVEMENT | AI_BEHAVIOR_REQUIRE_REACH

/datum/ai_behavior/make_babies/setup(datum/ai_controller/controller, target_key, child_types_key)
	. = ..()
	var/atom/target = controller.blackboard[target_key]
	if(!target)
		return FALSE
	set_movement_target(controller, target)

/datum/ai_behavior/make_babies/perform(seconds_per_tick, datum/ai_controller/controller, target_key, child_types_key)
	. = ..()
	var/mob/target = controller.blackboard[target_key]
	if(QDELETED(target) || target.stat != CONSCIOUS)
		finish_action(controller, FALSE, target_key)
		return
	var/mob/living/simple_animal/hostile/living_pawn = controller.pawn
	//living_pawn.set_combat_mode(FALSE)
	living_pawn.cmode = FALSE
	living_pawn.AttackingTarget(target)
	finish_action(controller, TRUE, target_key)

/datum/ai_behavior/make_babies/finish_action(datum/ai_controller/controller, succeeded, target_key)
	. = ..()
	controller.clear_blackboard_key(target_key)
	if(!succeeded)
		return
	var/mob/living/living_pawn = controller.pawn
	if(QDELETED(living_pawn)) // pawn can be null at this point
		return
	living_pawn.cmode = initial(living_pawn.cmode)

