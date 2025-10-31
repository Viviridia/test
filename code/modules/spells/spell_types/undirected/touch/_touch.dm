/**
 * ## Touch Spell
 *
 * Touch spells are spells which function through the power of an item attack.
 *
 * Instead of the spell triggering when the caster presses the button,
 * pressing the button will give them a hand object.
 * The spell's effects are cast when the hand object makes contact with something.
 *
 * To implement a touch spell, all you need is to implement:
 * * is_valid_target - to check whether the slapped target is valid
 * * cast_on_hand_hit - to implement effects on cast
 *
 * However, for added complexity, you can optionally implement:
 * * on_antimagic_triggered - to cause effects when antimagic is triggered
 * * cast_on_secondary_hand_hit - to implement different effects if the caster r-clicked
 * It is not necessarily to touch any of the core functions, and is
 * (generally) inadvisable unless you know what you're doing
 */
/datum/action/cooldown/spell/undirected/touch
	check_flags = AB_CHECK_CONSCIOUS|AB_CHECK_HANDS_BLOCKED
	charge_required = FALSE
	has_visual_effects = FALSE

	/// Typepath of what hand we create on initial cast.
	var/obj/item/melee/touch_attack/hand_path = /obj/item/melee/touch_attack
	/// Ref to the hand we currently have deployed.
	var/obj/item/melee/touch_attack/attached_hand
	/// The message displayed to the person upon creating the touch hand
	var/draw_message = span_notice("You channel the power of the spell to your hand.")
	/// The message displayed upon willingly dropping / deleting / cancelling the touch hand before using it
	var/drop_message = span_notice("You draw the power out of your hand.")
	/// If TRUE, the caster can willingly hit themselves with the hand
	var/can_cast_on_self = FALSE

	/// If the hand has charges
	var/infinite_use = FALSE
	/// Number of uses before the spell removes itself
	var/charges = 1

/datum/action/cooldown/spell/undirected/touch/Destroy()
	// If we have an owner, the hand is cleaned up in Remove(), which Destroy() calls.
	if(!owner)
		QDEL_NULL(attached_hand)
	return ..()

/datum/action/cooldown/spell/undirected/touch/Remove(mob/living/remove_from)
	remove_hand(remove_from)
	return ..()

// PreActivate is overridden to not check is_valid_target on the caster, as it makes less sense.
/datum/action/cooldown/spell/undirected/touch/PreActivate(atom/target)
	return Activate(target)

/datum/action/cooldown/spell/undirected/touch/is_action_active(atom/movable/screen/movable/action_button/current_button)
	return !!attached_hand

/datum/action/cooldown/spell/undirected/touch/can_cast_spell(feedback = TRUE)
	. = ..()
	if(!.)
		return FALSE
	if(!iscarbon(owner))
		return FALSE
	var/mob/living/carbon/carbon_owner = owner
	if(!(carbon_owner.mobility_flags & MOBILITY_USE))
		return FALSE
	return TRUE

/**
 * Creates a new hand_path hand and equips it to the caster.
 *
 * If the equipping action fails, reverts the cooldown and returns FALSE.
 * Otherwise, registers signals and returns TRUE.
 */
/datum/action/cooldown/spell/undirected/touch/proc/create_hand(mob/living/carbon/cast_on)
	SHOULD_CALL_PARENT(TRUE)
	charges = initial(charges)
	var/obj/item/melee/touch_attack/new_hand = new hand_path(cast_on, src)
	if(!cast_on.put_in_hands(new_hand, del_on_fail = TRUE))
		reset_spell_cooldown()
		if (cast_on.usable_hands == 0)
			to_chat(cast_on, span_warning("You dont have any usable hands!"))
		else
			to_chat(cast_on, span_warning("Your hands are full!"))
		return FALSE

	attached_hand = new_hand
	register_hand_signals()
	to_chat(cast_on, draw_message)
	return TRUE

/// Any handling for adjusting charges based on some factor should go here
/datum/action/cooldown/spell/undirected/touch/proc/adjust_hand_charges()
	return

/**
 * Unregisters any signals and deletes the hand currently summoned by the spell.
 *
 * If reset_cooldown_after is TRUE, we will additionally refund the cooldown of the spell.
 * If reset_cooldown_after is FALSE, we will instead just start the spell's cooldown
 */
/datum/action/cooldown/spell/undirected/touch/proc/remove_hand(mob/living/hand_owner, reset_cooldown_after = FALSE)
	if(!QDELETED(attached_hand))
		unregister_hand_signals()
		hand_owner?.temporarilyRemoveItemFromInventory(attached_hand)
		QDEL_NULL(attached_hand)
	attached_hand = null

	if(reset_cooldown_after)
		if(hand_owner)
			to_chat(hand_owner, drop_message)
		if(charges < initial(charges))
			StartCooldown(cooldown_time * (initial(charges) - charges))
		else
			reset_spell_cooldown()
	else
		StartCooldown()
		build_all_button_icons()

/// Registers all signal procs for the hand.
/datum/action/cooldown/spell/undirected/touch/proc/register_hand_signals()
	SHOULD_CALL_PARENT(TRUE)

	RegisterSignal(attached_hand, COMSIG_ITEM_AFTERATTACK, PROC_REF(on_hand_hit))
	RegisterSignal(attached_hand, COMSIG_PARENT_QDELETING, PROC_REF(on_hand_deleted))
	RegisterSignal(attached_hand, COMSIG_ITEM_DROPPED, PROC_REF(on_hand_dropped))

/// Unregisters all signal procs for the hand.
/datum/action/cooldown/spell/undirected/touch/proc/unregister_hand_signals()
	SHOULD_CALL_PARENT(TRUE)

	UnregisterSignal(attached_hand, list(
		COMSIG_ITEM_AFTERATTACK,
		COMSIG_PARENT_QDELETING,
		COMSIG_ITEM_DROPPED,
	))

// Touch spells don't go on cooldown OR give off an invocation until the hand is used itself.
/datum/action/cooldown/spell/undirected/touch/before_cast(atom/cast_on)
	return ..() | SPELL_NO_FEEDBACK | SPELL_NO_IMMEDIATE_COOLDOWN

/datum/action/cooldown/spell/undirected/touch/cast(mob/living/carbon/cast_on)
	if(!QDELETED(attached_hand) && (attached_hand in cast_on.held_items))
		remove_hand(cast_on, reset_cooldown_after = TRUE)
		return

	create_hand(cast_on)
	adjust_hand_charges()

	return ..()

/**
 * Signal proc for [COMSIG_ITEM_AFTERATTACK] from our attached hand.
 *
 * When our hand hits an atom, we can cast do_hand_hit() on them.
 */
/datum/action/cooldown/spell/undirected/touch/proc/on_hand_hit(datum/source, atom/victim, mob/caster, proximity_flag, click_parameters)
	SIGNAL_HANDLER
	SHOULD_NOT_OVERRIDE(TRUE) // DEFINITELY don't put effects here, put them in cast_on_hand_hit

	if(!proximity_flag || !can_hit_with_hand(victim, caster))
		return

	var/list/modifiers = params2list(click_parameters)
	if(LAZYACCESS(modifiers, RIGHT_CLICK))
		INVOKE_ASYNC(src, PROC_REF(do_secondary_hand_hit), source, victim, caster, modifiers)
	else
		INVOKE_ASYNC(src, PROC_REF(do_hand_hit), source, victim, caster, modifiers)
	return COMPONENT_CANCEL_ATTACK_CHAIN

/// Checks if the passed victim can be cast on by the caster.
/datum/action/cooldown/spell/undirected/touch/proc/can_hit_with_hand(atom/victim, mob/caster)
	if(!is_valid_target(victim))
		return FALSE
	if(!can_cast_spell(feedback = TRUE))
		return FALSE

	return TRUE

/**
 * Calls cast_on_hand_hit() from the caster onto the victim.
 * It's worth noting that victim will be guaranteed to be whatever checks are implemented in is_valid_target by this point.
 *
 * Implements checks for antimagic.
 */
/datum/action/cooldown/spell/undirected/touch/proc/do_hand_hit(obj/item/melee/touch_attack/hand, atom/victim, mob/living/carbon/caster, list/modifiers)
	SHOULD_NOT_OVERRIDE(TRUE) // Don't put effects here, put them in cast_on_hand_hit

	SEND_SIGNAL(src, COMSIG_SPELL_TOUCH_HAND_HIT, victim, caster, hand)
	var/mob/mob_victim = victim
	if(istype(mob_victim) && mob_victim.can_block_magic(antimagic_flags))
		on_antimagic_triggered(hand, victim, caster)

	else if(!cast_on_hand_hit(hand, victim, caster, modifiers))
		return

	log_combat(caster, victim, "cast the touch spell [name] on", hand)
	spell_feedback()
	if(!infinite_use)
		charges--
		if(charges <= 0)
			remove_hand(caster)

/**
 * Calls do_secondary_hand_hit() from the caster onto the victim.
 * It's worth noting that victim will be guaranteed to be whatever checks are implemented in is_valid_target by this point.
 * Does NOT check for antimagic on its own. Implement your own checks if you want the r-click to abide by it.
 */
/datum/action/cooldown/spell/undirected/touch/proc/do_secondary_hand_hit(obj/item/melee/touch_attack/hand, atom/victim, mob/living/carbon/caster, list/modifiers)
	SHOULD_NOT_OVERRIDE(TRUE) // Don't put effects here, put them in cast_on_secondary_hand_hit

	var/secondary_result = cast_on_secondary_hand_hit(hand, victim, caster, modifiers)
	switch(secondary_result)
		// Continue will remove the hand here and stop
		if(SECONDARY_ATTACK_CONTINUE_CHAIN)
			log_combat(caster, victim, "cast the touch spell [name] on", hand, "(secondary / alt cast)")
			spell_feedback()
			if(!infinite_use)
				charges--
				if(charges <= 0)
					remove_hand(caster)

		// Call normal will call the normal cast proc
		if(SECONDARY_ATTACK_CALL_NORMAL)
			do_hand_hit(hand, victim, caster)

		// Cancel chain will do nothing,
		if(SECONDARY_ATTACK_CANCEL_ATTACK_CHAIN)
			return

/**
 * The actual process of casting the spell on the victim from the caster.
 *
 * Override / extend this to implement casting effects.
 * Return TRUE on a successful cast to use up the hand (delete it)
 * Return FALSE to do nothing and let them keep the hand in hand
 */
/datum/action/cooldown/spell/undirected/touch/proc/cast_on_hand_hit(obj/item/melee/touch_attack/hand, atom/victim, mob/living/carbon/caster, list/modifiers)
	return FALSE

/**
 * For any special casting effects done if the user right-clicks
 * on touch spell instead of left-clicking
 *
 * Return SECONDARY_ATTACK_CALL_NORMAL to call the normal cast_on_hand_hit
 * Return SECONDARY_ATTACK_CONTINUE_CHAIN to prevent the normal cast_on_hand_hit from calling, but still use up the hand
 * Return SECONDARY_ATTACK_CANCEL_CHAIN to prevent the spell from being used
 */
/datum/action/cooldown/spell/undirected/touch/proc/cast_on_secondary_hand_hit(obj/item/melee/touch_attack/hand, atom/victim, mob/living/carbon/caster, list/modifiers)
	return SECONDARY_ATTACK_CALL_NORMAL

/**
 * Signal proc for [COMSIG_PARENT_QDELETING] from our attached hand.
 *
 * If our hand is deleted for a reason unrelated to our spell,
 * unlink it (clear refs) and revert the cooldown
 */
/datum/action/cooldown/spell/undirected/touch/proc/on_hand_deleted(datum/source)
	SIGNAL_HANDLER

	remove_hand(reset_cooldown_after = TRUE)

/**
 * Signal proc for [COMSIG_ITEM_DROPPED] from our attached hand.
 *
 * If our caster drops the hand, remove the hand / revert the cast
 * Basically gives them an easy hotkey to lose their hand without needing to click the button
 */
/datum/action/cooldown/spell/undirected/touch/proc/on_hand_dropped(datum/source, mob/living/dropper)
	SIGNAL_HANDLER

	remove_hand(dropper, reset_cooldown_after = TRUE)

/**
 * Called whenever our spell is cast, but blocked by antimagic.
 */
/datum/action/cooldown/spell/undirected/touch/proc/on_antimagic_triggered(obj/item/melee/touch_attack/hand, atom/victim, mob/living/carbon/caster)
	return

/**
 * ## Touch attack item
 *
 * Used for touch spells to have something physical to slap people with.
 *
 * Try to avoid adding behavior onto these for your touch spells!
 * The spells themselves should handle most, if not all, of the casted effects.
 *
 * These should generally just be dummy objects - holds name and icon stuff.
 */
/obj/item/melee/touch_attack
	name = "\improper outstretched hand"
	desc = "High Five?"
	icon = 'icons/mob/roguehudgrabs.dmi'
	icon_state = "grabbing_greyscale"
	item_flags = NEEDS_PERMIT | ABSTRACT
	w_class = WEIGHT_CLASS_HUGE
	force = 0
	throwforce = 0
	throw_range = 0
	throw_speed = 0
	/// A weakref to what spell made us.
	var/datum/weakref/spell_which_made_us

/obj/item/melee/touch_attack/Initialize(mapload, datum/action/cooldown/spell/spell)
	. = ..()

	if(spell)
		spell_which_made_us = WEAKREF(spell)

/obj/item/melee/touch_attack/attack(mob/target, mob/living/carbon/user)
	if(!iscarbon(user)) //Look ma, no hands
		return TRUE
	if(!(user.mobility_flags & MOBILITY_USE))
		to_chat(user, span_warning("You can't reach out!"))
		return TRUE
	return ..()

/**
 * When the hand component of a touch spell is qdel'd, (the hand is dropped or otherwise lost),
 * the cooldown on the spell that made it is automatically refunded.
 *
 * However, if you want to consume the hand and not give a cooldown,
 * such as adding a unique behavior to the hand specifically, this function will do that.
 */
/obj/item/melee/touch_attack/proc/remove_hand_with_no_refund(mob/holder)
	var/datum/action/cooldown/spell/undirected/touch/hand_spell = spell_which_made_us?.resolve()
	if(!QDELETED(hand_spell))
		hand_spell.remove_hand(holder, reset_cooldown_after = FALSE)
		return

	// We have no spell associated for some reason, just delete us as normal.
	holder.temporarilyRemoveItemFromInventory(src, force = TRUE)
	qdel(src)

/obj/item/melee/touch_attack/attack_self(mob/user, params)
	qdel(src)
