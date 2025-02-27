/proc/create_new_xenomorph(var/alien_caste,var/target)

	target = get_turf(target)
	if(!target || !alien_caste) return

	var/mob/living/carbon/human/new_alien = new(target)
	new_alien.set_species("Xenophage [alien_caste]")
	return new_alien

/mob/living/carbon/human/xdrone/Initialize(mapload, new_species)
	h_style = "Bald"
	. = ..(mapload, "Xenophage Drone")

/mob/living/carbon/human/xsentinel/Initialize(mapload, new_species)
	h_style = "Bald"
	. = ..(mapload, "Xenophage Sentinel")

/mob/living/carbon/human/xhunter/Initialize(mapload, new_species)
	h_style = "Bald"
	. = ..(mapload, "Xenophage Hunter")

/mob/living/carbon/human/xqueen/Initialize(mapload, new_species)
	h_style = "Bald"
	. = ..(mapload, "Xenophage Queen")
