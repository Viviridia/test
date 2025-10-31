// These do not all confirm to spell standards but if someone wants to go through all 60 odd of these and add proper
// Valid target / Can cast then be my guest
/datum/action/cooldown/spell/essence
	name = "Utility Spell"
	desc = "A minor utility spell."
	school = "utility"
	spell_cost = 5
	charge_drain = 0
	charge_required = FALSE
	cooldown_time = 30 SECONDS
	point_cost = 2
	spell_type = SPELL_ESSENCE
	experience_modifer = 0
	associated_skill = /datum/skill/craft/alchemy

/datum/action/cooldown/spell/essence/get_adjusted_charge_time()
	return charge_time

/datum/action/cooldown/spell/essence/get_adjusted_cost(cost_override)
	if(cost_override)
		return cost_override
	return spell_cost

/obj/effect/temp_visual/snake_base
	icon = 'icons/effects/effects.dmi'
	vis_flags = NONE
	plane = GAME_PLANE_UPPER
	layer = ABOVE_ALL_MOB_LAYER
	mouse_opacity = MOUSE_OPACITY_TRANSPARENT
	duration = 1.5 SECONDS
	var/datum/weakref/mob

/obj/effect/temp_visual/snake_base/Initialize(mapload, mob/target_mob)
	. = ..()
	mob = WEAKREF(target_mob)
	overlays += emissive_appearance(icon, icon_state, alpha = src.alpha)
	if(mob)
		var/mob/holder = mob.resolve()
		if(holder)
			holder.vis_contents += src
			loc = null

/obj/effect/temp_visual/snake_base/Destroy(force)
	if(mob)
		var/mob/holder = mob.resolve()
		if(holder)
			holder.vis_contents -= src
		mob = null
	return ..()

/obj/effect/temp_visual/twinsnake_up
	parent_type = /obj/effect/temp_visual/snake_base
	icon_state = "twinsnake"

/obj/effect/temp_visual/snakeswarm
	parent_type = /obj/effect/temp_visual/snake_base
	icon_state = "snakeswarm"
