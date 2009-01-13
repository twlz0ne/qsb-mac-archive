--
--  main.applescript
--  iTunes Plugin
--
--  Copyright (c) 2008 Google Inc. All rights reserved.
--
--  Redistribution and use in source and binary forms, with or without
--  modification, are permitted provided that the following conditions are
--  met:
--
--    * Redistributions of source code must retain the above copyright
--  notice, this list of conditions and the following disclaimer.
--    * Redistributions in binary form must reproduce the above
--  copyright notice, this list of conditions and the following disclaimer
--  in the documentation and/or other materials provided with the
--  distribution.
--    * Neither the name of Google Inc. nor the names of its
--  contributors may be used to endorse or promote products derived from
--  this software without specific prior written permission.
--
--  THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
--  "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT
--  LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR
--  A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT
--  OWNER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL,
--  SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT
--  LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE,
--  DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY
--  THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
--  (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
--  OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
--

on toggleRepeat()
	tell application "iTunes"
		tell current playlist
			if song repeat is off then
				set song repeat to one
			else if song repeat is one then
				set song repeat to all
			else
				set song repeat to off
			end if
		end tell
	end tell
end toggleRepeat

on toggleShuffle()
	tell application "iTunes" to tell current playlist to set shuffle to not shuffle
end toggleShuffle

on setRatingTo0()
	tell application "iTunes" to set rating of current track to 0
end setRatingTo0

on setRatingTo1()
	tell application "iTunes" to set rating of current track to 20
end setRatingTo1

on setRatingTo2()
	tell application "iTunes" to set rating of current track to 40
end setRatingTo2

on setRatingTo3()
	tell application "iTunes" to set rating of current track to 60
end setRatingTo3

on setRatingTo4()
	tell application "iTunes" to set rating of current track to 80
end setRatingTo4

on setRatingTo5()
	tell application "iTunes" to set rating of current track to 100
end setRatingTo5

on decreaseVolume()
	tell application "iTunes" to set sound volume to sound volume - 10
end decreaseVolume

on increaseVolume()
	tell application "iTunes" to set sound volume to sound volume + 10
end increaseVolume

on toggleMute()
	tell application "iTunes" to set mute to not mute
end toggleMute

on increaseRating()
	tell application "iTunes"
		if rating of current track is less than 100 then set rating of current track to (rating of current track) + 20
	end tell
end increaseRating

on decreaseRating()
	tell application "iTunes"
		if rating of current track is greater than 0 then set rating of current track to (rating of current track) - 20
	end tell
end decreaseRating
