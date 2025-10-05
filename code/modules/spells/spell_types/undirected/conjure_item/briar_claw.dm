/datum/action/cooldown/spell/undirected/conjure_item/briar_claw
	name = "Briar Claw"
	desc = "Turns one hand into a wolf's claw."
	button_icon_state = "dendor"
	invocation = "Beast-Lord, lend me the claws of a volf."
	invocation_type = INVOCATION_WHISPER
	spell_type = SPELL_MIRACLE
	antimagic_flags = MAGIC_RESISTANCE_HOLY
	associated_skill = /datum/skill/magic/holy
	required_items = list(/obj/item/clothing/neck/psycross/silver/dendor)
	spell_cost = 15
	item_duration = 1 MINUTES
	cooldown_time = 4 MINUTES
	item_type = /obj/item/weapon/briar_claw/left
	uses_component = TRUE
	refresh_count = 0
	attunements = list(
		/datum/attunement/blood = 0.3,
		/datum/attunement/earth = 0.7
	)

/datum/action/cooldown/spell/undirected/conjure_item/briar_claw/make_item()
	var/mob/living/carbon/M = owner
	if(!M)
		return
	var/obj/item/weapon/briar_claw/claw
	if(M.active_hand_index == 1)
		claw = new /obj/item/weapon/briar_claw/left()
	else
		claw = new /obj/item/weapon/briar_claw/right()
	LAZYADD(item_refs, WEAKREF(claw))
	claw.AddComponent(/datum/component/conjured_item, item_duration, associated_skill, skill_threshold)
	playsound(M, 'sound/ambience/noises/werewolf_howl1_01.ogg', 70, TRUE)
	return claw

/obj/item/weapon/briar_claw
	parent_type = /obj/item/weapon/werewolf_claw
	name = "briar claw"
	desc = "A volf's claw."
	force = 15
	wdefense = 1
	armor_penetration = 7
	max_blade_int = 700
	max_integrity = 700

/obj/item/weapon/briar_claw/Initialize()
	. = ..()
	ADD_TRAIT(src, TRAIT_NODROP, TRAIT_GENERIC)
	ADD_TRAIT(src, TRAIT_NOEMBED, TRAIT_GENERIC)

/obj/item/weapon/briar_claw/right
	icon_state = "claw_r"

/obj/item/weapon/briar_claw/left
	icon_state = "claw_l"

