-- Write a track's artwork to a file, in whatever format Music stores it.
-- osascript artwork.applescript <persistent id> <path>  →  "ok" | "none"
-- Tried through the library first; the current track covers streamed songs
-- that were never added to it.
on run argv
	set tid to item 1 of argv
	set p to item 2 of argv
	tell application "Music"
		if not running then return "none"
		try
			set t to first track of library playlist 1 whose persistent ID is tid
		on error
			try
				set t to current track
				if persistent ID of t is not tid then return "none"
			on error
				return "none"
			end try
		end try
		if (count of artworks of t) is 0 then return "none"
		set d to raw data of artwork 1 of t
	end tell
	set f to open for access (POSIX file p) with write permission
	try
		set eof f to 0
		write d to f
		close access f
	on error e
		close access f
		error e
	end try
	return "ok"
end run
