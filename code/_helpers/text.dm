/*
 * Holds procs designed to help with filtering text
 * Contains groups:
 *			SQL sanitization
 *			Text sanitization
 *			Text searches
 *			Text modification
 *			Misc
 */


/*
 * SQL sanitization
 */

// Run all strings to be used in an SQL query through this proc first to properly escape out injection attempts.
/proc/sanitizeSQL(var/t as text)
	var/sqltext = dbcon.Quote(t);
	return copytext(sqltext, 2, length(sqltext));//Quote() adds quotes around input, we already do that

// Adds a prefix to the table parameter, used in SQL to unify all tables under a common prefix, i.e. "tegu__[tablename]"
/proc/format_table_name(table as text)
	return "" + table // TODO: Remove hardcoded table prefix, make config entry instead

/*
 * Text sanitization
 */

//Used for preprocessing entered text
//Added in an additional check to alert players if input is too long
/proc/sanitize(var/input, var/max_length = MAX_MESSAGE_LEN, var/encode = 1, var/trim = 1, var/extra = 1)
	if(!input)
		return

	if(max_length)
		//testing shows that just looking for > max_length alone will actually cut off the final character if message is precisely max_length, so >= instead
		if(length(input) >= max_length)
			var/overflow = ((length(input)+1) - max_length)
			to_chat(usr, "<span class='warning'>Your message is too long by [overflow] character\s.</span>")
			return
		input = copytext(input,1,max_length)

	if(extra)
		input = replace_characters(input, list("\n"=" ","\t"=" "))

	if(encode)
		// The below \ escapes have a space inserted to attempt to enable unit testing of span class usage. Please do not remove the space.
		//In addition to processing html, html_encode removes byond formatting codes like "\ red", "\ i" and other.
		//It is important to avoid double-encode text, it can "break" quotes and some other characters.
		//Also, keep in mind that escaped characters don't work in the interface (window titles, lower left corner of the main window, etc.)
		input = html_encode(input)
	else
		//If not need encode text, simply remove < and >
		//note: we can also remove here byond formatting codes: 0xFF + next byte
		input = replace_characters(input, list("<"=" ", ">"=" "))

	if(trim)
		//Maybe, we need trim text twice? Here and before copytext?
		input = trim(input)

	return input

//Run sanitize(), but remove <, >, " first to prevent displaying them as &gt; &lt; &34; in some places, after html_encode().
//Best used for sanitize object names, window titles.
//If you have a problem with sanitize() in chat, when quotes and >, < are displayed as html entites -
//this is a problem of double-encode(when & becomes &amp;), use sanitize() with encode=0, but not the sanitizeSafe()!
/proc/sanitizeSafe(var/input, var/max_length = MAX_MESSAGE_LEN, var/encode = 1, var/trim = 1, var/extra = 1)
	return sanitize(replace_characters(input, list(">"=" ","<"=" ", "\""="'")), max_length, encode, trim, extra)

//Filters out undesirable characters from names
/proc/sanitizeName(var/input, var/max_length = MAX_NAME_LEN, var/allow_numbers = 0, var/force_first_letter_uppercase = TRUE)
	if(!input || length(input) > max_length)
		return //Rejects the input if it is null or if it is longer then the max length allowed

	var/number_of_alphanumeric	= 0
	var/last_char_group			= 0
	var/output = ""

	for(var/i=1, i<=length(input), i++)
		var/ascii_char = text2ascii(input,i)
		switch(ascii_char)
			// A  .. Z
			if(65 to 90)			//Uppercase Letters
				output += ascii2text(ascii_char)
				number_of_alphanumeric++
				last_char_group = 4

			// a  .. z
			if(97 to 122)			//Lowercase Letters
				if(last_char_group<2 && force_first_letter_uppercase)
					output += ascii2text(ascii_char-32)	//Force uppercase first character
				else
					output += ascii2text(ascii_char)
				number_of_alphanumeric++
				last_char_group = 4

			// 0  .. 9
			if(48 to 57)			//Numbers
				if(!last_char_group)		continue	//suppress at start of string
				if(!allow_numbers)			continue
				output += ascii2text(ascii_char)
				number_of_alphanumeric++
				last_char_group = 3

			// '  -  .
			if(39,45,46)			//Common name punctuation
				if(!last_char_group) continue
				output += ascii2text(ascii_char)
				last_char_group = 2

			// ~   |   @  :  #  $  %  &  *  +
			if(126,124,64,58,35,36,37,38,42,43)			//Other symbols that we'll allow (mainly for AI)
				if(!last_char_group)		continue	//suppress at start of string
				if(!allow_numbers)			continue
				output += ascii2text(ascii_char)
				last_char_group = 2

			//Space
			if(32)
				if(last_char_group <= 1)	continue	//suppress double-spaces and spaces at start of string
				output += ascii2text(ascii_char)
				last_char_group = 1
			else
				return

	if(number_of_alphanumeric < 2)	return		//protects against tiny names like "A" and also names like "' ' ' ' ' ' ' '"

	if(last_char_group == 1)
		output = copytext(output,1,length(output))	//removes the last character (in this case a space)

	for(var/bad_name in list("space","floor","wall","r-wall","monkey","unknown","inactive ai","plating"))	//prevents these common metagamey names
		if(cmptext(output,bad_name))	return	//(not case sensitive)

	return output

//Used to strip text of everything but letters and numbers, make letters lowercase, and turn spaces into .'s.
//Make sure the text hasn't been encoded if using this.
/proc/sanitize_for_email(text)
	if(!text) return ""
	var/list/dat = list()
	var/last_was_space = 1
	for(var/i=1, i<=length(text), i++)
		var/ascii_char = text2ascii(text,i)
		switch(ascii_char)
			if(65 to 90)	//A-Z, make them lowercase
				dat += ascii2text(ascii_char + 32)
			if(97 to 122)	//a-z
				dat += ascii2text(ascii_char)
				last_was_space = 0
			if(48 to 57)	//0-9
				dat += ascii2text(ascii_char)
				last_was_space = 0
			if(32, 46)	//space or .
				if(last_was_space)
					continue
				dat += "."		//We turn these into ., but avoid repeats or . at start.
				last_was_space = 1
	if(dat[length(dat)] == ".")	//kill trailing .
		dat.Cut(length(dat))
	return jointext(dat, null)

//Returns null if there is any bad text in the string
/proc/reject_bad_text(var/text, var/max_length=512)
	if(length(text) > max_length)	return			//message too long
	var/non_whitespace = 0
	for(var/i=1, i<=length(text), i++)
		switch(text2ascii(text,i))
			if(62,60,92,47)	return			//rejects the text if it contains these bad characters: <, >, \ or /
			if(127 to 255)	return			//rejects non-ASCII letters
			if(0 to 31)		return			//more weird stuff
			if(32)			continue		//whitespace
			else			non_whitespace = 1
	if(non_whitespace)		return text		//only accepts the text if it has some non-spaces


//Old variant. Haven't dared to replace in some places.
/proc/sanitize_old(var/t,var/list/repl_chars = list("\n"="#","\t"="#"))
	return html_encode(replace_characters(t,repl_chars))

/*
 * Text searches
 */

//Checks the beginning of a string for a specified sub-string
//Returns the position of the substring or 0 if it was not found
/proc/dd_hasprefix(text, prefix)
	var/start = 1
	var/end = length(prefix) + 1
	return findtext(text, prefix, start, end)

//Checks the beginning of a string for a specified sub-string. This proc is case sensitive
//Returns the position of the substring or 0 if it was not found
/proc/dd_hasprefix_case(text, prefix)
	var/start = 1
	var/end = length(prefix) + 1
	return findtextEx(text, prefix, start, end)

//Checks the end of a string for a specified substring.
//Returns the position of the substring or 0 if it was not found
/proc/dd_hassuffix(text, suffix)
	var/start = length(text) - length(suffix)
	if(start)
		return findtext(text, suffix, start, null)
	return

//Checks the end of a string for a specified substring. This proc is case sensitive
//Returns the position of the substring or 0 if it was not found
/proc/dd_hassuffix_case(text, suffix)
	var/start = length(text) - length(suffix)
	if(start)
		return findtextEx(text, suffix, start, null)

/*
 * Text modification
 */

/proc/replace_characters(var/t,var/list/repl_chars)
	for(var/char in repl_chars)
		t = replacetext(t, char, repl_chars[char])
	return t

//Adds 'u' number of zeros ahead of the text 't'
/proc/add_zero(t, u)
	return pad_left(t, u, "0")

//Adds 'u' number of spaces ahead of the text 't'
/proc/add_lspace(t, u)
	return pad_left(t, u, " ")

//Adds 'u' number of spaces behind the text 't'
/proc/add_tspace(t, u)
	return pad_right(t, u, " ")

// Adds the required amount of 'character' in front of 'text' to extend the lengh to 'desired_length', if it is shorter
// No consideration are made for a multi-character 'character' input
/proc/pad_left(text, desired_length, character)
	var/padding = generate_padding(length(text), desired_length, character)
	return length(padding) ? "[padding][text]" : text

// Adds the required amount of 'character' after 'text' to extend the lengh to 'desired_length', if it is shorter
// No consideration are made for a multi-character 'character' input
/proc/pad_right(text, desired_length, character)
	var/padding = generate_padding(length(text), desired_length, character)
	return length(padding) ? "[text][padding]" : text

/proc/generate_padding(current_length, desired_length, character)
	if(current_length >= desired_length)
		return ""
	var/characters = list()
	for(var/i = 1 to (desired_length - current_length))
		characters += character
	return JOINTEXT(characters)

//Returns a string with reserved characters and spaces before the first letter removed
/proc/trim_left(text)
	for (var/i = 1 to length(text))
		if (text2ascii(text, i) > 32)
			return copytext(text, i)
	return ""

//Returns a string with reserved characters and spaces after the last letter removed
/proc/trim_right(text)
	for (var/i = length(text), i > 0, i--)
		if (text2ascii(text, i) > 32)
			return copytext(text, 1, i + 1)
	return ""

//Returns a string with reserved characters and spaces before the first word and after the last word removed.
/proc/trim(text)
	return trim_left(trim_right(text))

//Returns a string with the first element of the string capitalized.
/proc/capitalize(var/t as text)
	return uppertext(copytext(t, 1, 2)) + copytext(t, 2)

//This proc strips html properly, remove < > and all text between
//for complete text sanitizing should be used sanitize()
/proc/strip_html_properly(var/input)
	if(!input)
		return
	var/opentag = 1 //These store the position of < and > respectively.
	var/closetag = 1
	while(1)
		opentag = findtext(input, "<")
		closetag = findtext(input, ">")
		if(closetag && opentag)
			if(closetag < opentag)
				input = copytext(input, (closetag + 1))
			else
				input = copytext(input, 1, opentag) + copytext(input, (closetag + 1))
		else if(closetag || opentag)
			if(opentag)
				input = copytext(input, 1, opentag)
			else
				input = copytext(input, (closetag + 1))
		else
			break

	return input

//This proc fills in all spaces with the "replace" var (* by default) with whatever
//is in the other string at the same spot (assuming it is not a replace char).
//This is used for fingerprints
/proc/stringmerge(var/text,var/compare,replace = "*")
	var/newtext = text
	if(length(text) != length(compare))
		return 0
	for(var/i = 1, i < length(text), i++)
		var/a = copytext(text,i,i+1)
		var/b = copytext(compare,i,i+1)
		//if it isn't both the same letter, or if they are both the replacement character
		//(no way to know what it was supposed to be)
		if(a != b)
			if(a == replace) //if A is the replacement char
				newtext = copytext(newtext,1,i) + b + copytext(newtext, i+1)
			else if(b == replace) //if B is the replacement char
				newtext = copytext(newtext,1,i) + a + copytext(newtext, i+1)
			else //The lists disagree, Uh-oh!
				return 0
	return newtext

//This proc returns the number of chars of the string that is the character
//This is used for detective work to determine fingerprint completion.
/proc/stringpercent(var/text,character = "*")
	if(!text || !character)
		return 0
	var/count = 0
	for(var/i = 1, i <= length(text), i++)
		var/a = copytext(text,i,i+1)
		if(a == character)
			count++
	return count

/proc/reverse_text(var/text = "")
	var/new_text = ""
	for(var/i = length(text); i > 0; i--)
		new_text += copytext(text, i, i+1)
	return new_text

//Used in preferences' SetFlavorText and human's set_flavor verb
//Previews a string of len or less length
/proc/TextPreview(var/string,var/len=40)
	if(length(string) <= len)
		if(!length(string))
			return "\[...\]"
		else
			return string
	else
		return "[copytext_preserve_html(string, 1, 37)]..."

//alternative copytext() for encoded text, doesn't break html entities (&#34; and other)
/proc/copytext_preserve_html(var/text, var/first, var/last)
	return html_encode(copytext(html_decode(text), first, last))

/proc/create_text_tag(var/tagname, var/tagdesc = tagname, var/client/C = null)
	if(!(C?.get_preference_value(/datum/client_preference/chat_tags) == GLOB.PREF_SHOW))
		return tagdesc
	return icon2html(icon('./icons/chattags.dmi', tagname), world, extra_classes="text_tag")

/proc/text_badge(client/C = null)
	if(!C)
		return null
	var/badge_name
	if(C.holder)
		//No badges when deadminned
		if(C.is_stealthed())
			return null
		//Admin badge otherwise
		if(C.holder.rank)
			badge_name = C.holder.rank
	else if(IS_TRUSTED_PLAYER(C.ckey))
		badge_name = "Trusted"
	if(badge_name)
		return icon2html(icon('./icons/chatbadges.dmi', badge_name), world, extra_classes="text_tag")
	return null

/proc/contains_az09(var/input)
	for(var/i=1, i<=length(input), i++)
		var/ascii_char = text2ascii(input,i)
		switch(ascii_char)
			// A  .. Z
			if(65 to 90)			//Uppercase Letters
				return 1
			// a  .. z
			if(97 to 122)			//Lowercase Letters
				return 1

			// 0  .. 9
			if(48 to 57)			//Numbers
				return 1
	return 0

/proc/generateRandomString(var/length)
	. = list()
	for(var/a in 1 to length)
		var/letter = rand(33,126)
		. += ascii2text(letter)
	. = jointext(.,null)

#define starts_with(string, substring) (copytext(string,1,1+length(substring)) == substring)

#define gender2text(gender) capitalize(gender)

/**
 * Strip out the special beyond characters for \proper and \improper
 * from text that will be sent to the browser.
 */
#define strip_improper(input_text) replacetext(replacetext(input_text, "\proper", ""), "\improper", "")

/proc/pencode2html(t)
	t = replacetext(t, "\n", "<BR>")
	t = replacetext(t, "\[center\]", "<center>")
	t = replacetext(t, "\[/center\]", "</center>")
	t = replacetext(t, "\[br\]", "<BR>")
	t = replacetext(t, "\[b\]", "<B>")
	t = replacetext(t, "\[/b\]", "</B>")
	t = replacetext(t, "\[i\]", "<I>")
	t = replacetext(t, "\[/i\]", "</I>")
	t = replacetext(t, "\[u\]", "<U>")
	t = replacetext(t, "\[/u\]", "</U>")
	t = replacetext(t, "\[time\]", "[station_time_timestamp("hh:mm")]")
	t = replacetext(t, "\[date\]", "[stationdate2text()]")
	t = replacetext(t, "\[large\]", "<font size=\"4\">")
	t = replacetext(t, "\[/large\]", "</font>")
	t = replacetext(t, "\[field\]", "<span class=\"paper_field\"></span>")
	t = replacetext(t, "\[h1\]", "<H1>")
	t = replacetext(t, "\[/h1\]", "</H1>")
	t = replacetext(t, "\[h2\]", "<H2>")
	t = replacetext(t, "\[/h2\]", "</H2>")
	t = replacetext(t, "\[h3\]", "<H3>")
	t = replacetext(t, "\[/h3\]", "</H3>")
	t = replacetext(t, "\[*\]", "<li>")
	t = replacetext(t, "\[hr\]", "<HR>")
	t = replacetext(t, "\[small\]", "<font size = \"1\">")
	t = replacetext(t, "\[/small\]", "</font>")
	t = replacetext(t, "\[list\]", "<ul>")
	t = replacetext(t, "\[/list\]", "</ul>")
	t = replacetext(t, "\[table\]", "<table border=1 cellspacing=0 cellpadding=3 style='border: 1px solid black;'>")
	t = replacetext(t, "\[/table\]", "</td></tr></table>")
	t = replacetext(t, "\[grid\]", "<table>")
	t = replacetext(t, "\[/grid\]", "</td></tr></table>")
	t = replacetext(t, "\[row\]", "</td><tr>")
	t = replacetext(t, "\[cell\]", "<td>")
	t = replacetext(t, "\[logo\]", "<img src = exologo.png>")
	t = replacetext(t, "\[bluelogo\]", "<img src = bluentlogo.png>")
	t = replacetext(t, "\[solcrest\]", "<img src = sollogo.png>")
	t = replacetext(t, "\[torchltd\]", "<img src = exologo.png>")
	t = replacetext(t, "\[iccgseal\]", "<img src = terralogo.png>")
	t = replacetext(t, "\[ntlogo\]", "<img src = ntlogo.png>")
	t = replacetext(t, "\[daislogo\]", "<img src = daislogo.png>")
	t = replacetext(t, "\[eclogo\]", "<img src = eclogo.png>")
	t = replacetext(t, "\[xynlogo\]", "<img src = xynlogo.png>")
	t = replacetext(t, "\[fleetlogo\]", "<img src = fleetlogo.png>")
	t = replacetext(t, "\[sfplogo\]", "<img src = sfplogo.png>")
	t = replacetext(t, "\[editorbr\]", "")
	t = replacetext(t, "\[ethics\]", "<img src = ethics.png>")
	t = replacetext(t, "\[eng\]", "<img src = eng.png>")
	t = replacetext(t, "\[mtf\]", "<img src = mtf.png>")
	t = replacetext(t, "\[log\]", "<img src = log.png>")
	t = replacetext(t, "\[sec\]", "<img src = sec.png>")
	t = replacetext(t, "\[scplogo\]", "<img src = scplogo.png>")
	t = replacetext(t, "\[o5\]", "<img src = o5.png>")
	t = replacetext(t, "\[isd\]", "<img src = isd.png>")
	t = replacetext(t, "\[ecd\]", "<img src = ecd.png>")
	t = replacetext(t, "\[goc\]", "<img src = ungoc.png>")
	t = replacetext(t, "\[uiu\]", "<img src = uiu.png>")
	t = replacetext(t, "\[thi\]", "<img src = thi.png>")
	t = replacetext(t, "\[ar\]", "<img src = ar.png>")
	t = replacetext(t, "\[ci\]", "<img src = ci.png>")
	t = replacetext(t, "\[sh\]", "<img src = sh.png>")
	t = replacetext(t, "\[cotbg\]", "<img src = cotbg.png>")
	return t

//pencode translation to html for tags exclusive to digital files (currently email, nanoword, report editor fields,
//modular scanner data and txt file printing) and prints from them
/proc/digitalPencode2html(var/text)
	text = replacetext(text, "\[pre\]", "<pre>")
	text = replacetext(text, "\[/pre\]", "</pre>")
	text = replacetext(text, "\[fontred\]", "<font color=\"red\">") //</font> to pass html tag integrity unit test
	text = replacetext(text, "\[fontblue\]", "<font color=\"blue\">")//</font> to pass html tag integrity unit test
	text = replacetext(text, "\[fontgreen\]", "<font color=\"green\">")
	text = replacetext(text, "\[/font\]", "</font>")
	text = replacetext(text, "\[redacted\]", "<span class=\"redacted\">R E D A C T E D</span>")
	return pencode2html(text)

//Will kill most formatting; not recommended.
/proc/html2pencode(t)
	t = replacetext(t, "<pre>", "\[pre\]")
	t = replacetext(t, "</pre>", "\[/pre\]")
	t = replacetext(t, "<font color=\"red\">", "\[fontred\]")//</font> to pass html tag integrity unit test
	t = replacetext(t, "<font color=\"blue\">", "\[fontblue\]")//</font> to pass html tag integrity unit test
	t = replacetext(t, "<font color=\"green\">", "\[fontgreen\]")
	t = replacetext(t, "</font>", "\[/font\]")
	t = replacetext(t, "<BR>", "\[br\]")
	t = replacetext(t, "<br>", "\[br\]")
	t = replacetext(t, "<B>", "\[b\]")
	t = replacetext(t, "</B>", "\[/b\]")
	t = replacetext(t, "<I>", "\[i\]")
	t = replacetext(t, "</I>", "\[/i\]")
	t = replacetext(t, "<U>", "\[u\]")
	t = replacetext(t, "</U>", "\[/u\]")
	t = replacetext(t, "<center>", "\[center\]")
	t = replacetext(t, "</center>", "\[/center\]")
	t = replacetext(t, "<H1>", "\[h1\]")
	t = replacetext(t, "</H1>", "\[/h1\]")
	t = replacetext(t, "<H2>", "\[h2\]")
	t = replacetext(t, "</H2>", "\[/h2\]")
	t = replacetext(t, "<H3>", "\[h3\]")
	t = replacetext(t, "</H3>", "\[/h3\]")
	t = replacetext(t, "<li>", "\[*\]")
	t = replacetext(t, "<HR>", "\[hr\]")
	t = replacetext(t, "<ul>", "\[list\]")
	t = replacetext(t, "</ul>", "\[/list\]")
	t = replacetext(t, "<table>", "\[grid\]")
	t = replacetext(t, "</table>", "\[/grid\]")
	t = replacetext(t, "<tr>", "\[row\]")
	t = replacetext(t, "<td>", "\[cell\]")
	t = replacetext(t, "<img src = ntlogo.png>", "\[ntlogo\]")
	t = replacetext(t, "<img src = bluentlogo.png>", "\[bluelogo\]")
	t = replacetext(t, "<img src = sollogo.png>", "\[solcrest\]")
	t = replacetext(t, "<img src = terralogo.png>", "\[iccgseal\]")
	t = replacetext(t, "<img src = exologo.png>", "\[logo\]")
	t = replacetext(t, "<img src = eclogo.png>", "\[eclogo\]")
	t = replacetext(t, "<img src = daislogo.png>", "\[daislogo\]")
	t = replacetext(t, "<img src = xynlogo.png>", "\[xynlogo\]")
	t = replacetext(t, "<img src = sfplogo.png>", "\[sfplogo\]")
	t = replacetext(t, "<span class=\"paper_field\"></span>", "\[field\]")
	t = replacetext(t, "<span class=\"redacted\">R E D A C T E D</span>", "\[redacted\]")
	t = strip_html_properly(t)
	return t

// Random password generator
/proc/GenerateKey()
	//Feel free to move to Helpers.
	var/newKey
	newKey += pick("the", "if", "of", "as", "in", "a", "you", "from", "to", "an", "too", "little", "snow", "dead", "drunk", "rosebud", "duck", "al", "le")
	newKey += pick("diamond", "beer", "mushroom", "assistant", "clown", "captain", "twinkie", "security", "nuke", "small", "big", "escape", "yellow", "gloves", "monkey", "engine", "nuclear", "ai")
	newKey += pick("1", "2", "3", "4", "5", "6", "7", "8", "9", "0")
	return newKey

//Used for applying byonds text macros to strings that are loaded at runtime
/proc/apply_text_macros(string)
	var/next_backslash = findtext(string, "\\")
	if(!next_backslash)
		return string

	var/leng = length(string)

	var/next_space = findtext(string, " ", next_backslash + 1)
	if(!next_space)
		next_space = leng - next_backslash

	if(!next_space)	//trailing bs
		return string

	var/base = next_backslash == 1 ? "" : copytext(string, 1, next_backslash)
	var/macro = lowertext(copytext(string, next_backslash + 1, next_space))
	var/rest = next_backslash > leng ? "" : copytext(string, next_space + 1)

	//See http://www.byond.com/docs/ref/info.html#/DM/text/macros
	switch(macro)
		//prefixes/agnostic
		if("the")
			rest = text("\the []", rest)
		if("a")
			rest = text("\a []", rest)
		if("an")
			rest = text("\an []", rest)
		if("proper")
			rest = text("\proper []", rest)
		if("improper")
			rest = text("\improper []", rest)
		if("roman")
			rest = text("\roman []", rest)
		//postfixes
		if("th")
			base = text("[]\th", rest)
		if("s")
			base = text("[]\s", rest)
		if("he")
			base = text("[]\he", rest)
		if("she")
			base = text("[]\she", rest)
		if("his")
			base = text("[]\his", rest)
		if("himself")
			base = text("[]\himself", rest)
		if("herself")
			base = text("[]\herself", rest)
		if("hers")
			base = text("[]\hers", rest)

	. = base
	if(rest)
		. += .(rest)

/proc/deep_string_equals(var/A, var/B)
	if (length(A) != length(B))
		return FALSE
	for (var/i = 1 to length(A))
		if (text2ascii(A, i) != text2ascii(B, i))
			return FALSE
	return TRUE

// If char isn't part of the text the entire text is returned
/proc/copytext_after_last(var/text, var/char)
	var/regex/R = regex("(\[^[char]\]*)$")
	regex_find(R, text)
	return R.group[1]

/proc/sql_sanitize_text(var/text)
	text = replacetext(text, "'", "''")
	text = replacetext(text, ";", "")
	text = replacetext(text, "&", "")
	return text

/proc/text2num_or_default(text, default)
	var/result = text2num(text)
	return "[result]" == text ? result : default

/proc/text2regex(text)
	var/end = findlasttext(text, "/")
	if (end > 2 && length(text) > 2 && text[1] == "/")
		var/flags = end == length(text) ? FALSE : copytext(text, end + 1)
		var/matcher = copytext(text, 2, end)
		try
			return flags ? regex(matcher, flags) : regex(matcher)
		catch()
	log_error("failed to parse text to regex: [text]")

/proc/process_chat_markup(message)
	if (message && length(config.chat_markup))
		for (var/list/entry in config.chat_markup)
			var/regex/matcher = entry[1]
			message = replacetext_char(message, matcher, entry[2])
	return message

/**
 * Used to get a properly sanitized input. Returns null if cancel is pressed.
 *
 * Arguments
 ** user - Target of the input prompt.
 ** message - The text inside of the prompt.
 ** title - The window title of the prompt.
 ** max_length - If you intend to impose a length limit - default is 1024.
 ** no_trim - Prevents the input from being trimmed if you intend to parse newlines or whitespace.
*/
/proc/stripped_input(mob/user, message = "", title = "", default = "", max_length=MAX_MESSAGE_LEN, no_trim=FALSE)
	var/user_input = input(user, message, title, default) as text|null
	if(isnull(user_input)) // User pressed cancel
		return
	if(no_trim)
		return copytext(html_encode(user_input), 1, max_length)
	else
		return trim(html_encode(user_input), max_length) //trim is "outside" because html_encode can expand single symbols into multiple symbols (such as turning < into &lt;)

/**
 * Used to get a properly sanitized input in a larger box. Works very similarly to stripped_input.
 *
 * Arguments
 ** user - Target of the input prompt.
 ** message - The text inside of the prompt.
 ** title - The window title of the prompt.
 ** max_length - If you intend to impose a length limit - default is 1024.
 ** no_trim - Prevents the input from being trimmed if you intend to parse newlines or whitespace.
*/
/proc/stripped_multiline_input(mob/user, message = "", title = "", default = "", max_length=MAX_MESSAGE_LEN, no_trim=FALSE)
	var/user_input = input(user, message, title, default) as message|null
	if(isnull(user_input)) // User pressed cancel
		return
	if(no_trim)
		return copytext(html_encode(user_input), 1, max_length)
	else
		return trim(html_encode(user_input), max_length)

// Format a power value in W, kW, MW, or GW.
/proc/DisplayPower(powerused)
	if(powerused < 1000) //Less than a kW
		return "[powerused] W"
	else if(powerused < 1000000) //Less than a MW
		return "[round((powerused * 0.001),0.01)] kW"
	else if(powerused < 1000000000) //Less than a GW
		return "[round((powerused * 0.000001),0.001)] MW"
	return "[round((powerused * 0.000000001),0.0001)] GW"
