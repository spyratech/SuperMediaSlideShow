--
--	SuperMediaSlideShow.lua
--
--	Author: keith.schneider at spyratech dot com - September, 2022
--
--	Modification History:
--	11-Dec-2022 Add support for Flags in ScenesList to allow Scene specific settings
--              drop ! use on Media Command as replaced by Flags. Fix spellings and
--              events function (although still unused).  Bump Version to 1.7
--	19-Dec-2022 Fix bug where Settings Overrides were not always reseting properly.
--				Bump version to 1.7.1
--	19-Dec-2022	Fix bug, remove empty modcallback functions in script_properties that
--				caused infinite modcallbacks on non-existent field changes that occur
--				when no sources are yet defined.  eg: as in a new OBS setup/config.
--				Bump Version to 1.7.2
--
--	-----------------------------------------------------------------------------------
--	
--	COPYRIGHT NOTICE:
--	Copyright (c) 2022 Keith A. Schneider
--	Copyright (c) 2022 SpyraTech International LLC
--	An unpublished work.
--
--	This software and its documentation is licensed under the terms of the:
--
--		GNU GENERAL PUBLIC LICENSE
--		 Version 3, 29 June 2007
--
--	The text of this license accompanies this software and is implicitly
--	incorporated into the body of this source code.
--	
--	-----------------------------------------------------------------------------------
--
--	Konsole regex string useful for debug/highlighting on terminal.
--	Take the next couple lines less lua comment chars as 1 line and paste
--	into a Konsole find pattern search/match field and see the highlighted
--	logging output on the terminal while it runs. For debugging, run obs
--	from a terminal command line (eg: clear ; obs ). Also, set regex match!
--
--	ENTER:|LEAVE:|script_tick|\*\*STOP\*\*|true|false|source_.*activated.*|
--	callback|Next\s+Item\s+Info:\s#\d+\s+of\s+\d+|.*\.lua\]\s+[1-9]+[0-9]*
--
--	-----------------------------------------------------------------------------------
--
--	A core aspect of the theory of operation of this script follows.  The cycling of media is
--	totally based on the behavior of sources.  They themselves cycle through something called
--	visibility.  When visibility changes, these objects activate and deactivate.  This
--	program merely picks up on that behavior and uses it to know when to load a next image and
--	when a picture has expired a time duration to change visibilty to none which causes a
--	deactivation, where a new image is loaded and the cycle continues.
--
--	When you change the visibility of a sceneItem, these call backs were observed.  There are
--	two paths taken - obviously visibility is stated as true or false (visible and not visible).
--	In the diagram below, various intermediate callbacks are informational but not useful (here)
--	but by tracing/observing these, I was able to see/learn about OBS and what happens under
--	the covers regarding scene item visibility changes.
--
--	Signals completely depended upon are: source activate & deactivate while show/hide and
--	item_visible are incidental yet informational.
--
--	When a picture is setup, the image source is loaded with the filespec of the picture and
--	has visibility set true causing a source_activated callback which sets the timer for image
--	duration.  When that timer expires, the callback for images merely cancels the timer and
--	sets visibility to false to setup the deactivated callback.  This sets up the basis for
--	the cycling of images.  When a Media (audio/video) source comes into play, the same cycle
--	continues except in this case, the callback that handles the termination of the video is
--	triggered as a result of the source media_ended signal.  There again, it just sets the
--	visibility of the media source to false triggering a source_deactivated callback where the
--	next item is loaded and the cycle perpetuates...
--
--	The diagram below attempts to show the flow of the program for the case of an Image source.
--	If you remove the item_visible, source show & hide callbacks, the flow appears even more
--	simplified.  Those callbacks do nothing to the flow, as they only help one understand the
--	sequence of things as a result of setting a sceneItems visibility.
--
--                          +-<--<--<--<--<-<-<-<-<-<-<--<-<-<-+
--                          |                                  ^
--                          v                                  |
--       [----------------------------------------------]      ^
--       [          CB ImageShowDurationExpired         ]      |
--       [  cancel timer and set the pic to not visible ]      ^
--       [    Flow then takes the left side of diagram  ]      |
--       [  set_sceneitem_visibility(sceneItem, false)  ]      ^
--       [------------------v---------------------------]      |
--                          |                                  ^
--                          v                                  |
--                   [CB_item_visible]                  [CB_source_activated]
--                          |                         add timer for pic duration
--                          |                                  ^
--                          v                                  |
--                   [CB_source_hide]                    [CB_source_show]
--                          |                                  ^
--                          v                                  |
--                [CB_source_deactivated]                [CB_item_visible]
--                    load next pic                            ^
--                     set vis true                            |
--                          |                                  ^
--                          +->-->-->-->-->-->-->-->-->-->->->-+
--
--	When it comes to the operational setup of a slide show using this program, I require that
--	your sources be added into a GROUP.  This way as you click on the group to turn it on/off,
--	all sources within the group behave accordingly.  If you set the group to active and simply
--	want the show to activate as a result of entering that scene, you can accomplish this by
--	using some other tools like probably Advance Scene Switcher/Macros or whatever.  If you
--	only want to setup an Images only slide show (or Videos Only), you  can do this.  You MUST
--	have ONE Image source or One Media Source or both.  If, at the start of a show, you have
--	any one or both of these sources set to OFF, then the slide show will proceed and possibly,
--	effectively Do Nothing.  It honors the initial visibility of these sources for the run of
--	the show.  The notion of the TEXT source - well, it just sort of comes along for the ride
--	with the Image and Media sources.  You do not have to add a Text source to the group and if
--	it is defined, it does not have to be visible.  So, there ought be some reasonable flexibility
--	therein...  I'm interested in how users might actually implement this thing.  Oh, if you
--	specify that the show ought loop, then the only way to stop it is to manually press the group
--	source icon to stop it or use the Safe Terminate Hotkey/button.  If the list of files
--	collected has zero items, the show wont start..
--
--	I have tried to broadly test this but its the real world testing that will tell.  I tried to
--	make it robust but time will tell.  I tend towards verbosity in coding, debugging code and
--	commenting.  I have learned from empirical evidence/experience that commenting code is good
--	no matter what others say or how stale you might think they become.  We all have billions of
--	instructions per second to work with.  Back in mid PDP-11 days, we had maybe a few hundred
--	thousand instructions per second to work with and only 64KB of address space.  So, Suck it
--	up and consider how good we all have it these days.
--
--	------------------------------------------------------------------------------
--
obs = obslua	-- global object for interfacing to obs for everything
bit = require("bit")
--
gbl_settings          = nil
gbl_scriptTitle       = "SuperMediaSlideShow"
gbl_scriptVersion     = "1.7.2"
gbl_activatedState    = false
gbl_TickSeconds       = 0
gbl_LoopCount         = 0
gbl_ShowInterrupt     = false
gbl_ShowInterruptViaHotkey = false
gbl_ScenesUsedList    = {}
gbl_SceneBegBgVolume  = 0
gbl_SceneEntryAutoStarting = false
gbl_ShowSceneName     = ""
gbl_ShowMediaCommand  = ""
gbl_ShowNextScene     = ""
gbl_LastBgVolume      = 0
gbl_PrelaunchVolume   = 0			-- Set to the Volume BEFORE a Scene Entry Startup sequence starts.  Normally, ought match prmBgAudioData.origVolume
gbl_RecordStarting    = false		-- Recording starting, not yet started
gbl_RecordStarted     = false		-- Recording actually completed Starting
gbl_RecordWasActive   = false		-- Recording was already active when we went to start recording.
gbl_RecordStopping    = false		-- Recording Stopping, not yet stopped
gbl_RecordStopped     = false		-- Recording actually completed Stop
gbl_RecordWasInactive = false		-- Recording was already inactive when we went to stop recording.
gbl_SceneRecFlags = { 	begSceneBegRecord=false,		-- when scene begins, set Bg Audio to 0, fade up (if defined) and start recording, waiting for ready
						endSceneEndRecord=false,		-- when scene ends,   fade Bg Audio to 0, stop recording if a Next-Scene is not specified
						VT={flag=false,valu=0},			-- Set/override Pic View Time      if falg=true
						AF={flag=false,valu=0},			-- Set/override BgAudio Fade Time  if flag=true
						AP={flag=false,valu=0},			-- Set/override Audio Fade Percent if flag=true
						RN={flag=false,valu=false},		-- Set/override RandomizeShow      if flag=true
						QT={flag=false,valu=false} }	-- Set/override Quiet Text view    if flag=true
gbl_FirstSlideItem       = ""
gbl_FirstSlideType       = 0
gbl_FirstSlideTypeString = ""
--
cbVisDelay            = 10		-- Delay time for some script_tick operations
hotkey_id             = obs.OBS_INVALID_HOTKEY_ID
--
local ctx = { 	set_visible   = {},
				set_scene     = {},
				set_delay     = {},
				set_audioFade = {}
			}
--
--	Define initial prm variables and values - these are used in the properties forms etc.
--
prmSceneAutoStart    = false
prmShowsDisabled     = true
prmLoopContinuous    = false	-- True=Slide show loops forever, False=Stops after finish Media List
prmShowControlGroup  = ""
prmTargetTextSource  = ""
prmTargetImageSource = ""
prmImageShowTranTime = 0
prmImageHideTranTime = 0
prmTargetMediaSource = ""
prmMediaShowTranTime = 0
prmMediaHideTranTime = 0
prmBgAudioFadeSource = ""
prmBgAudioCutPercent = 50
prmBgAudioFadeTime   = 1000
prmPicDelayPeriod    = 3000
prmFolderTrimLevel   = 0		-- trims n folders off text displayed path
prmFolderTrimOnLeft  = true		-- True=trims N elems on left, False=retain N elems left of filename
prmRandomizeShow     = false
prmMediaMonPeriod    = 1000
-- cannot make a local file URL link work in the Scripts settings description.
prmUserGuidePdfFile  = script_path().."SuperMediaSlideShow.pdf"
-- Got all but the Hotkey text externalized to an ini locale file but tried Chinese lang and it crashes
-- Something to work on with the UTF character sets etc.  Long story...TWT
prmCurrentLocaleFile = script_path().."locale"..string.sub( package.config,1,1 ).."en-US.ini"
defCurrentLocaleFile = prmCurrentLocaleFile
defLocaleIniFilePath = script_path().."locale"
localeIniData        = {}		-- Loaded with keys/text from en-US.ini file - but locale stuff fails overall
prmHomeFolderPath    = ""
defHomeFolderPath    = ""		-- This is set immediately in script_defaults to platform HOME folder using getenv etc.
--
-- simple stats counters
--
countTargetTextSource  = 0
countTargetImageSource = 0
countTargetMediaSource = 0
--
-- for debug control
--
prmDebugLogLevel   = 1
prmDebugMaxLevel   = 5
prmDebugLogEnabled = false
gbl_DLevel         = 0
gbl_LastTime       = os.time()
--
showBegTime        = 0
showEndTime        = 0
--
-- These are used during the show.
--
prmSourceNames = {}
prmSourceNames["prmTargetTextSource" ] = { value=prmTargetTextSource  , beginVisibility=nil , sceneItemObj=nil , beginItemValue=nil }
prmSourceNames["prmTargetImageSource"] = { value=prmTargetImageSource , beginvisibility=nil , sceneItemObj=nil , beginItemValue=nil }
prmSourceNames["prmTargetMediaSource"] = { value=prmTargetMediaSource , beginvisibility=nil , sceneItemObj=nil , beginItemValue=nil }
--
--	This is used to carry fader data for the audio source that gets its volume faded down and up as needed.
--
prmBgAudioData = {	sourceName   = prmBgAudioFadeSource ,
					sourceObj    = nil ,
					cutToPercent = prmBgAudioCutPercent ,
					fadeTime     = prmBgAudioFadeTime ,
					origVolume   = 0 ,
					fadedVolume  = 0
				 }
--
--	Constants - want types when collecting scenes, groups or both
--
wantBothSAndGs	= 1
wantOnlyScenes	= 2
wantOnlyGroups	= 3
filterAllow     = false
filterExclude   = true
--
--	Constants - slide types active at each cycle - used to set/compare with activeSlideType
--
slideTypeNone  = 0
slideTypeMedia = 1
slideTypeImage = 2
slideTypeAudio = 3
--
--	Key data items used globally
--
activeMediaList       = {}
activeMediaIndex      = 0
activeSlideType       = slideTypeNone
activeMediaItem       = ""
activeSlideTypeString = ""
activeLastSlideType   = slideTypeNone
activeSlideRunning    = false				-- true when a slide is started but not finished
activeStartupWaiting  = false
activeWaitingCount    = 0
activeShutdownWaiting = false
activeWaitingCount    = 0
--
--	list of indexs to follow for the show.
--	Once this list is loaded, it will have the same number of entries as the activeMediaList does.
--	IF RANDOM SHOW this list is populated with index numbers from the activeMediaLIst randomly.
--	IF NOT RANDOM, this list is populated with index numbers identical to the activeMediaList.
--	While the show operates, for either random or not, the items are loaded via this index of indexs.
--	The building of this list of indexes adds startup time to the show but seems very reasonable.
--	Even loading a list of a couple thousand entries and randomizing the list happens in a blink.
--
activeListIndexs = nil
--
--	Media filetypes allowed - Gleaned this infor from OBS sources and docs
--
gblMediaTypes = {	mp3  = "mp3" ,
					mp4  = "mp4" ,
					m4v  = "m4v" ,
					ts   = "ts"  ,
					mov  = "mov" ,
					mxf  = "mxf" ,
					flv  = "flv" ,
					mkv  = "mkv" ,
					avi  = "avi" ,
					ogg  = "ogg" ,
					aac  = "aac" ,
					wav  = "wav" ,
					gif  = "gif" ,
					webm = "webm"
				}
--
--	Image filetypes allowed
--
gblImageTypes = {	bmp  = "bmp"  ,
					tga  = "tga"  ,
					png  = "png"  ,
					jpg  = "jpg"  ,
					jpeg = "jpeg" ,
					jxr  = "jxr"  ,
					gif  = "gif"  ,
					psd  = "psd"  ,
					webp = "webp"
				}
--
--	Media filetypes that match AUDIO only
--
gblAudioOnly =  {	mp3 = "mp3" ,
					aac = "aac" ,
					ogg = "ogg" ,
					wav = "wav"
				}
--
--	Function to get the CWD (cd) currently set.
--	It is a wrapper over the OBS provided call because of the nuances
--	of using the API, I wrapped it up to make it easy/intuitive to use.
--
function getcwd()
	--debugLog( 5 , "ENTER: getcwd" )
	-- have to have a buffer long enough to contain the results of the os call
	-- I experimented with short lengths and they fail until it is big enough to work.
	-- Hard to say how big is enough.  Field use will tell.
	local rtncwd = ""
	local buffer = string.rep(" ",200)			-- ought be enough
	rtncwd = obs.os_getcwd( buffer , string.len(buffer) )
	--debugLog( 5 , "LEAVE: getcwd - returning: "..rtncwd )
	return rtncwd	
end
--
--	Function to do a set of CWD (cd) for the running application.
--	It is a wrapper for the OBS provided call and in this case, the
--	wrapper is super simple but setup to fit with the more complicated
--	counterpart call wrapper (above).  BTW - testing on Windows shows that
--	it works across devices too.
--
function setcwd( newcwd )
	--debugLog( 5 , "ENTER: setcwd - newcwd: "..newcwd )
	obs.os_chdir( newcwd )
	--local newCurCwd = getcwd()
	--debugLog( 5 , "LEAVE: setcwd - newcwd: "..newcwd..", new set CWD: "..newCurCwd )
	return true
end
--
--	Return character T, F or N for a given (supposedly) bool value.
--
function tf( val )
	local rval = false
	if val == nil then
		rval = "N"
	else
		if val then
			rval = "T"
		else
			rval = "F"
		end
	end
	return rval
end
--
--	Function to shorten and make it easier to use string.format with a bool
--
function sfbool(abool)
	return string.format("%q",abool)
end
--
--	Function to check if an item is in a given list.
--	List is a simple array where the key is of no concern.
--	Nothing fancy, just a convenience tool
--
function isInList(srchList,item)
	local found = false
	for k,v in pairs(srchList) do
		if item == v then
			found = true
			break
		end
	end
	return found
end
--
-- Debug Logging functions
--
function debugLog ( level , text )
	local gotENTER   = false
	local gotLEAVE   = false
	local bodyIndent = string.rep(" ",7)
	local curTime = os.time()
	local difTime = os.difftime(curTime,gbl_LastTime)
	if string.match(text,"^ENTER:") ~= nil then
		gotENTER = true
		bodyIndent = ""
	end
	if string.match(text,"^LEAVE:") ~= nil then
		gotLEAVE = true
		bodyIndent = ""
		gbl_DLevel = gbl_DLevel - 1
		if gbl_DLevel < 0 then
			gbl_DLevel = 0
		end
	end
	if prmDebugLogEnabled or level == 0 then
		if level <= prmDebugLogLevel then
			gbl_LastTime  = curTime
			-- A level of 0 will always print the message
			--obs.script_log(obs.LOG_DEBUG, text)
			local dl = gbl_DLevel
			if not (gotENTER or gotLEAVE) then dl = dl - 1 end
			local msg = ""
			--msg = obs.bnum_allocs()..";"	-- uncomment this and see every debug line with mem leak/use info
			msg = msg..string.format("%3d,",difTime)
			if level == 0 then
				msg = msg..level..": "..text
			else
				msg = msg..level..": "..bodyIndent..string.rep("       ",dl)..text
			end
			print( msg )
			-- I favored using print because the output of print would also show up
			-- on STDOUT, which is why I would run OBS from a KDE Konsole terminal.
			-- I would then see the output and would not loose it even if OBS would
			-- hard crash (I had lots of that in early days).  I liked that I could
			-- also setup the Konsole terminal to regex match/highlight text that
			-- would scroll by which helped readability of volumious debug output.
			--obs.script_log(obs.LOG_DEBUG, "SMS "..msg)
		end
	end
	if gotENTER then
		gbl_DLevel = gbl_DLevel + 1
		if gbl_DLevel > 25 then
			gbl_DLevel = 25
		end
	end
end
function toggleDebugLogClicked(props, p)
	prmDebugLogEnabled = not prmDebugLogEnabled
	debugLog( 0 , "DebugLog status is: "..sfbool(prmDebugLogEnabled).." at logLevel: "..prmDebugLogLevel..", ILevel: "..gbl_DLevel  )
	return false
end
function incrDebugLogLevelClicked(props, p)
	if prmDebugLogLevel + 1 <= prmDebugMaxLevel then
		prmDebugLogLevel = prmDebugLogLevel + 1
	end
	debugLog( 0 , "DebugLog status is: "..sfbool(prmDebugLogEnabled).." at logLevel: "..prmDebugLogLevel..", ILevel: "..gbl_DLevel  )
	return false
end
function decrDebugLogLevelClicked(props, p)
	if prmDebugLogLevel - 1 >= 1 then
		prmDebugLogLevel = prmDebugLogLevel - 1
	end
	debugLog( 0 , "DebugLog status is: "..sfbool(prmDebugLogEnabled).." at logLevel: "..prmDebugLogLevel..", ILevel: "..gbl_DLevel  )
	return false
end
--
--	Use package.config to check the file path delimiter to determine if we are running
--	on Windows or not. But still some ambiguity with Linux or macos
--	Windows has always been intentionally back ass wards with the use of the back slash
--
function isPlatformWindows ()
	local pathDelim = string.sub( package.config,1,1 )
	return pathDelim == '\\'
end
--
--	Check if we are running on Linux
--	I chose to test for the SHELL environment variable to decide Linux.
--	A bit lazy I suppose, could have done an io.popen on the uname command
--	for more exactness.
--
function isPlatformLinux ()
	local isLinux = false
	if not isPlatformWindows() then
		local env_shell = os.getenv("SHELL")
		--debugLog ( 5 , "os.getenv(SHELL) returned: "..env_shell )
		if env_shell ~= nil and env_shell ~= "fail" then
			isLinux = true
		end
	end
	return isLinux
end
--
--	Check if we are running on a MacOS platform
--	Need to improve - its MAC only because its not one of the others
--	Can also reason that with modern Mac, that the file path delimiter being also a slash char,
--	for purposes of this program, they are about all the same.
--
function isPlatformMacOS ()
	local isMacOS = false
	if not isPlatformWindows() and not isPlatformLinux() then
		isMacOS = true
	end
	return isMacOS
end
--
-- Function to act like basename
-- Similar issues like function dirname below
-- but also, it requires a file extension in the fspec of pattern type %w (alphanumeric)
-- this works herein since all these files need an extension that matches a media type anyways.
--
function basename( fspec )
	local pathDelim = string.sub( package.config,1,1 )
	local bname = string.match(fspec,pathDelim.."([%w%s._-]-%.?%w-)$")
	if bname == nil then
		bname = fspec
	end
	return bname
end
--
-- Function to act like dirname
-- beware this might allow funny characters to break the function.
-- it only works with all alpha, digits, dot, hyphen and underscore chars in names
-- If someone has things like $,(),[],{},%,*,?,&,^,#,@ in them, elements will fail.
--
function dirname( fspec )
	local pathDelim = string.sub( package.config,1,1 )
	return string.gsub( fspec , "(%"..pathDelim.."[%w%s._-]-)$" , "" )
end
--
--	Function to load an array of text strings to simulate what the obs_module_text
--	function (that lua cannot see) does.  Not happy that this function is not made
--	available to OBS lua scripts.  Function uses lua os.setlocale function to get
--	ctype catagory of locale and works from there.  Hope it works for other languages.
--	Typically, LANG in US would look like en_US.UTF-8.. Thing is, that the ini file
--	I am using is not exactly standard compliant.  lol, It was Never a standard anyway.
--
--	Further frustration - at this time anyway :-)  OBS is not influenced by a LANG env
--	and I am not sure how to get the lua os.setlocale to pick up the locale, so until
--	otherwise, I just added my own language selection property to this scripts settings
--	page.  Kinda a hack but workable and I did not want to throw away all my work to
--	setup my own localization features since OBS is not enabling me with their APIs.
--	Below, my 2nd attempt fallback ought always work!
--
--	Yet another frustration - I have found that setting up a Chinese local ini file
--	crashes lua/OBS. Gotta figure out something to load and carry the UTF characters
--	properly at some time.  So I have externalized ALL properties text stuff but yet
--	cannot yet properly load and carry the non english data strings around for usage.
--	Until another time, this remains English only.  But close... More work to do.
--	Now I see OBS helper calls that probably enable this to work - well, dunno if
--	anyone will want to localize this thing anyway.
--
function loadLocaleData()
	debugLog( 4 , "ENTER: loadLocaleData" )
	--local myLocale = os.setlocale(nil,"ctype")
	--myLocale = string.gsub(myLocale,"(%..+)$","")
	----	Seems *nix systems store and return things like en_US but everywhere it is
	----	used, (eg the ini files), they are always with the underscore converted to
	----	a hyphen...  Who makes these conventions - always a method to the madness.
	--myLocale = string.gsub(myLocale,"_","-")
	----	And sometimes it can come back as C so that needs to be converted to en-US.
	--if string.lower(myLocale) == "c" then myLocale = "en-US" end
	--debugLog( 4 , "myLocale="..myLocale )
	--
	local pathDelim = ""
	if isPlatformWindows() then
		pathDelim = "\\"
	else
		pathDelim = "/"
	end
	local mypath = script_path()
	--
	--local myLangFile = mypath.."locale"..pathDelim..myLocale..".ini"
	local myLangFile = prmCurrentLocaleFile		-- darn - for now, force always to en-US.ini
	debugLog( 5 , "1st Initial  Attempt opening myLangFile="..myLangFile )
	local itemLines = assert( io.open(myLangFile) )
	if itemLines == nil then
		myLocale = "en_US"
		myLangFile = mypath.."locale"..pathDelim..myLocale..".ini"
		debugLog( 5 , "2nd Fallback Attempt opening myLangFile="..myLangFile )
		itemLines = assert( io.open(myLangFile) )
	end
	--
	local lineArray = {}
	if itemLines ~= nil then
		local aline = ""
		for aline in itemLines:lines() do
			aline = string.gsub(aline,"%s+$","")						-- trim white space at end
			aline = string.gsub(aline,"^%s+","")						-- trim white space at beginning
			if string.match(aline,"^%s-#") == nil and aline ~= "" then
				table.insert( lineArray, aline )
				--debugLog( 5 , "Got Locale Entry: - "..aline )
			end
		end
		itemLines:close()
	else
		debugLog( 4 , "Oh Oh - Total Fail on locale file access!" )
	end
	--
	local key = ""
	local val = ""
	local curKey = ""
	local aSize = 0
	for i=1,#lineArray do
		aLine = lineArray[i]
		aLine = string.gsub(aLine,"%s+$","")						-- trim white space at end
		aLine = string.gsub(aLine,"^%s+","")						-- trim white space at beginning
		-- debugLog( 5 , "Processing line:"..aLine)
		key,val = string.match(aLine,"^([%w%p.-]+)%s-=%s-(.*)$")
		if key ~= nil then
			-- debugLog( 5 , "Got key match:"..key..", val: "..val )
			val = string.gsub(val,[[^(")]],"")						-- strip " from beg of string val
			val = string.gsub(val,[[(")$]],"")						-- strip " from end of string val
			localeIniData[key] = val
			curKey = key
			aSize = aSize + 1
		else
			-- debugLog( 5 , "Got NON key line:"..aLine )
			aLine = string.gsub(aLine,[[^(")]],"")
			aLine = string.gsub(aLine,[[(")$]],"")
			localeIniData[curKey] = localeIniData[curKey] .. aLine
			-- debugLog( 5 , "Built up string:"..localeIniData[curKey] )
		end
	end
	--
	--debugLog( 5 , "" )
	--local i = 0
	--for k,v in pairs(localeIniData) do
	--	i = i + 1
	--	--debugLog( 5 , "Property "..i..", Key="..k.." = "..v )
	--	debugLog( 5 , "Have Property "..string.format("%02d",i)..", Key: "..k )
	--end
	--debugLog( 5 , "" )
	--
	debugLog( 4 , "LEAVE: loadLocaleData - loaded "..aSize.." Language Keys and Text" )
end
--
--	Function to act like the obs_module_text function is supposed to do (if it were available to lua scripting)
--	Since the texts have already been loaded elsewhere, this merely gets the text index by its key and then it
--	has to convert the \n to real new lines etc.
--
function smss_module_text(key)
	debugLog( 4 , "ENTER: smss_module_text" )
	local txt = ""
	if key ~= nil and key ~= "" then
		txt = localeIniData[key]
		if txt ~= nil and txt ~= "" then
			txt = string.gsub(txt,"\\n","\n")
		else
			debugLog( 4 , "smss_module_text - Lookup problem, no Text, key has no actual indexed data?" )
		end
	else
		debugLog( 4 , "smss_module_text - Lookup problem, key is nil or blank" )
	end
	if txt == nil then txt = "" end
	debugLog( 4 , "LEAVE: smss_module_text - returning string.len(txt)="..string.len(txt) )
	return txt
end

--
-- Function to clean off level number of folders from filespec on left side.
--
function trimTopFolders( level , fspec )
	local pathDelim = string.sub( package.config,1,1 )
	local tmpFspec = fspec
	tmpFspec = string.gsub( tmpFspec , ".-"..pathDelim , "" , level )
	return tmpFspec
end
--
-- Function to trim file folder elements off the left side but keeping N levels
-- of folders left of the filename part.
--
function trimTopFoldersFromRight( level , fspec )
	local pathDelim = string.sub( package.config,1,1 )
	local tmpFspec = fspec
	local pparts = {}
	local filepart = basename(fspec)
	local fullDirName = dirname(fspec)
	local fdname = fullDirName
	-- collect the level number (or less) of elements parts into pparts
	for i = 1 , level , 1 do
		pparts[i] = basename(fdname)	-- this is now a basename element
		fdname = dirname(fdname)		-- reduce the fdname by one level
	end
	-- put together the parts as desired
	local newFname = ""
	for k,v in pairs(pparts) do
		newFname = newFname..v..pathDelim
	end
	newFname = newFname..filepart
	return newFname
end
--
--	Trim a [path]filespec of n levels from the right or left pending given direction/
--
function trimPathFolderLevels ( whichway , level , fspec )
	local fresult = ""
	if whichway then
		fresult = trimTopFolders( level , fspec )
	else
		fresult = trimTopFoldersFromRight( level , fspec )
	end
	return fresult
end
--
--	Check the filespec extension for Media types and decide...
--
function isTypeMedia ( filespec )
	local typeMedia = false
	local fspec = string.lower(filespec)
	local ext = string.match(fspec,"%.(%w+)$")
	if ext ~= nil then
		for k,v in pairs(gblMediaTypes) do
			typeMedia = v == ext
			if typeMedia then
				break
			end
		end
	end
	return typeMedia
end
--
--	Check the filespec extension for Image types and decide...
--
function isTypeImage ( filespec )
	local typeImage = false
	local fspec = string.lower(filespec)
	local ext = string.match(fspec,"%.(%w+)$")
	if ext ~= nil then
		for k,v in pairs(gblImageTypes) do
			typeImage = v == ext
			if typeImage then
				break
			end
		end
	end
	return typeImage
end
--
--	Check the filespec extension for Audio types and decide...
--	Notes use isTypeMedia before this to find out if Audio Only
--
function isMediaAudio ( filespec )
	local typeAudio = false
	local fspec = string.lower(filespec)
	local ext = string.match(fspec,"%.(%w+)$")
	if ext ~= nil then
		for k,v in pairs(gblAudioOnly) do
			typeAudio = v == ext
			if typeAudio then
				break
			end
		end
	end
	return typeAudio
end
--
--	Check if the source is active
--	per docs: A source is only considered active if it is being shown on the final mix
--
function isSourceActive ( src )
	local isActive = nil
	if src ~= nil then
		if type(src) == "string" then
			local source = obs.obs_get_source_by_name( src )				--getObj source
			if source ~= nil then
				isActive = obs.obs_source_active(source)
				obs.obs_source_release(source)								-- release source
			end
		else
			isActive = obs.obs_source_active(src)
		end
	end
	return isActive
end
--
--	Check if the source is showing
--	per docs: A source is considered showing if it is being displayed anywhere at all
--	whether on a display context or on the final output
--
function isSourceShowing ( src )
	local isShowing = nil
	if src ~= nil then
		if type(src) == "string" then
			local source = obs.obs_get_source_by_name( src )				-- getObj source
			if source ~= nil then
				isShowing = obs.obs_source_showing(source)
				obs.obs_source_release(source)								-- release source
			end
		else
			isShowing = obs.obs_source_showing(src)
		end
	end
	return isShowing
end
--
--	Function to getSourceHidden
--	per docs: Gets the hidden property that determines whether it should be hidden from the user.
--	Used when the source is still alive but should not be referenced.
--
function isSourceHidden ( src )
	local isHidden = nil
	if src ~= nil then
		if type(src) == "string" then
			local source = obs.obs_get_source_by_name( src )					-- getObj source
			if source ~= nil then
				isHidden = obs.obs_source_is_hidden(source)
				obs.obs_source_release(source)									-- release source
			end
		else
			isHidden = obs.obs_source_is_hidden(src)
		end
	end
	return isHidden
end
--
--	Function to setSourceHidden
--	per docs: Sets the hidden property that determines whether it should be hidden from the user.
--	Used when the source is still alive but should not be referenced.
--
function setSourceHidden ( source , hide )
	local wasHidden = nil
	if source ~= nil then
		if type(source) == "string" then
			local srcObj = obs.obs_get_source_by_name( source )						-- getObj srcObj
			if srcObj ~= nil then
				wasHidden = obs.obs_source_is_hidden(srcObj)
				obs.obs_source_set_hidden(srcObj,hide)
				obs.obs_source_release(srcObj)										-- release srcObj
			end
		else
			wasHidden = obs.obs_source_is_hidden(source)
			obs.obs_source_set_hidden(source,hide)
		end
	end
	return wasHidden
end
--
-- Function to change/update a setting in a source by name settings field.
--
function changeSourceSetting( source, settingKey , settingValue , settingType )
	debugLog( 4 , "ENTER: changeSourceSetting - source: "..source..", Key: "..settingKey..", NewValue: "..settingValue..", Type: "..settingType )
	local wasValue = ""
	if settingType == "string" or settingType == "int" or settingType == "bool" or settingType == "double" then
		local srcObj = obs.obs_get_source_by_name( source )						-- getObj srcObj
		if srcObj ~= nil then
			local curSettings = obs.obs_source_get_settings( srcObj )			-- getObj curSettings
			if settingType == "string" then wasValue = obs.obs_data_get_string( curSettings , settingKey ) end
			if settingType == "int"    then wasValue = obs.obs_data_get_int   ( curSettings , settingKey ) end
			if settingType == "bool"   then wasValue = obs.obs_data_get_bool  ( curSettings , settingKey ) end
			if settingType == "double" then wasValue = obs.obs_data_get_double( curSettings , settingKey ) end
			-- update the settings via given key/value
			if settingType == "string" then	           obs.obs_data_set_string( curSettings , settingKey, settingValue ) end
			if settingType == "int"    then	           obs.obs_data_set_int   ( curSettings , settingKey, settingValue ) end
			if settingType == "bool"   then	           obs.obs_data_set_bool  ( curSettings , settingKey, settingValue ) end
			if settingType == "double" then	           obs.obs_data_set_double( curSettings , settingKey, settingValue ) end
			obs.obs_source_update(srcObj, curSettings)
			obs.obs_data_release(curSettings)									-- release curSettings
			obs.obs_source_release(srcObj)										-- release srcObj
		else
			debugLog( 1 , "changeSourceSetting - Requested SourceObj Not Found for: "..source )
		end
	else
		debugLog( 1 , "changeSourceSetting - Requested settingType invalid: "..settingType )
	end
	debugLog( 4 , "LEAVE: changeSourceSetting - return: "..source..", Key: "..settingKey..", WasValue: "..wasValue )
	return wasValue
end
--
-- Function to get a setting in a source by name settings field.
--
function getSourceSetting( source, settingKey, settingType )
	debugLog( 4 , "ENTER: getSourceSetting - source: "..source..", Key: "..settingKey..", type: "..settingType )
	local isValue = ""
	if settingType == "string" or settingType == "int" or settingType == "bool" or settingType == "double" then
		local srcObj = obs.obs_get_source_by_name( source )						-- getObj srcObj
		if srcObj ~= nil then
			local curSettings = obs.obs_source_get_settings( srcObj )			-- getObj curSettings
			if settingType == "string" then isValue = obs.obs_data_get_string( curSettings , settingKey ) end
			if settingType == "int"    then isValue = obs.obs_data_get_int   ( curSettings , settingKey ) end
			if settingType == "bool"   then isValue = obs.obs_data_get_bool  ( curSettings , settingKey ) end
			if settingType == "double" then isValue = obs.obs_data_get_double( curSettings , settingKey ) end
			obs.obs_data_release(curSettings)									-- release curSettings
			obs.obs_source_release(srcObj)										-- release source Obj
		else
			debugLog( 1 , "getSourceSetting - Requested SourceObj Not Found for: "..source )
		end
	else
		debugLog( 1 , "getSourceSetting - Requested settingType invalid: "..settingType )
	end
	debugLog( 4 , "LEAVE: getSourceSetting - return: "..source..", Key: "..settingKey..", Is Value: "..isValue )
	return isValue
end
--
-- Function to get the visibility of a Scene Item by Name
--
function getSceneItemVisibility( sceneItem )
	local isVisible = nil																				-- function return value
	if sceneItem ~= nil then
		if type(sceneItem) == "string" then
			local sceneSourceObj = obs.obs_frontend_get_current_scene()									-- getObj sceneSourceObj
			local scnName = obs.obs_source_get_name(sceneSourceObj)
			local sceneSceneObj = obs.obs_group_or_scene_from_source(sceneSourceObj)
			obs.obs_source_release(sceneSourceObj)														-- release sceneSourceObj
			local sceneSceneItemObj = obs.obs_scene_find_source_recursive(sceneSceneObj,sceneItem)
			if sceneSceneItemObj ~= nil then
				isVisible = obs.obs_sceneitem_visible(sceneSceneItemObj)
			else
				debugLog( 5 , "getSceneItemVisibility - obs_scene_find_source_recursive("..scnName..","..sceneItem..") returned NIL" )
			end
		else
			if sceneItem ~= nil then
				isVisible = obs.obs_sceneitem_visible(sceneItem)
			end
		end
	else
		debugLog( 5 , "getSceneItemVisibility - Given sceneItem arg was nil." )
	end
	return isVisible
end
--
-- Function to set the visibility of a Scene Item by name or by sceneItemObj
--
function setSceneItemVisibility( sceneItem , visibility )
	debugLog( 4 , "ENTER: setSceneItemVisibility - ")
	local wasVisible = nil		-- function return value
	if sceneItem ~= nil then
		if type(sceneItem) == "string" then
			local sceneSourceObj = obs.obs_frontend_get_current_scene()									-- getObj sceneSourceObj
			local scnName = obs.obs_source_get_name(sceneSourceObj)
			local sceneSceneObj  = obs.obs_group_or_scene_from_source(sceneSourceObj)
			obs.obs_source_release(sceneSourceObj)														-- release sceneSourceObj
			local sceneSceneItemObj = obs.obs_scene_find_source_recursive(sceneSceneObj,sceneItem)
			if sceneSceneItemObj ~= nil then
				wasVisible = obs.obs_sceneitem_visible(sceneSceneItemObj)
				debugLog( 4 , "by name - "..scnName.." item: "..sceneItem.." Set Vis: "..sfbool(visibility).." , Was: "..sfbool(wasVisible) )
				obs.obs_sceneitem_set_visible(sceneSceneItemObj, visibility)
			else
				if scnName == nil then scnName = "NIL" end
				debugLog( 5 , "by name -  Bad Things Happened, obs_scene_find_source_recursive("..scnName..","..sceneItem..") returned NIL" )
			end
		else
			wasVisible = obs.obs_sceneitem_visible(sceneItem)
			debugLog( 4 , "by obj - Set Vis: "..sfbool(visibility).." , Was: "..sfbool(wasVisible) )
			obs.obs_sceneitem_set_visible(sceneItem, visibility)
		end
	else
		debugLog( 5 , "Given sceneItem arg was nil." )
	end
	debugLog( 4 , "LEAVE: setSceneItemVisibility - ")
	return wasVisible
end
--
-- Function check enabled state of a source
--
function isSourceEnabled( src )
	local isEnabled = nil
	if src ~= nil then
		if type(src) == "string" then
			source = obs.obs_get_source_by_name( src )									-- getObj source
			if source ~= nil then
				isEnabled = obs.obs_source_enabled( source )
				obs.obs_source_release( source )										-- release source
			end
		else
			isEnabled = obs.obs_source_enabled( src )
		end
	end
	return isEnabled
end
--
-- Function to change enable/disable a given source
-- DANGER - seems like this can remove all your sources!!!
--
function enableSource( src , reqState )
	local wasEnabled = nil
	if src ~= nil then
		if type(src) == "string" then
			source = obs.obs_get_source_by_name( src )									-- getObj source
			if source ~= nil then
				wasEnabled = obs.obs_source_enabled( source )
				if wasEnabled == reqState then
					debugLog( 5 , "enableSource - byName - Already is requested state: "..sfbool(reqState) )
				else
					obs.obs_source_set_enabled( source , reqState )
				end
				obs.obs_source_release( source )										-- release source
			end
		else
			wasEnabled = obs.obs_source_enabled( src )
			if wasEnabled == reqState then
				debugLog( 5 , "enableSource - byObj - Already is requested state: "..sfbool(reqState) )
			else
				obs.obs_source_set_enabled( src , reqState )
			end
		end
	end
	return wasEnabled
end
--
--	Function to take a list in and return the same list, less duplicates.
--	The returned list is sorted in the process.
--
function uniqList( inList )
	-- First, build an assoc array of the values used as keys
	-- This will absorb the dups automagically.
	local tbl = {}
	for k,v in pairs(inList) do
		tbl[v] = v
	end
	table.sort(tbl)			-- Why not? Seems like a reasonable opportunity.
	local ouList = {}
	for k,v in pairs(tbl) do
		table.insert(ouList,v)
	end
	return ouList
end
--
--	Function to return a table.array of sources that MATCH the provided table of source_id types
--	If ANY element of the wantedIdList == "*", it will be added to the list.  Thus using multiple
--	values in the list with an * wildcard makes little sense.
--	Ought make an id field also work with string.match patterns.
--
function filteredSourcesList(wantedIdList)
	local sources = obs.obs_enum_sources()			-- getObj sources
	local item_list = {}
	if sources ~= nil then
        for _, source in ipairs(sources) do
            local name = obs.obs_source_get_name( source )
			local s_id = obs.obs_source_get_unversioned_id( source )
			for k,f_id in pairs(wantedIdList) do
				if f_id == s_id or f_id == "*" then
					item_list[#item_list+1] = name
					break
				end
			end
		end
		obs.source_list_release(sources)			--release sources
	end
	return item_list
end
--
--	Function to return a list of sources (names) that all have an output attribute of Audio.
--
function audioSourcesList()
	debugLog( 5 , "ENTER: audioSourcesList" )
	local sources = obs.obs_enum_sources()			-- get Obj sources
	local item_list = {}
	if sources ~= nil then
		for _, source in ipairs(sources) do
			if bit.band(obs.obs_source_get_output_flags(source),obs.OBS_SOURCE_AUDIO) > 0  then
				item_list[#item_list+1] = obs.obs_source_get_name(source)
			end
		end
		table.sort(item_list)
	end
	obs.source_list_release(sources)				--release sources
	debugLog( 5 , "LEAVE: audioSourcesList" )
	return item_list
end
--
--	Function to return a table.array of Scenes and Groups
--	wanted=1=Want both scenes and groups, 2=want only scenes, 3=want only groups
--
function getScenesAndGroupsList(wanted)
	debugLog( 5 , "ENTER: GetScenesAndGroupsList - wanted: "..wanted )
	local scenes = obs.obs_frontend_get_scene_names()
	local item_list = {}
	if ( wanted == 1 or wanted == 2 or wanted == 3 ) then
		if scenes ~= nil then
			for i, scene_name in pairs(scenes) do
				if scene_name ~= nil then
					local sceneItemsTbl = {}
					if wanted == 1 or wanted == 2 then
						debugLog( 5 , "Adding Scene "..scene_name.." to list, wanted="..wanted )
						item_list[#item_list+1] = scene_name
					end
					-- Got scene name, now to get scene obj and look thru items for groups
					local sceneSourceObj = obs.obs_get_source_by_name( scene_name )					-- getObj sceneSourceObj
					local sceneSceneObj  = obs.obs_scene_from_source(sceneSourceObj)
					sceneItemsTbl = obs.obs_scene_enum_items(sceneSceneObj)							-- getObj sceneSceneTbl
					for i, sceneItemObj in ipairs(sceneItemsTbl) do
						local itemSourceObj  = obs.obs_sceneitem_get_source(sceneItemObj)
						local itemSourceName = obs.obs_source_get_name(itemSourceObj)
						local isGroup        = obs.obs_sceneitem_is_group(sceneItemObj)
						if isGroup and ( wanted == 1 or wanted == 3 ) then
							debugLog( 5 , "Adding Group "..itemSourceName.." to list, wanted="..wanted )
							item_list[#item_list+1] = itemSourceName
						end
					end
					obs.sceneitem_list_release(sceneItemsTbl)										-- release sceneItemsObj
					obs.obs_source_release    (sceneSourceObj)										-- release sceneSourceObj
				end
			end
		else
			debugLog( 5 , "GetScenesAndGroupsList - Got ZERO scenes - was nil" )
		end
	else
		debugLog( 5 , "GetScenesAndGroupsList - Given Wanted argument must be either 1,2 or 3" )
	end
	debugLog( 5 , "LEAVE: GetScenesAndGroupsList" )
	return item_list
end
--
--	Function to take a list(table/array) and copy it to a list that it returns to the caller.
--	the list returned is filtered either by excluding things in the filterList or allowing
--	only those in the filterList as selected by the filterHow bool.  True=exclude, false=allow.
--	The in and out lists are presumed to be single dimension lists and the array indexes will
--	not be preserved.  The indexes are assumed to be index numbers starting from 1.
--	The returned list will always be either equal to the input list or smaller than the input
--	but never larger then the input list.
--
function filterListItems( inList , filterList , filterHow )
	local rList = {}
	for k,iv in pairs(inList) do				-- iv=input value
		local inFList = false
		for i,fv in pairs(filterList) do		-- fv=filter value
			if iv == fv then
				inFList = true
			end
		end
		if filterHow then						-- true=exclude
			if not inFlist then
				rList[#rList+1] = iv
			end
		else									-- false=allow
			if inFlist then
				rList[#rList+1] = iv
			end
		end
	end
	return rList
end
--
-- ------------------------------ End of Generalized/Utility Functions
--
-- ------------------------------ Application specific things follow
--
-- A function named script_properties defines the properties that
-- the user can change for the entire script module itself
--
--	Some reference types per OBS docs
--		OBS_PROPERTY_INVALID
--		OBS_PROPERTY_BOOL
--		OBS_PROPERTY_INT
--		OBS_PROPERTY_FLOAT
--		OBS_PROPERTY_TEXT
--		OBS_PROPERTY_PATH
--		OBS_PROPERTY_LIST
--		OBS_PROPERTY_COLOR
--		OBS_PROPERTY_BUTTON
--		OBS_PROPERTY_FONT
--		OBS_PROPERTY_EDITABLE_LIST
--		OBS_PROPERTY_FRAME_RATE
--		OBS_PROPERTY_GROUP
--
function script_properties()
	debugLog( 4 , "ENTER: script_properties -- Setup Script Dialog Tools Page fields/buttons etc.")
	--
	local props = obs.obs_properties_create()
	--
	loadLocaleData()
	--	If you find the s arg in these functions unobvious, its lua that adds a self arg due to the way the functions are invoked.
	--	Read the lua docs about invoking functions using the : form. eg: pda[i].parms:listpop(p)
	local function listPop_ShowControlGroup(s,p)
		for k,v in pairs( uniqList(getScenesAndGroupsList(wantOnlyGroups)) ) do
			obs.obs_property_list_add_string(p, v , v)
		end
	end
	--
	local function listPop_TargetTextSource(s,p)
		obs.obs_property_list_add_string(p, "" , "")		-- allow this to be blanked out
		for k,v in pairs( uniqList(filteredSourcesList({"text_gdiplus" , "text_ft2_source"})) ) do
			obs.obs_property_list_add_string(p, v , v)
		end
	end
	--
	local function listPop_TargetImageSource(s,p)
		obs.obs_property_list_add_string(p, "" , "")		-- allow this to be blanked out
		for k,v in pairs( uniqList(filteredSourcesList({"image_source"})) ) do
			obs.obs_property_list_add_string(p, v , v)
		end
	end
	--
	local function listPop_TargetMediaSource(s,p)
		obs.obs_property_list_add_string(p, "" , "")		-- allow this to be blanked out
		for k,v in pairs( uniqList(filteredSourcesList({"ffmpeg_source"})) ) do
			obs.obs_property_list_add_string(p, v , v)
		end
	end
	--
	local function listPop_BgAudioFadeSource(s,p)
		obs.obs_property_list_add_string(p, "" , "")		-- allow this to be blanked out
		for k,v in pairs( uniqList(audioSourcesList()) ) do
			obs.obs_property_list_add_string(p, v , v)
		end
	end
	--
	local pda = {}
	--table.insert( pda, { name="CurrentLocaleFile" , parms={ ptype="pat" , ltype=obs.OBS_PATH_FILE , filter="*.ini" ,
	--														defpath=defLocaleIniFilePath , modCallback=nil , clear=false } } )
	table.insert( pda, { name="SceneAutoStart"    , parms={ ptype="boo" , modCallback=nil } } )
	table.insert( pda, { name="ShowsDisabled"     , parms={ ptype="boo" , modCallback=nil } } )
	table.insert( pda, { name="PictureViewTime"   , parms={ ptype="int" , min=500 , max=60000 , steps=50 , modCallback=nil } } )
	table.insert( pda, { name="ShowControlGroup"  , parms={ ptype="lst" , ltype=obs.OBS_COMBO_TYPE_LIST ,
															format=obs.OBS_COMBO_FORMAT_STRING ,
															modCallback=nil , clear=true ,
															listpop=listPop_ShowControlGroup  } } )
	table.insert( pda, { name="TargetTextSource"  , parms={ ptype="lst" , ltype=obs.OBS_COMBO_TYPE_LIST ,
															format=obs.OBS_COMBO_FORMAT_STRING ,
															modCallback=nil , clear=true ,
															listpop=listPop_TargetTextSource  } } )
	table.insert( pda, { name="TargetImageSource" , parms={ ptype="lst" , ltype=obs.OBS_COMBO_TYPE_LIST ,
															format=obs.OBS_COMBO_FORMAT_STRING ,
															modCallback=nil , clear=true ,
															listpop=listPop_TargetImageSource } } )
	table.insert( pda, { name="TargetMediaSource" , parms={ ptype="lst" , ltype=obs.OBS_COMBO_TYPE_LIST ,
															format=obs.OBS_COMBO_FORMAT_STRING ,
															modCallback=nil , clear=true ,
															listpop=listPop_TargetMediaSource } } )
	table.insert( pda, { name="BgAudioFadeSource" , parms={ ptype="lst" , ltype=obs.OBS_COMBO_TYPE_LIST ,
														    format=obs.OBS_COMBO_FORMAT_STRING ,
															modCallback=nil , clear=true ,
															listpop=listPop_BgAudioFadeSource } } )
	table.insert( pda, { name="BgAudioCutPercent" , parms={ ptype="int" , min=0 , max=100   , steps=5   , modCallback=nil } } )
	table.insert( pda, { name="BgAudioFadeTime"   , parms={ ptype="int" , min=0 , max=10000 , steps=100 , modCallback=nil } } )
	table.insert( pda, { name="ScenesListBasePath", parms={ ptype="pat" , ltype=obs.OBS_PATH_DIRECTORY , filter=nil ,
															defpath=defHomeFolderPath , modCallback=nil } } )
	table.insert( pda, { name="ScenesList"        , parms={ ptype="els" , ltype=obs.OBS_EDITABLE_LIST_TYPE_STRINGS,filter=nil ,
															defpath=nil , modCallback=validateScenesPropertiesCallback ,
															clear=true , listpop=nil } } )
	table.insert( pda, { name="FolderTrimLevel"   , parms={ ptype="int" , min=0 , max=15    , steps=1 ,
														   modCallback=nil } } )
	--table.insert( pda, { name="FolderTrimOnLeft"  , parms={ ptype="boo" , modCallback=nil } } )
	table.insert( pda, { name="LoopContinuous"    , parms={ ptype="boo" , modCallback=nil } } )
	table.insert( pda, { name="RandomizeShow"     , parms={ ptype="boo" , modCallback=nil } } )
	table.insert( pda, { name="SafeTerminate"     , parms={ ptype="btn" , modCallback=nil , callback=showSafeTerminateCallback } } )
	table.insert( pda, { name="DebugLogEnabled"   , parms={ ptype="boo" , modCallback=propDebugToggledCallback } } )
	table.insert( pda, { name="DebugLogLevel"     , parms={ ptype="int" , min=1 , max=5 , steps=1 , modCallback=bil } } )
	table.insert( pda, { name="onFlyToggleDebug"  , parms={ ptype="btn" , modCallback=nil , callback=toggleDebugLogClicked } } )
	table.insert( pda, { name="onFlyIncrLogLevel" , parms={ ptype="btn" , modCallback=nil , callback=incrDebugLogLevelClicked } } )
	table.insert( pda, { name="onFlyDecrLogLevel" , parms={ ptype="btn" , modCallback=nil , callback=decrDebugLogLevelClicked } } )
	--
	--	The following defines the properties/fields per the definitions in the pda array.
	--	The whole thing can be expanded by adding more data types as needed.
	--	This makes the generation of the fields consistent as well as the naming of them
	--	which also works to make the localization of things easier as the ini file names are
	--	generated consistently.
	--
	local p = nil
	for i=1, #pda do
		p = nil
		debugLog( 5 , "Generating Script Properties: "..pda[i].name )
		if pda[i].parms.ptype == "int" then		-- int
			p = obs.obs_properties_add_int(props , pda[i].name , smss_module_text(pda[i].name) , pda[i].parms.min , pda[i].parms.max , pda[i].parms.steps )
		end
		if pda[i].parms.ptype == "boo" then		-- Bool
			p = obs.obs_properties_add_bool(props, pda[i].name , smss_module_text(pda[i].name) )
		end
		if pda[i].parms.ptype == "btn" then		-- Button
			p = obs.obs_properties_add_button(props, pda[i].name , smss_module_text(pda[i].name) , pda[i].parms.callback )
		end
		if pda[i].parms.ptype == "lst" then		-- List
			p = obs.obs_properties_add_list(props, pda[i].name , smss_module_text(pda[i].name) , pda[i].parms.ltype , pda[i].parms.format )
			if pda[i].parms.clear then obs.obs_property_list_clear(p) end
			if pda[i].parms.listpop ~= nil and type(pda[i].parms.listpop) == "function" then
				pda[i].parms:listpop(p)
			end
		end
		if pda[i].parms.ptype == "els" then		-- Editable List
			p = obs.obs_properties_add_editable_list(props , pda[i].name , smss_module_text(pda[i].name) , pda[i].parms.ltype , pda[i].parms.format , pda[i].parms.defpath )
			if pda[i].parms.clear then obs.obs_property_list_clear(p) end
			if pda[i].parms.listpop ~= nil and type(pda[i].parms.listpop) == "function" then
				pda[i].parms:listpop(p)
			end
		end
		if pda[i].parms.ptype == "pat" then		-- Path
			p = obs.obs_properties_add_path(props , pda[i].name , smss_module_text(pda[i].name) , pda[i].parms.ltype , pda[i].parms.filter , pda[i].parms.defpath )
			if pda[i].parms.clear then obs.obs_property_list_clear(p) end
		end
		if p ~= nil then
			local t = smss_module_text( pda[i].name .. ".Tooltip" )
			if t ~= nil and t ~= "" then obs.obs_property_set_long_description( p , t ) end
			if pda[i].parms.modCallback ~= nil and type(pda[i].parms.modCallback) == "function" then
				obs.obs_property_set_modified_callback( p , pda[i].parms.modCallback )
			end
		end
	end
	--
	--	Set initial visibility state for the debug fields.  Want them hidden on 1st paint if debug is off.
	--	The modified callback for property DebugLogEnabled does the onTheFly visibility changes as needed.
	--
	local aItems = { "DebugLogLevel" , "onFlyToggleDebug" , "onFlyIncrLogLevel" , "onFlyDecrLogLevel" }
	for i,pItem in pairs(aItems) do
		local prm = obs.obs_properties_get( props , pItem )
		obs.obs_property_set_visible( prm , prmDebugLogEnabled )
	end
	--
	debugLog( 4 , "LEAVE: script_properties")
	return props
end
--
--	Function to manage the properties display so that when the Debug enabled checkbox is toggled
--	the additional debug options become visible/invisible -just to be cool.  The value of the
--	prmDebugLogEnabled is not changed here.  That happens when OBS calls script_update.
--
function propDebugToggledCallback ( props, property, settings )
	debugLog( 4 , "ENTER: propDebugToggledCallback" )
	--
	local funcReturn = true
	local debugCkBox = obs.obs_data_get_bool( settings , "DebugLogEnabled" )
	--
	debugLog( 0 , "propDebugToggledCallback - debugLogEnabled was Toggled to: "..sfbool(debugCkBox) )
	local lAction = "Hidding"
	if debugCkBox then lAction = "Showing" end
	-- make an array of Associated Items/Properties
	local aItems = { "DebugLogLevel" , "onFlyToggleDebug" , "onFlyIncrLogLevel" , "onFlyDecrLogLevel" }
	for i,pItem in pairs(aItems) do
		debugLog( 0 , "propDebugToggledCallback - "..lAction.." associated field: "..pItem )
		local prm = obs.obs_properties_get( props , pItem )
		obs.obs_property_set_visible( prm , debugCkBox )
	end
	--
	debugLog( 0 , "LEAVE: propDebugToggledCallback -- Returning: "..sfbool(funcReturn) )
	return true
end
--
--	Function to check all the entries in the editable list to ensure that ALL
--	entries have a valid scene name listed at the front of each line.
--	Not happy with the OBS selction of UI tools to work with...  Someday...
--
function validateScenesPropertiesCallback( props , property , settings )
	debugLog( 4 , "ENTER: validateScenesPropertiesCallback" )
	local sceneNamesList =  obs.obs_data_get_array(settings, "ScenesList")		-- getObj sceneNamesList
	local count = obs.obs_data_array_count(sceneNamesList)
	if count > 0 then
		local validScenesList = obs.obs_frontend_get_scene_names()
		local validScene = false
		local validNextScene = false
		local itemErrCode = ""
		local statCount  = 0
		local itemErrTbl = {}
		local flagStr = ""
		local f_VT = {}
		local f_FT = {}
		local f_FP = {}
		local f_RN = {}
		local f_QT = {}
		for i = 1,count do 
			local bangBeg = false
			local bangEnd = false
			flagStr = ""
			f_VT = { flag = false , valu = 0 }									-- Image View Time ms
			f_AF = { flag = false , valu = 0 }									-- AF Audio Fade Time ms
			f_AP = { flag = false , valu = 0 }									-- AP Audio Fade To Percent
			f_RN = { flag = false , valu = "" }									-- RN Random T/F
			f_QT = { flag = false , valu = "" }									-- QT Quiet Text T/F T=Shows Text source (default), F=hide Text Source
			local listItem = obs.obs_data_array_item(sceneNamesList, i-1)		-- getObj listItem
			local itemString = obs.obs_data_get_string(listItem, "value")
			debugLog( 5 , "itemString "..i..", 1 - value: "..itemString )
			itemString = string.gsub(itemString,"^<[%a%p]+>","")				-- remove any Scene Error String
			debugLog( 5 , "itemString "..i..", 2 - value: "..itemString )
			itemString = string.gsub(itemString,"<I:%d-M:%d->","")				-- remove any Cmd Stats String
			debugLog( 5 , "itemString "..i..", 3 - value: "..itemString )
			local itemScene,partTwo = string.match(itemString,"^(.-),(.*)$")
			if itemScene == nil then itemScene = "" end
			if partTwo   == nil then partTwo   = "" end
			debugLog( 5 , "Raw 1 Matches, itemScene: "..itemScene..": partTwo:"..partTwo..":" )
			local itemCmd,nextScene = string.match(partTwo,"^(.*)(,.*)$")
			if itemScene == nil then itemScene = ""      end
			if itemCmd   == nil then itemCmd   = partTwo end
			if nextScene == nil then nextScene = ""      end
			debugLog( 5 , "Raw 2 Matches, itemScene: "..itemScene..": itemCmd:"..itemCmd..": nextScene:"..nextScene..":" )
			itemScene = string.gsub(itemScene,"%s+$","")	-- trim white space at end
			itemScene = string.gsub(itemScene,"^%s+","")	-- trim white space at beginning
			itemCmd   = string.gsub(itemCmd  ,"%s+$","")	-- trim white space at end
			itemCmd   = string.gsub(itemCmd  ,"^%s+","")	-- trim white space at beginning
			nextScene = string.gsub(nextScene,"^,"  ,"")	-- Remove leading comma, its expected as part of pattern capture
			nextScene = string.gsub(nextScene,"%s+$","")	-- trim white space at end
			nextScene = string.gsub(nextScene,"^%s+","")	-- trim white space at beginning
			--
			--	Now, itemCmd could have a <> string containing flags allowing the specification of parameters that
			--	would override the settings values. Flags (case insensitive) are:
			--		VT:ms  - this is View Time for Image slide view duration Milliseconds
			--		AF:ms  - this is Audio Fade Time Milliseconds
			--		AP:%   - this is the Audio Fade To Percentage int value range:0-100
			--		QT:t/f  - this is text dhow/hide - T=show(default), f=hide
			--		RN:t/f  - this is random: T or F
			--	Starting here, itemCmd is a string of the Cmd, possibly prefixed with <flag:value...>
			--	Flags and values are NOT comma separated and spaces not allowed.
			--	Note: Here we are only doing the parsing and some true validation and no error flagging.
			--	Thus, users could put other junk inside the <> brackets and this code could not even see it.
			--	But the user will not get the desired result and flagging it wouold be lots of work and probably ugly
			--	It is bad enough that this takes a lot of character space in the line of text, itself being ugly
			--
			flagStr = string.match( itemCmd , "^%s-(<.->)%s-")			-- extract the flags part of the string
			if flagStr == nil then flagStr = "" end
			itemCmd = string.gsub ( itemCmd , "^%s-<.->%s-" , "" )		-- remove the flags item, leaving only the CMD
			itemCmd = string.gsub(itemCmd  ,"^%s+","")					-- trim white space at beginning
			debugLog( 5 , "flagStr:"..tostring(flagStr)..", itemCmd:"..itemCmd..":")
			--
			--	What is most important here is that the flagStr match be removed from the CMD for CMD testing etc.
			--
			if flagStr ~= nil and flagStr ~= "" then
				flagStr = string.upper(flagStr)
				-- If a match occurs, that .flag value will not be nil, therefore is TRUE
				-- If no match, flag is nil - therefore false
				-- If a match occurs, we initially trust the value capture part of the match.
				f_VT.flag, f_VT.valu = string.match( flagStr , "(VT:)(%d+)"  )		-- To match, must be zero or positive
				f_AF.flag, f_AF.valu = string.match( flagStr , "(AF:)(%d+)"  )		-- To match, must be zero or positive
				f_AP.flag, f_AP.valu = string.match( flagStr , "(AP:)(%d+)"  )		-- To match, must be zero or positive
				f_RN.flag, f_RN.valu = string.match( flagStr , "(RN:)([TF10])" )	-- To match, must be T, F, 1 or 0
				f_QT.flag, f_QT.valu = string.match( flagStr , "(QT:)([TF10])" )	-- To match, must be T, F, 1 or 0
				--
				debugLog( 5 , "f_VT.flag:"..tostring(f_VT.flag)..", f_VT.valu:"..tostring(f_VT.valu)..":" )
				debugLog( 5 , "f_AF.flag:"..tostring(f_AF.flag)..", f_AF.valu:"..tostring(f_AF.valu)..":" )
				debugLog( 5 , "f_AP.flag:"..tostring(f_AP.flag)..", f_AP.valu:"..tostring(f_AP.valu)..":" )
				debugLog( 5 , "f_RN.flag:"..tostring(f_RN.flag)..", f_RN.valu:"..tostring(f_RN.valu)..":" )
				debugLog( 5 , "f_QT.flag:"..tostring(f_QT.flag)..", f_QT.valu:"..tostring(f_QT.valu)..":" )
				--
				if f_VT.flag then
					if tonumber(f_VT.valu) <= 0 then
						f_VT.flag = false							-- a ZERO Image View Time is not good - cancel it
						f_VT.valu = 0
					else
						f_VT.valu = tonumber(f_VT.valu)				-- make this a number
					end
				end
				--		We accept any Audio Fade Time value desired from zero to positive anything
				if f_AF.flag then
					f_AF.valu = tonumber(f_AF.valu)					-- make this a number
				end
				--
				if f_AP.flag then
					if tonumber(f_AP.valu) > 100 then
						f_AP.flag = false							-- a Audio Fade Percentage > 100 is illegal - cancel it
						f_AP.valu = 0
					else
						f_AP.valu = tonumber(f_AP.valu)				-- make this a number
					end
				end
				if f_RN.flag then
					-- based on the nature of the matching, valu is any 1 of the allowed characters.
					-- make the valu a proper bool
					if f_RN.valu == "T" or f_RN.valu == "1" then
						f_RN.valu = true
					else
						f_RN.valu = false
					end
				end
				if f_QT.flag then
					-- based on the nature of the matching, valu is any 1 of the allowed characters.
					-- make the valu a proper bool
					if f_QT.valu == "T" or f_QT.valu == "1" then
						f_QT.valu = true
					else
						f_QT.valu = false
					end
				end
				--	Now nicely reformat the flagStr to what we think we got.  Any junk from the user would then be gone.
				--	If the user notices this, perhaps they might spot mistakes... sigh...
				local nuFlagStr = ""
				if  f_VT.flag  then  nuFlagStr = nuFlagStr.."VT:"..f_VT.valu      end
				if  f_AF.flag  then  nuFlagStr = nuFlagStr.."AF:"..f_AF.valu      end
				if  f_AP.flag  then  nuFlagStr = nuFlagStr.."AP:"..f_AP.valu      end
				if  f_RN.flag  then  nuFlagStr = nuFlagStr.."RN:"..tf(f_RN.valu)  end
				if  f_QT.flag  then  nuFlagStr = nuFlagStr.."QT:"..tf(f_QT.valu)  end
				flagStr = "<"..nuFlagStr..">"
			end
			--
			validScene = false
			validNextScene = false
			itemErrTbl = {}
			if string.match(itemString,"^%s-#") == nil then
				debugLog( 5 , "Trimmed strings, itemScene:"..itemScene..": itemCmd:"..itemCmd..": nextScene:"..nextScene..":" )
				--	Now check itemScene for presence of the prefixed Recording Control Character !
				--	This block of code merely checks if syntactically the ! char is present and in a legal place
				--	If it is, then we just clean it off and pass on the rest of the string to the subsequent code for scene eval.
				local bangChr,iScene = string.match(itemScene,"^(!?)(.*)$")
				if bangChr ~= nil and bangChr == "!" then
					-- Okay, so we got a bangChr - only validating in this function.
					itemScene = iScene
					bangBeg = true
				end
				--	Now check the nextScene for presence, either alone or attached/prefixed to next-scene
				local bangChr,nScene = string.match(nextScene,"^(!?)(.*)$")
				if bangChr ~= nil and bangChr == "!" then
					-- Okay, so we got a bang but did we get a scene or blank
					bangEnd = true
					if nScene ~= nil then
						nextScene = nScene
					end
				end
				--
				if itemScene ~= nil and itemCmd ~= nil then
					-- both parts have something in them
					if itemScene ~= "" then
						for k,v in pairs(validScenesList) do
							if itemScene == v or string.lower(itemScene) == "default" then
								validScene = true
								break
							end
						end
						if not validScene then
							table.insert(itemErrTbl,"UnkScn")
						end
					else
						debugLog( 5 , "Entry "..i.." Scene is blank." )
						table.insert(itemErrTbl,"NilScn")
					end
					if itemCmd == "" then
						table.insert(itemErrTbl,"NilCmd")
					end
				else
					debugLog( 5 , "One or both scene name and command parts of entry "..i.." are nil." )
					table.insert(itemErrTbl,"NilScn")
					table.insert(itemErrTbl,"NilCmd")
				end
				--
				if nextScene ~= "" then
					-- nextScene is optional
					-- If something is filling the 3rd part of the item, then check it for a valid scene
					-- But it could be a bang char by itself
					if nextScene == "!" then
						debugLog( 4 , "nextScene:"..nextScene..": Is a Lone/Valid ! Character - Okay" )
					else
						validNextScene = isInList(validScenesList,nextScene)
						if validNextScene then
							debugLog( 4 , "nextScene:"..nextScene..": Matches Valid Scene - Okay" )
						else
							debugLog( 4 , "nextScene:"..nextScene..": Fails Match to a Valid Scene" )
							table.insert(itemErrTbl,"UnkNxt")
						end
					end
				end
				--
				local newString = ""
				if #itemErrTbl == 0 then
					debugLog( 4 , "Scene Item "..i..", seems okay!" )
					local theMedias = {}
					local numImages = 0
					local numMedias = 0
					numImages,numMedias,theMedias = get_media_list_items ( itemCmd )
					if theMedias == nil then theMedias = {} end
					local stats = "<I:"..numImages.."M:"..numMedias..">"
					newString = ""
					if numImages + numMedias <= 0 then
						newString = "<CmdErr> "
					end
					if bangBeg then newString = newString .. "!" end
					newString = newString .. itemScene.." , "
					if flagStr ~= nil and flagStr ~= "" then
						newString = newString .. flagStr.." "
					end
					newString = newString .. itemCmd.." "..stats
					if nextScene ~= "" or bangEnd then
						newString = newString .. " , "
						if bangEnd then newString = newString .. "!" end
						newString = newString .. nextScene
					end
				else
					itemErrCode = "<"..table.concat(itemErrTbl,"+")..">"
					newString = itemErrCode .. itemString
					debugLog( 4 , "Any or All parts of Scene,Cmd,NextScene entry are Invalid, itemErrCode="..itemErrCode )
				end
				obs.obs_data_set_string(listItem, "value", newString)
			else
				--debugLog( 5 , "Ignoring Comment Line..." )
			end
			obs.obs_data_release(listItem)										-- release listItem
		end
		obs.obs_data_set_array(settings, "ScenesList", sceneNamesList)
	else
		debugLog( 4 , "Scenes Array Empty, Nothing to validate, count="..count )
	end
	obs.obs_data_array_release(sceneNamesList)									-- release sceneNamesList
	debugLog( 4 , "LEAVE: validateScenesPropertiesCallback" )
	return true
end
--
--	Function to get a Media Command Data for the given Scene Name.
--	Returns 4 values,
--		1) Actual Scene Name (could be Default)
--		2) Media Collection Command Line
--		3) Next Scene (could be blank if not defined)
--		4) A recording control array stating to begin recording and or end recording for this show entry
--	It pulls the data out of the gbl_settings data
--
--	NOTE IMPORTANT -- If fiddling with the code at the top of the main loop in this function, where it parses
--	out the data items from each line of the scenesList array,  You have to work to keep it consistent with
--	the almost identical code in validateScenesPropertiesCallback as they both extract from the scenes array
--	and filter/extract items the same and MUST stay the same.
--
function getMediaCmdDataBySceneName( argSceneName )
	debugLog( 4 , "ENTER: getMediaCmdDataBySceneName" )
	local sceneNamesList =  obs.obs_data_get_array(gbl_settings, "ScenesList")		-- getObj sceneNamesList
	local count = obs.obs_data_array_count(sceneNamesList)
	local passCount = 0
	local rtnScene  = ""
	local rtnCmd    = ""
	local rtnNext   = ""
	local rtnRecCtl = { begSceneBegRecord = false , endSceneEndRecord = false , QT={} , RN={} , VT={} , AF={} , AP={} }
	local gotEntry  = false
	local begSceneBang = false
	local nxtSceneBang = false
	local flagStr = ""
	local f_VT = { flag = false , valu = 0 }									-- Image View Time ms
	local f_AF = { flag = false , valu = 0 }									-- AF Audio Fade Time ms
	local f_AP = { flag = false , valu = 0 }									-- AP Audio Fade To Percent
	local f_RN = { flag = false , valu = "" }									-- RN Random T/F
	local f_QT = { flag = false , valu = "" }									-- QT Quiet Text T/F T=Shows Text source (default), F=hide Text Source
	if count > 0 then
		repeat
			passCount = passCount + 1
			for i = 1,count do 
				flagStr = ""
				f_VT = { flag = false , valu = 0 }									-- Image View Time ms
				f_AF = { flag = false , valu = 0 }									-- AF Audio Fade Time ms
				f_AP = { flag = false , valu = 0 }									-- AP Audio Fade To Percent
				f_RN = { flag = false , valu = "" }									-- RN Random T/F
				f_QT = { flag = false , valu = "" }									-- QT Quiet Text T/F T=Shows Text source (default), F=hide Text Source
				local listItem = obs.obs_data_array_item(sceneNamesList, i-1)		-- getObj listItem
				local itemString = obs.obs_data_get_string(listItem, "value")
				obs.obs_data_release(listItem)										-- release listItem
				itemString = string.gsub(itemString,"^<[%a%p]+>","")				-- remove any Scene Error String
				itemString = string.gsub(itemString,"<I:%d-M:%d->","")				-- remove any Cmd Stats String
				local itemScene,partTwo = string.match(itemString,"^(.-),(.*)$")
				if itemScene == nil then itemScene = "" end
				if partTwo   == nil then partTwo   = "" end
				local itemCmd,nextScene = string.match(partTwo,"^(.*)(,.*)$")
				if itemScene == nil then itemScene = ""      end
				if itemCmd   == nil then itemCmd   = partTwo end
				if nextScene == nil then nextScene = ""      end
				itemScene = string.gsub(itemScene,"%s+$","")						-- trim white space at end
				itemScene = string.gsub(itemScene,"^%s+","")						-- trim white space at beginning
				itemCmd   = string.gsub(itemCmd  ,"%s+$","")						-- trim white space at end
				itemCmd   = string.gsub(itemCmd  ,"^%s+","")						-- trim white space at beginning
				nextScene = string.gsub(nextScene,"^,"  ,"")						-- Remove leading comma, its part of pat capture
				nextScene = string.gsub(nextScene,"%s+$","")						-- trim white space at end
				nextScene = string.gsub(nextScene,"^%s+","")						-- trim white space at beginning
				if string.match(itemString,"^%s-#") == nil then
					debugLog( 5 , "P:"..passCount.." Trimmed strings, itemScene:"..itemScene..": nextScene:"..nextScene..": itemCmd:"..itemCmd )
					--	Got a line with all fields extracted and cleaned.
					--	But do we have a line that we want?
					--
					--	Now, itemCmd could have a <> string containing flags allowing the specification of parameters that
					--	would override the settings values. Flags (case insensitive) are:
					--		VT:ms  - this is View Time for Image slide view duration Milliseconds
					--		AF:ms  - this is Audio Fade Time Milliseconds
					--		AP:%   - this is the Audio Fade To Percentage int value range:0-100
					--		TQ:t/f  - this is text dhow/hide - T=show(default), f=hide
					--		RN:t/f  - this is random: T or F
					--	Starting here, itemCmd is a string of the Cmd, possibly prefixed with <flag:value...>
					--	Flags and values are NOT comma separated and spaces not allowed.
					--	Flags present ought be formatted by the validation code so that we can supposedly trust what we get.
					--
					flagStr = string.match( itemCmd , "^%s-(<.->)%s-")			-- extract the flags part of the string
					if flagStr == nil then flagStr = "" end
					itemCmd = string.gsub ( itemCmd , "^%s-<.->%s-" , "" )		-- remove the flags item, leaving only the CMD
					itemCmd = string.gsub(itemCmd  ,"^%s+","")					-- trim white space at beginning
					--
					--	What is most important here is that the flagStr match be removed from the CMD for CMD testing etc.
					--
					if flagStr ~= nil and flagStr ~= "" then
						flagStr = string.upper(flagStr)
						-- If a match occurs, that .flag value will not be nil, therefore is TRUE
						-- If no match, flag is nil - therefore false
						-- If a match occurs, we initially trust the value capture part of the match.
						f_VT.flag, f_VT.valu = string.match( flagStr , "(VT:)(%d+)"  )		-- To match, must be zero or positive
						f_AF.flag, f_AF.valu = string.match( flagStr , "(AF:)(%d+)"  )		-- To match, must be zero or positive
						f_AP.flag, f_AP.valu = string.match( flagStr , "(AP:)(%d+)"  )		-- To match, must be zero or positive
						f_RN.flag, f_RN.valu = string.match( flagStr , "(RN:)([TF10])" )	-- To match, must be T, F, 1 or 0
						f_QT.flag, f_QT.valu = string.match( flagStr , "(QT:)([TF10])" )	-- To match, must be T, F, 1 or 0
						if f_VT.flag then
							if tonumber(f_VT.valu) <= 0 then
								f_VT.flag = false							-- a ZERO Image View Time is not good - cancel it
								f_VT.valu = 0
							else
								f_VT.valu = tonumber(f_VT.valu)
							end
						else
							f_VT.flag = false								-- in case of nil, make it false proper
							f_VT.valu = 0
						end
						--		We accept any Audio Fade Time value desired from zero to positive anything
						if f_AF.flag then
							f_AF.valu = tonumber(f_AF.valu)					-- make a number
						else
							f_AF.flag = false								-- in case of nil, make it false proper
							f_AF.valu = 0
						end
						if f_AP.flag then
							if tonumber(f_AP.valu) > 100 then
								f_AP.flag = false							-- a Audio Fade Percentage > 100 is illegal - cancel it
								f_AP.valu = 0
							else
								f_AP.valu = tonumber(f_AP.valu)				-- make a number
							end
						else
							f_AP.flag = false								-- in case of nil, make it false proper
							f_AP.valu = 0
						end
						if f_RN.flag then
							-- based on the nature of the matching, valu is any 1 of the allowed characters.
							-- make the valu a proper bool
							if f_RN.valu == "T" or f_RN.valu == "1" then
								f_RN.valu = true
							else
								f_RN.valu = false
							end
						else
							f_RN.flag = false								-- in case of nil, make it false proper
							f_RN.valu = false
						end
						if f_QT.flag then
							-- based on the nature of the matching, valu is any 1 of the allowed characters.
							-- make the valu a proper bool
							if f_QT.valu == "T" or f_QT.valu == "1" then
								f_QT.valu = true
							else
								f_QT.valu = false
							end
						else
							f_QT.flag = false								-- in case of nil, make it false proper
							f_QT.valu = false
						end
						--	Now nicely reformat the flagStr to what we think we got.  Any junk from the user would then be gone.
						--	If the user notices this, perhaps they might spot mistakes... sigh...
						--	Ought not really have to do all these reformat things etc. Again, all was formatted in validation code etc.
						local nuFlagStr = ""
						if  f_VT.flag  then  nuFlagStr = nuFlagStr.."VT:"..f_VT.valu      end
						if  f_AF.flag  then  nuFlagStr = nuFlagStr.."AF:"..f_AF.valu      end
						if  f_AP.flag  then  nuFlagStr = nuFlagStr.."AP:"..f_AP.valu      end
						if  f_RN.flag  then  nuFlagStr = nuFlagStr.."RN:"..tf(f_RN.valu)  end
						if  f_QT.flag  then  nuFlagStr = nuFlagStr.."QT:"..tf(f_QT.valu)  end
						flagStr = "<"..nuFlagStr..">"
					end
					--	Now check itemScene for presence of the prefixed Recording Control Character !
					begSceneBang = false
					nxtSceneBang = false
					local bangChr,iScene = string.match(itemScene,"^(!?)(.*)$")
					if bangChr ~= nil and bangChr == "!" then
						-- Okay, so we got a bangChr - only validating in this function.
						begSceneBang = true
						itemScene = iScene
					end
					--	Now check the nextScene for presence, either alone or attached/prefixed to next-scene
					local bangChr,nScene = string.match(nextScene,"^(!?)(.*)$")
					if bangChr ~= nil and bangChr == "!" then
						-- Okay, so we got a bang but did we get a scene or blank
						nxtSceneBang = true
						if nScene ~= nil and nScene ~= "" then
							nextScene = nScene
						end
					end
					if nextScene == "!" then		-- When ! is alone, the match does not get it as thought
						nxtSceneBang = true
						nextScene = ""
					end
					if passCount == 1 then
						if itemScene == argSceneName then
							-- yep, setup the fields for return to caller.
							rtnScene = itemScene
							rtnCmd   = itemCmd
							rtnNext  = nextScene
							rtnRecCtl = { begSceneBegRecord = begSceneBang , endSceneEndRecord = nxtSceneBang ,QT={},RN={},VT={},AF={},AP={}}
							rtnRecCtl.QT.flag = f_QT.flag
							rtnRecCtl.QT.valu = f_QT.valu
							rtnRecCtl.RN.flag = f_RN.flag
							rtnRecCtl.RN.valu = f_RN.valu
							rtnRecCtl.VT.flag = f_VT.flag
							rtnRecCtl.VT.valu = f_VT.valu
							rtnRecCtl.AF.flag = f_AF.flag
							rtnRecCtl.AF.valu = f_AF.valu
							rtnRecCtl.AP.flag = f_AP.flag
							rtnRecCtl.AP.valu = f_AP.valu
							local msg = "P:1, Scene:"..rtnScene..":, beg:"..tf(begSceneBang)..", end:"..tf(nxtSceneBang)..",flagStr="..flagStr
							msg = msg .. ",QT:"..tostring(rtnRecCtl.QT.flag)..tf(rtnRecCtl.QT.valu)
							msg = msg .. ",RN:"..tostring(rtnRecCtl.RN.flag)..tf(rtnRecCtl.RN.valu)
							msg = msg .. ",VT:"..tostring(rtnRecCtl.VT.flag)..rtnRecCtl.VT.valu..":"
							msg = msg .. ",AF:"..tostring(rtnRecCtl.AF.flag)..rtnRecCtl.AF.valu..":"
							msg = msg .. ",AP:"..tostring(rtnRecCtl.AP.flag)..rtnRecCtl.AP.valu..":"
							debugLog( 5 , msg )
							gotEntry = true
							break
						end
					else
						if string.lower(itemScene) == "default" then
							-- yep, but 1st pass failed to find named scene so this pass, we look for a Default entry
							rtnScene = "default"
							rtnCmd   = itemCmd
							rtnNext  = nextScene
							rtnRecCtl = { begSceneBegRecord = begSceneBang , endSceneEndRecord = nxtSceneBang ,QT={},RN={},VT={},AF={},AP={}}
							rtnRecCtl.QT.flag = f_QT.flag
							rtnRecCtl.QT.valu = f_QT.valu
							rtnRecCtl.RN.flag = f_RN.flag
							rtnRecCtl.RN.valu = f_RN.valu
							rtnRecCtl.VT.flag = f_VT.flag
							rtnRecCtl.VT.valu = f_VT.valu
							rtnRecCtl.AF.flag = f_AF.flag
							rtnRecCtl.AF.valu = f_AF.valu
							rtnRecCtl.AP.flag = f_AP.flag
							rtnRecCtl.AP.valu = f_AP.valu
							local msg = "P:1, Scene:"..rtnScene..":, beg:"..sfbool(begSceneBang)..", end:"..sfbool(nxtSceneBang)..",flagStr="..flagStr
							msg = msg .. ",QT:"..tostring(rtnRecCtl.QT.flag)..tf(rtnRecCtl.QT.valu)
							msg = msg .. ",RN:"..tostring(rtnRecCtl.RN.flag)..tf(rtnRecCtl.RN.valu)
							msg = msg .. ",VT:"..tostring(rtnRecCtl.VT.flag)..rtnRecCtl.VT.valu..":"
							msg = msg .. ",AF:"..tostring(rtnRecCtl.AF.flag)..rtnRecCtl.AF.valu..":"
							msg = msg .. ",AP:"..tostring(rtnRecCtl.AP.flag)..rtnRecCtl.AP.valu..":"
							debugLog( 5 , msg )
							gotEntry = true
							break
						else
							-- nope, 1st pass failed to find named scene and no default
							rtnScene = ""
							rtnCmd   = ""
							rtnNext  = ""
							rtnRecCtl = { begSceneBegRecord = false , endSceneEndRecord = false ,QT={},RN={},VT={},AF={},AP={}}
							rtnRecCtl.QT.flag = false
							rtnRecCtl.QT.valu = false
							rtnRecCtl.RN.flag = false
							rtnRecCtl.RN.valu = false
							rtnRecCtl.VT.flag = false
							rtnRecCtl.VT.valu = 0
							rtnRecCtl.AF.flag = false
							rtnRecCtl.AF.valu = 0
							rtnRecCtl.AP.flag = false
							rtnRecCtl.AP.valu = 0
							local msg = "P:1, Scene:"..rtnScene..":, beg:"..sfbool(begSceneBang)..", end:"..sfbool(nxtSceneBang)..",flagStr="..flagStr
							msg = msg .. ",QT:"..tostring(rtnRecCtl.QT.flag)..tf(rtnRecCtl.QT.valu)
							msg = msg .. ",RN:"..tostring(rtnRecCtl.RN.flag)..tf(rtnRecCtl.RN.valu)
							msg = msg .. ",VT:"..tostring(rtnRecCtl.VT.flag)..rtnRecCtl.VT.valu..":"
							msg = msg .. ",AF:"..tostring(rtnRecCtl.AF.flag)..rtnRecCtl.AF.valu..":"
							msg = msg .. ",AP:"..tostring(rtnRecCtl.AP.flag)..rtnRecCtl.AP.valu..":"
							debugLog( 5 , msg )
							break
						end
					end
				else
					--debugLog( 5 , "Ignoring Comment Line..." )
				end
			end
		until gotEntry or passCount == 2
	else
		rtnScene = ""
		rtnCmd   = ""
		rtnNext  = ""
		rtnRecCtl = { begSceneBegRecord = false , endSceneEndRecord = false ,QT={},RN={},VT={},AF={},AP={}}
		rtnRecCtl.QT.flag = false
		rtnRecCtl.QT.valu = false
		rtnRecCtl.RN.flag = false
		rtnRecCtl.RN.valu = false
		rtnRecCtl.VT.flag = false
		rtnRecCtl.VT.valu = 0
		rtnRecCtl.AF.flag = false
		rtnRecCtl.AF.valu = 0
		rtnRecCtl.AP.flag = false
		rtnRecCtl.AP.valu = 0
	end
	obs.obs_data_array_release(sceneNamesList)										-- release sceneNamesList
	local xtra = "Ctl.beg:"..tf(rtnRecCtl.begSceneBegRecord)..", end:"..tf(rtnRecCtl.endSceneEndRecord)
	xtra = xtra .. ",QT:"..tostring(rtnRecCtl.QT.flag)..tf(rtnRecCtl.QT.valu)
	xtra = xtra .. ",RN:"..tostring(rtnRecCtl.RN.flag)..tf(rtnRecCtl.RN.valu)
	xtra = xtra .. ",VT:"..tostring(rtnRecCtl.VT.flag)..rtnRecCtl.VT.valu..":"
	xtra = xtra .. ",AF:"..tostring(rtnRecCtl.AF.flag)..rtnRecCtl.AF.valu..":"
	xtra = xtra .. ",AP:"..tostring(rtnRecCtl.AP.flag)..rtnRecCtl.AP.valu..":"
	debugLog( 4 , "LEAVE: getMediaCmdDataBySceneName, rtnScene:"..rtnScene..": nxtScene:"..rtnNext..": "..xtra..": rtnCmd:"..rtnCmd )
	return rtnScene, rtnCmd, rtnNext, rtnRecCtl
end
--
--	Function to get a Media Command Data for the current Scene
--	Uses getMediaCmdDataBySceneName to do the main work
--	Passes the results of getMediaCmdDataBySceneName to caller.
--
function getMediaCmdDataForCurScene()
	debugLog( 4 , "ENTER: getMediaCmdDataForCurScene" )
	local rtnScene  = ""
	local rtnCmd    = ""
	local rtnNext   = ""
	local rtnRecCtl = { begSceneBegRecord = false , endSceneEndRecord = false }
	local scnName   = ""
	local sceneSourceObj = obs.obs_frontend_get_current_scene()									-- getObj sceneSourceObj
	if sceneSourceObj ~= nil then
		scnName = obs.obs_source_get_name(sceneSourceObj)
		obs.obs_source_release(sceneSourceObj)														-- release sceneSourceObj
		debugLog( 4 , "Got current Scene - calling getMediaCmdDataBySceneName("..scnName..")" )
		rtnScene, rtnCmd, rtnNext, rtnRecCtl = getMediaCmdDataBySceneName( scnName )
	else
		debugLog( 4 , "Failed to get Current Scene - something is not right!" )
	end
	debugLog( 4 , "LEAVE: getMediaCmdDataForCurScene, returns, rtnScene:"..rtnScene..": rtnCmd:"..rtnCmd..": rtnNext:"..rtnNext..":" )
	return rtnScene, rtnCmd, rtnNext, rtnRecCtl
end
--
-- A function named script_description returns the description shown to the user in OBS
--
function script_description()
	-- Spyratech.com globe logo - Geeez, so big!  Hack!
	local icon = 	"data:image/png;base64," ..
					"iVBORw0KGgoAAAANSUhEUgAAAC0AAAAsCAYAAADxRjE/AAAABGdBTUEAALGPC/xhBQAAACBjSFJN" ..
					"AAB6JgAAgIQAAPoAAACA6AAAdTAAAOpgAAA6mAAAF3CculE8AAAABmJLR0QA/wD/AP+gvaeTAAAA" ..
					"B3RJTUUH5gsHFDIAEJEESgAAEXNJREFUWMPFmHuUXVV9x7977/O+z7l33pPHJJMAgYQkYAJReQhK" ..
					"gBB5uaQ8lLKsVfsAW1eXVVZbbbsqtlaMtkq1LhYWLUXFiNIgCSRADJIHyRCSEEIymUkmM3ce933v" ..
					"ee29f/1jZiBAsIjY/tba69y7zrl3f/bvfPfvsRnexJasXDfzkQNgAGhm7N1+B/4/zXgLzyQAZAF4" ..
					"08NYsnJdBKAMYAJA8/96IezNbpzkaTY9BABnegHdAHoBdALQAA4B2AtgFID6XS+AvZ0fTS+IYeot" ..
					"LASwEsASADUAmwH8CkAVAH4XC3hb0KdYADD1Bt4N4GoArQA2AHgYwNg7Df9bQ58C3gbwHgC3YUpG" ..
					"9wP4Md5Bz79j0KeAdwBcAeB2AA0AXwbwSwD6twV/x6FPAd8B4NMArsOU178BoPx68OnnOYA0puSV" ..
					"ABAAKACo4KQI9bagtz1/GKuWzGcPbX7OqjT8PBGlE66TJCJPKl3hnJWJUCGtaz998GW1Z9eYcBxx" ..
					"JWPs7wEMAvgsgAMn/WUOwLkATp/+Pg5gnAg+gDbGcADAod8YeuOz+/F0/yGcNqcjGUbxEq3pbDB2" ..
					"jmmIc5KeK9Kew6TSZiSVJQSfIAIR0YBS+nGAnrz2oqVHz1h+90LT5F9jjM2a9v5LANYCOAPACwCe" ..
					"AjAAIDxp6gyAxQCewbS0/lfof7j3YSyY3Q0CeUEYn+uH8YWmIS5OJxOd6aTbZXCRBsNWwdnzliHa" ..
					"HNvqNQQPiODW/XBRrRkkiHBCKrWeCfrO525/fIyI7mKMXQngKIAfAXgAwIkZCfzLN++ZmX6RUhR/" ..
					"/dth1XPZJKZzgPh1wPf8+An82U2Xs2tv/thZrmPd7tjWis58tr0jn+11bCsRxMqsNgInkioVSb28" ..
					"3AhO94O4xxB8vmsZna5tWlGsDKmoxTLF+Y5pXHb5mr4jYRzfe/ilUppzdimA9QC2nqzZK9dcNaOC" ..
					"cxlj3u9dZ+17/CkJABgbfvTN0/j6J3ejUm+Kx57dfzVj7M9TCXeRZRhWM4ztmh+acawgNZEGWGc2" ..
					"0SGVxni5gWozgCEYHNM0PMdCayaBRhDBtU1kk+7cyUr9o9dfv/j0ZUu77/2nL20jw+B3YSocPrRk" ..
					"5bqTQ6IJoMkYaPCYZnu330EzN07p6UefeQGCQeQy6U9YlvXPLanEGbEit+ZHVhBJUaoF8MMYbdkk" ..
					"y6VcmEKgVPcxWqoBjMEPY4yWamAADEMg6VowDQHbMkTCtRfaprGqvT254swlrd/c8sRRh3P2pwD6" ..
					"AQzcfNNa5Fo4AFwG4IwwopH//FF0ItdxhR4bfvTU0Jt2HEBXS4r5km42TOMfXdvON4IIE+UGCqUa" ..
					"yg0fQRijJ59GRy4J2zTh2iaICCcma6j5IRpBjCCK6xPVRkFpmKbgplSqv94Mt6UTbjPp2XO1prZs" ..
					"1unwkmJd/57CGYyxGwBsDiOaOG2BSBBhCWOYVRijkQe+Fxzt6BF0Sugndh5AOplAINWlrmN/yxCi" ..
					"zQ9jTFQaKNd9xEpDE6CJUA8ijJbqGBorY6RYQxRLTFTqUFqDAHiOWUy55gbPMpKmIbKWKX5qcF5q" ..
					"+GGnZ1tVz7G2VhvBQFdPwtu/b+z7pWJwDWNseWGcNlz4bsPWGjnfp7Gf/yIeGqtivDXPMQPNT4Zm" ..
					"TKDeDDobfvyFKNadShMqjQDNSEJpAhgDEUFpQrUZoFwPwBlDIwgxOFZGJBVipaC0Rsq1spHUx+d0" ..
					"tFTbMkkr4diftC3zVtMQ5cHRybujWH7VMsQ3GHjrF754yQWMsTuJ6L3trexOGaONc7QePqqtSpXC" ..
					"0/r4a0rfVzbi+if3QHEHfrN6mxDGe1OGQKnWRCOIIaWCJg0Qg9IETQStCZbJYVsClslhGQKxlNBS" ..
					"Y0F3HucsnMUEZ+cqTX3NIALngjPGNOf8wSCUL5dqzety6YQvBL8ijOWs7957zdpbbn7oXz1PfH6y" ..
					"REfSKZSODqlsGGHMsl4bmV+BJgC1anG+EMatKc9BLBXqfohYTnmOpmGV1pBKQSmNpgoQxTGE4PAj" ..
					"iSjWyCYcLOvrhmkIW2u9ljHWsEyjHsUyaZlGDsDnW1tSZixlbxDFyKUTrFhtgDF8tKNdfCUI6LKB" ..
					"IX3N8RP6qyOjup5Ksvrr9x0HgO8/+izm93Qgn0mu7cqnT0+5FsIoRqw0YqleAVdaQ2sNIgbGGMA4" ..
					"IqVRD6aeVVoj4UxFCsYAxljMgB+YhtjJOUMsFYIw7g+j2BRcMCk1Y4zBc2yUKo2bb7u144NBoL/U" ..
					"aNDKep0+KSX6iegNlSEHgEzKw4sDw4mWVGJNS9qDaQjk0h7aMglganIwzsH4FCxj080iEUBTV6U0" ..
					"skkXSxd0Q2utONg+xtm9RPSilGqJ1gQ/CEMAw45lJgxDQGmNMJawTQHB0Mq4ee2H1mL72ITeWavT" ..
					"PNNkIWNvTNocABzLRD6TnG0aYhFpgIgatmk0k549JR2i6ev0mJEUEQiEpGejt6MF7S1JJBzrqZGJ" ..
					"8l8fHy/e5fvhu8NY3qWJ8o5lwrGtstI6ZIw5RATOOfwgxNDgUag4RCKTO32ybLxnfELXAZoLYA3w" ..
					"morxVU0bgiOM4nQQRd9xLPvsKJYvOrZ5bS7lnZlLeRgtVqfB6dUNACDl2ljU24GuXAqZhIuBkcnq" ..
					"xp0HN4wWxrf0tLVg9aol37IN4xMg6tWEtGWKQhDGcxljLtFUNKrXazAtEyzyYQjD2HuA3UqExzln" ..
					"IwBuwVQD8Rpdiwc27sCKM/tQqTcvCiM55DrWvnLdP5Z07Wtc28y0ZRMQnEEqglQasdKg6Vi9aG47" ..
					"Fvd2wBAcWpNsBOE9Lxwd28tNszOMVaL/SKEcxvJ7+XRivSH4DgY2RkRXcMayAKBkDBWFEJyDSJW2" ..
					"PTMxuGvXZBRH6m+E4EMAPg5gF4CjMzEaALjWGh19a5gfRiqT8t5FBF1t+CXGmNJEsEwDvZ05LJzV" ..
					"illtGaRdC0QaRIRyrTkmBD+mCTRQKIls0tvzt7dd9kPG+OZYymMEOjBYKO/zbHMnY+hlDFeYhuhW" ..
					"BISBj+ODAyDGUa2UcOJEYG7aOJR3PePbbZ2J0nRa3w7gmtdLRFz3kY/j1luu4vUgSh8+Pr5bKll4" ..
					"+XjBas2kJg0herTWThjL0Xzac7NJ15jVno0qzfBYM4yzpbrfKNaam4cnqq3DE5WkIto1+7w1hxMm" ..
					"jgtSmjMEionk80dG0oLz5UnHWq2ldCfGCuBCIA4DtLe3Ynzcx333HzCJ4Yk/+JOl6xctyRe2/3JE" ..
					"A4gB3ATg5wDqM942ACCIIghhxEEUj/e0tVTGSzVOwJa6H2xKJ9yOZhDNz6a82zO2tYAz9rP2bPLe" ..
					"QrH2XoAWHR0pScb5xqRrXXFgsPCplGsn7uR33/klfntOEv6OMfQxsJa9R0YyxwpFM8EiBH4Dy848" ..
					"DY7rYODICB788RCkROGWj569KZkU2nHMGadundbzMgCv6MNgAMrFImVzeVim4XiOXfUcK6eUstOe" ..
					"c6jeDHcC9GGl9Vyh+QCBtizt63rk6V3PP2KaVp4BiVuvuuCsaiN4fHP/4ZeUpku+jM98SkMtIa2v" ..
					"YiCDcQYBhWYQIZYNMNPGyPgEAh/Y8LMhTBZDfPYvLgq5p2pDJyYDIV6pLoqYaoZXAXh0pnTlN60+" ..
					"Dx1dXcQY8/OZZI8hhBtLVXRsizm2lQYApelIFKu9RPQFTbRTEyUW982BVrrhOVZLqdo4Vpgs75Z+" ..
					"4wRi/yfNRn2r1nqnEJwMwWByBjuuwmAEzgABhYMDZdz/g0M4eKiIG248G3N7sx1xpPoEZ03LNE5O" ..
					"KI8BWICp7v7VOC0YgyFEnYhSfT25oh9Gk1rTPABGV2s28cjWPfv7Xxr6I030pNJ6WRDGF1qmMS+b" ..
					"SnQrpWdt2NbPNmzrLw6OTlZfHBw9nEkl9jq2NdumyLSjMgQUICxwKHDLxtiJBjb+fBiF4TouXdOH" ..
					"pcs6IaXyhRDDQRRXZ/LCtO0HoDDV1b+q6WYYggiVWjOIvvvw1kwkpY5iuaBYrQ/Vm8bK1eeffXjL" ..
					"cwdqSc9eNrsj/5EwjjcePj52sNrwi0rpF3raW5TWdCIbHAdcymDy4LlRes4iQEELG4IUuOkAYQOH" ..
					"hjh2PDWOMJC4cHUvlr+rC0nXBmmqhFE0vGP/4eYFy884GboI4GUAPZjq5Kc8LaUCEVUtQzQSrt0R" ..
					"RVIeGS48PjQ6Oa6J5rZmUw9duuKsPzSFUJ5tIZdOPv3h9593pFRrlBt+OK6U8tppspW0NgG2BqBu" ..
					"EVWzHFTmwoTBNZoNiV9tq+HJDYOQscb7rpyHZSu6kUm4YABiqUak0ieuv+Q87VomXmf9ANpfIw/G" ..
					"GKJYKiF4gXPecuPqVXxOZz7obs2eZpkGGYJvS7j2WNJzGQH7AOyYObH++uaUL8sjC+I4+hwAj4hy" ..
					"BLZNRNVNlmo8gqhJR1728djDw+jfVUQ6Y2P1tQtw5tJ2eLYZduXTTSLSkZSHqvXmULXh4+qLlgN4" ..
					"zRHay5g6bntVHjetPg8/fHwXqg2/0JnLXKyJ/rIzn91wZHhsn2NbMIT4DhFma6KlpWrj3j0Hjzaz" ..
					"qQSKtQbuXiupKTFkGyyyEqmsiiNhWcal9aZyd+8KD44V6uWR4bBFxgrzFmZxwQd60dGThMk5XNu8" ..
					"P+VZj4wVqxeW681f3PCBFeUHN+3AKWwUQB8AtmTlOnqlnmaMYfnpc/26Hx4vVRsN1zYfqzUDykVx" ..
					"wBlrTTjWxAuHjz0Wx3KyszWb84NofF53G7fbcp70A6UaIx7T+oZyQzw3tLdxef8L8qx6XZ9HhBYA" ..
					"E8vP74rPv3h2VzJpwxAcKdcKXMvYtGXngQHHNgMGbHtg4w7ceNnKU0HXp7UtAMhXoD90yTn4yZbd" ..
					"8IPoqWYQdnW3tVx3/uK+3slKfeOxwuT+bf0vjVT9wHUsKxdEscEYm5XPJOt1P/SjahUThXj08GE1" ..
					"+8WD4QVEeA9jaGGMScNgT5kO+8olV86/Wgj+McsQSNgmHMt4Usbx/nTSm2cItjfpudWR8SLexGIA" ..
					"Q5gu1d5QrG7afgBhLGe1taTXdeTT1ymlq80g+tlkpbGpUKw8c2R4PNGaTVZy6QTjjE38x3dfKO/d" ..
					"M5ZJ56xLLFMsjgKlfV82OWcsnbHLl6+dv7ut16oknPRfmYL/fsqz4dnmUdc2/7hcrVMzCCuxlM8y" ..
					"xtSH37/ilMRLVq5j01KWAOgN0A9tfg497XkEYXROPpu8ryXlLSZAa03NMJJbB0cnPrPhmb0T5581" ..
					"r+g5dhvAKs8PDDZrTd/pbs9mVi3u4/m8Wx8Zr1qTpWZ6ctJvGxot0tkL596R9Jybk659VCr1xUqt" ..
					"PtgMQssU4mnGWfODFyzFW7U3nHv8133/hqUXr8Vlq84eOTI8tl0IscQQImeawrZNoyfpOpuL1Xpp" ..
					"ZKKs5nW1l6TW+dZ0ys6lUolKNZhdqYUtB14u2M/tOxZWa2GU8hzfscxwwezOGz3HmuNH0T0nChMT" ..
					"sVQuEbbEStWvf985bxn4lPKYsXUPPIbVq5ahMFmZZ5nGJZ5jdSdce5Vh8H/vf+nYs2EUL2CMTQRR" ..
					"rDVRXmtqHB8rFpXSOO+sPspnkyXLNBJxLDONIJpvGOaXm0GYbvj+gwbn20q1xqOCs+Dmy8//jYB/" ..
					"LTQAINmOB9f/N6JYuobgpxMwxzQMbhpiIJ1wmdI6bwhRaM9ljsaxNDhnmdHJSovnWIFpCNYMolhp" ..
					"3RtL9Z5Y0TVKqe2mYF9rSXkHm2Gs37/ijLeI+ZtAT9tPtuyGVIp5jp2KpZrDGFtoCB4zxsalVFas" ..
					"NMskXce2TE8pbfhhlDMN0cWApFS6U2k9LJX+aaPp73Ed29994DC++Mnr3xbwW4aesYef2oPhwgjr" ..
					"7uhy/DDuNAQ/TWtyTdPoMQRvZUDJNAxLE+W01jUi2imVfjGWcsQyDPnt9VvwyN2fftuwbwv6ZLvv" ..
					"kWdQbQasNeOxzlzW1CBrolQjqRSCKA5eHBxVs9pzdMcNl/7WkK+3/wEBtRr2iPgCcwAAACV0RVh0" ..
					"ZGF0ZTpjcmVhdGUAMjAyMi0xMS0wN1QyMDozOToyMyswMDowMJrkeJ8AAAAldEVYdGRhdGU6bW9k" ..
					"aWZ5ADIwMjItMTEtMDdUMjA6Mzk6MjMrMDA6MDDrucAjAAAAKHRFWHRkYXRlOnRpbWVzdGFtcAAy" ..
					"MDIyLTExLTA3VDIwOjUwOjAwKzAwOjAw28EdlQAAABd0RVh0U29mdHdhcmUAZ2lmMnBuZyAyLjUu" ..
					"MTSHPFzeAAAAAElFTkSuQmCC"
	local desc = 	[[	<center>
							<h2>]] .. gbl_scriptTitle .. [[</h2>
							Copyright(C) 2022 Keith Schneider
							<br/>
							(Version: %s)
							<br/>
							<a href="https://spyratech.com">
								<img width=28 height=28 src=']]..icon..[['></img>
								Spyratech
							</a>
						</center>
					]]
	return string.format(desc, tostring(gbl_scriptVersion))
end
--
--	A function named script_update will be called when settings are changed
--
function script_update(settings)
	debugLog( 4 , "ENTER: script_update -- Get currently set Properties" )
	prmSceneAutoStart    = obs.obs_data_get_bool  (settings, "SceneAutoStart")
	prmShowsDisabled     = obs.obs_data_get_bool  (settings, "ShowsDisabled")
	prmLoopContinuous    = obs.obs_data_get_bool  (settings, "LoopContinuous")
	prmPicDelayPeriod    = obs.obs_data_get_int   (settings, "PictureViewTime")
	prmShowControlGroup  = obs.obs_data_get_string(settings, "ShowControlGroup")
	prmTargetTextSource  = obs.obs_data_get_string(settings, "TargetTextSource")
	prmTargetImageSource = obs.obs_data_get_string(settings, "TargetImageSource")
	prmTargetMediaSource = obs.obs_data_get_string(settings, "TargetMediaSource")
	prmBgAudioFadeSource = obs.obs_data_get_string(settings, "BgAudioFadeSource")
	prmBgAudioCutPercent = obs.obs_data_get_int   (settings, "BgAudioCutPercent")
	prmBgAudioFadeTime   = obs.obs_data_get_int   (settings, "BgAudioFadeTime")
	prmFolderTrimLevel   = obs.obs_data_get_int   (settings, "FolderTrimLevel" )
	prmFolderTrimOnLeft  = obs.obs_data_get_bool  (settings, "FolderTrimOnLeft")
	prmRandomizeShow     = obs.obs_data_get_bool  (settings, "RandomizeShow")
	prmDebugLogEnabled   = obs.obs_data_get_bool  (settings, "DebugLogEnabled")
	prmDebugLogLevel     = obs.obs_data_get_int   (settings, "DebugLogLevel")
	prmCurrentLocaleFile = obs.obs_data_get_string(settings, "CurrentLocaleFile")
	prmHomeFolderPath    = obs.obs_data_get_string(settings, "ScenesListBasePath")
	--
	--	Save this for use elsewhere globally
	--
	gbl_settings = settings
	--
	debugLog( 4 , "LEAVE: script_update" )
	return true
end
--
-- A function named script_defaults will be called to set the default settings
-- script_defaults is called as a very first step in loading a script.
-- I observed that script_defaults is called BEFORE script_load.
-- Computed defaults ought be put here vs script_load.
-- Unless of course such things were computed at the initial physical script read.
-- Contrast this with defCurrentLocaleFile vs defHomeFolderPath.
-- defHomeFolderPath needed supposrt from the isPlatformXXXX functions to work
-- and those functions are not available until they are read from the source file.
--
function script_defaults(settings)
	debugLog( 2 , "ENTER: script_defaults" )
	--
	--	Set defHomeFolderPath now for each platform.
	--
	if isPlatformWindows() then
		defHomeFolderPath = os.getenv("HOMEPATH")
	end
	if isPlatformLinux() then
		defHomeFolderPath = os.getenv("HOME")
	end
	if isPlatformMacOS() then
		defHomeFolderPath = os.getenv("HOME")
	end
	debugLog( 2 , "script_defaults - SMSS - defHomeFolderPath: "..defHomeFolderPath )
	obs.obs_data_set_default_bool  (settings, "SceneAutoStart"    , false )
	obs.obs_data_set_default_bool  (settings, "ShowsDisabled"     , true )
	obs.obs_data_set_default_bool  (settings, "LoopContinuous"    , false )
	obs.obs_data_set_default_int   (settings, "PictureViewTime"   , 4000)
	obs.obs_data_set_default_int   (settings, "BgAudioCutPercent" , 80 )
	obs.obs_data_set_default_int   (settings, "BgAudioFadeTime"   , 1500 )
	obs.obs_data_set_default_bool  (settings, "DebugLogEnabled"   , false )
	obs.obs_data_set_default_bool  (settings, "RandomizeShow"     , false )
	obs.obs_data_set_default_int   (settings, "FolderTrimLevel"   , 1 )
	obs.obs_data_set_default_bool  (settings, "FolderTrimOnLeft"  , true )
	obs.obs_data_set_default_int   (settings, "DebugLogLevel"     , 1 )
	obs.obs_data_set_default_string(settings, "CurrentLocaleFile" , defCurrentLocaleFile )
	obs.obs_data_set_default_string(settings, "ScenesListBasePath", defHomeFolderPath )
	debugLog( 2 , "LEAVE: script_defaults" )
end
--
--	Function called when a source is loaded
--
function source_loaded(cd)
	local sourceObj = obs.calldata_source(cd, "source")
	local loadedSourceName = obs.obs_source_get_name(sourceObj)
	debugLog( 5 , "ENTER: source_loaded - name: "..loadedSourceName )
	--local sourceItm = obs.calldata_source(cd, "item")
	debugLog( 5 , "LEAVE: source_loaded" )
end
--
-- a function named script_load will be called on startup by OBS
--
function script_load(settings)
	--debugLog( 2 , "ENTER: script_load - basic initialization steps here" )
	--
	--	Save this for use elsewhere globally
	--
	gbl_settings = settings
	--
	--	Get all our current parameter values right away when we load
	--
	prmSceneAutoStart    = obs.obs_data_get_bool  (settings, "SceneAutoStart")
	prmShowsDisabled     = obs.obs_data_get_bool  (settings, "ShowsDisabled")
	prmLoopContinuous    = obs.obs_data_get_bool  (settings, "LoopContinuous")
	prmPicDelayPeriod    = obs.obs_data_get_int   (settings, "PictureViewTime")
	prmShowControlGroup  = obs.obs_data_get_string(settings, "ShowControlGroup")
	prmTargetTextSource  = obs.obs_data_get_string(settings, "TargetTextSource")
	prmTargetImageSource = obs.obs_data_get_string(settings, "TargetImageSource")
	prmTargetMediaSource = obs.obs_data_get_string(settings, "TargetMediaSource")
	prmBgAudioFadeSource = obs.obs_data_get_string(settings, "BgAudioFadeSource")
	prmBgAudioCutPercent = obs.obs_data_get_int   (settings, "BgAudioCutPercent")
	prmBgAudioFadeTime   = obs.obs_data_get_int   (settings, "BgAudioFadeTime")
	prmFolderTrimLevel   = obs.obs_data_get_int   (settings, "FolderTrimLevel" )
	prmFolderTrimOnLeft  = obs.obs_data_get_bool  (settings, "FolderTrimOnLeft")
	prmRandomizeShow     = obs.obs_data_get_bool  (settings, "RandomizeShow")
	prmDebugLogEnabled   = obs.obs_data_get_bool  (settings, "DebugLogEnabled")
	prmDebugLogLevel     = obs.obs_data_get_int   (settings, "DebugLogLevel")
	prmCurrentLocaleFile = obs.obs_data_get_string(settings, "CurrentLocaleFile")
	prmHomeFolderPath    = obs.obs_data_get_string(settings, "ScenesListBasePath")
	--
	activeMediaList = {}
	activeMediaIndex = 0
	--
	-- Connect hotkey and activation/deactivation signal callbacks
	--
	local sh = obs.obs_get_signal_handler()
	obs.signal_handler_connect(sh, "source_activate"   , source_activated)
	obs.signal_handler_connect(sh, "source_deactivate" , source_deactivated)
	obs.signal_handler_connect(sh, "source_load"       , source_loaded)
	--
	debugLog( 2 , "defHomeFolderPath = "..defHomeFolderPath )
	debugLog( 2 , "This Script Path  = "..script_path() )
	debugLog( 2 , "PlatformIsWindows = "..sfbool(isPlatformWindows() ) )
	debugLog( 2 , "PlatformIsLinux   = "..sfbool(isPlatformLinux()   ) )
	debugLog( 2 , "PlatformIsMacOS   = "..sfbool(isPlatformMacOS()   ) )
	--
	--	Establish a hotkey that the user can press anytime during the show to cause it to safely terminate.
	--	All it does is set gbl_ShowInterrupt to true and stop the current media via Vis change, causing the
	--	usual deactivation etc.  At the next media item to show, it will fake out the end of the list and
	--	the show will naturally stop.  This ought to work around the clicking of the activation icon which
	--	kills the show in some way that I cannot at this time fully figure out.  Seems it can leave sources
	--	in some inderterminate state as to Vis and Active etc.
	--
	--	TODO: Locale lookups for the hotkey description.
	--
	hotkey_id = obs.obs_hotkey_register_frontend("SMSS-Safe-Terminate","SuperMediaSlideShow\nSafe Terminate",showSafeTerminateCallback)
	local hotkey_save_array = obs.obs_data_get_array(settings, "SMSS-Safe-Terminate")			-- getObj hotkey_save_array
	obs.obs_hotkey_load(hotkey_id, hotkey_save_array)
	obs.obs_data_array_release(hotkey_save_array)												-- release hotkey_save_array
	--
	--debugLog( 2 , "LEAVE: script_load" )
end
--
-- A function named script_save will be called when the script is saved
-- NOTE: This function is usually used for saving extra data (such as in this
-- case, a hotkey's save data).  Settings set via the properties are saved
-- automatically.  For a hotkey, if this is not done, the assigned hotkey
-- selected by the user in OBS->settings->hotkeys will not be saved and
-- the user then has to reassign the key definition at each OBS startup.
--
function script_save(settings)
	debugLog( 4 , "ENTER: script_save" )
	local hotkey_save_array = obs.obs_hotkey_save(hotkey_id)
	obs.obs_data_set_array(settings, "SMSS-Safe-Terminate", hotkey_save_array)
	obs.obs_data_array_release(hotkey_save_array)
	debugLog( 4 , "LEAVE: script_save" )
end
--
--	script_unload is generally not needed as I have seen so far.
--	Though, it would seem that a well behaved script would do the things it needs
--	to to undo what it does at load time.
--
function script_unload(settings)
	debugLog( 4 , "ENTER: script_unload" )
	-- these things seem to make OBS crash - seg fault
	--debugLog( 4 , "script_unload  - Disconnecting global signal handlers source_activate/deactivate and script_load" )
	--local sh = obs.obs_get_signal_handler()
	--obs.signal_handler_disconnect(sh, "source_activate"   , source_activated)
	--obs.signal_handler_disconnect(sh, "source_deactivate" , source_deactivated)
	--obs.signal_handler_disconnect(sh, "source_load"       , source_loaded)
	debugLog( 4 , "LEAVE: script_unload" )
end
--
--	Function to execute given command that will feed back (via pipe) n lines of text
--	The idea here is that the lines of text are really just file paths/names for each
--	media to present in the Media Slide Show.
--
function get_media_list_items ( aCommand )
	debugLog( 4 , "ENTER: get_media_list_items - aCommand="..aCommand )
	local lineArray = {}
	local lineIndex = 0
	--
	--	Before the io.popen, must do a getcwd and then setcwd(prmHomeFolderPath)
	--	so the files specified in the ScenesList commands will work.  Collect the files
	--	accordingly and save them as always.  Afterward, do a setcwd to put the curcwd
	--	back as it was.  My guess is that it might only have to be set long enough for the
	--	popen to execute.  Once we have the handle, presumably the command is executing
	--	and waiting to pipe lines of text back to us.  But I will wait till the pipe is
	--	closed just to not push the limits.
	--
	--	Most of this base path stuff is for Windows users so it can use relative paths
	--	but the  base path is useful for all platform when it comes to portability.
	--
	local curCWD = getcwd()				-- fetch our cwd
	setcwd(prmHomeFolderPath)			-- set cwd to new location
	--
	local itemLines = assert( io.popen(aCommand) )
	local numImages = 0
	local numMedias = 0
	for aline in itemLines:lines() do
		local gotImage = isTypeImage(aline)
		local gotMedia = isTypeMedia(aline)
		if gotImage then numImages = numImages + 1 end
		if gotMedia then numMedias = numMedias + 1 end
		if gotMedia or gotImage then
			lineIndex = lineIndex + 1
			lineArray[lineIndex] = aline
			debugLog( 5 , "Got Entry: "..string.format("%05d",lineIndex).." - "..aline )
		else
			debugLog( 4 , "get_media_list_items - Entry Skipped - Not Image or Media Allowed Types: "..aline )
		end
	end
	itemLines:close()
	--
	setcwd(curCWD)						-- now to put the original cwd back
	--
	debugLog( 4 , "LEAVE: get_media_list_items - loaded: "..#lineArray.." Entries." )
	return numImages , numMedias , lineArray
end
--
-- Function to get the name/filespec of the next media file to operate on.
--
function getNextMediaItem()
	debugLog( 3 , "ENTER: getNextMediaItem - Items List Count="..#activeMediaList.." activeMediaIndex="..activeMediaIndex)
	local text = ""
	local stopFlag = false
	local stopReason = ""
	local numImages = 0
	local numMedias = 0
	if gbl_ShowInterrupt then
		--
		--	This ought to stop new media items going back to the program.
		--	The stop will be seen by the next media item request.
		--	At this time, this happens when the user clicks the group icon and that causes the prmShowContolGroup source
		--	to become deactivated.  As that deactivate code determines that a slide operation is still running, it takes
		--	the action (missed by the timer or the media_ended signals) to set the source visibility to false to cause it
		--	to deactivate.  When that happens, it asks for the next item and this code then returns the STOP message and
		--	thus, the show winds down.  With calm and grace...
		--
		stopFlag = true
		stopReason = "Show Interrupted!"
	else
		if #activeMediaList == 0 or activeMediaIndex + 1 > #activeMediaList then
			local loadReason = ""
			if #activeMediaList == 0 then
				loadReason = "No Media List (yet) Loaded."
			else
				if activeMediaIndex + 1 > #activeMediaList then
					if prmLoopContinuous then
						loadReason = "Media Items List Use Count Rollover."
						--	Note, I decides to let it do a full reload if loop is set
						--	and if randomize is set, it gets new random order.
					else
						--pass text back with special token STOP value
						stopReason = "End of Media List Reached."
						stopFlag = true
					end
				end
			end
			if not stopFlag then
				debugLog( 2 , "Load Status: "..loadReason)
				activeMediaList  = {}
				activeListIndexs = {}
				activeMediaIndex = 0
				activeSlideType = slideTypeNone
				numImages,numMedias,activeMediaList = get_media_list_items(gbl_ShowMediaCommand)
				debugLog( 2 , "Load Status: "..#activeMediaList.." Items of: "..numImages.." Images and "..numMedias.." Medias" )
				gbl_LoopCount = gbl_LoopCount + 1
				if #activeMediaList ~= 0 then
					if prmRandomizeShow then
						-- Build the randomized indexs list
						btime = os.time()
						local i = 1
						local lCount = 0
						local lHit = 0
						while i <= #activeMediaList do
							lCount = lCount + 1
							local n = math.random(1,#activeMediaList)
							if activeListIndexs[n] == nil then
								debugLog( 5 , string.format("BldRndIdx, Put item idx %05d in idx pos %05d, Iters: %05d, Tries: %03d" ,i,n,lCount, lCount-lHit ) )
								activeListIndexs[n] = i
								i = i + 1
								lHit = lCount
							end				
						end
						debugLog( 1 , "Load -> RndzLst Stats: Iters: "..lCount.." vs lstSize: "..#activeMediaList..", idxSize: "..#activeListIndexs..", Elapsed: "..os.difftime(os.time(),btime) )
					else
						-- This is the easy side to populating the indexs list
						for i,v in pairs(activeMediaList) do
							activeListIndexs[i] = i
						end
					end
				else
					stopReason = "Loaded ZERO items - Nothing to do, Looping or not!"
					stopFlag = true
				end
			end
		end
	end
	--
	-- Setup and return the next line to update into the source(s) settings.
	--
	if #activeMediaList > 0 and not stopFlag then
		local listIsAllImages = #activeMediaList == numImages
		local listIsAllMedias = #activeMediaList == numMedias
		if  ( listIsAllImages and prmSourceNames.prmTargetImageSource.sceneItemObj == nil )
		or  ( listIsAllMedias and prmSourceNames.prmTargetMediaSource.sceneItemObj == nil )
		then
			stopReason = "Notice: Oh Oh - Loaded all Images and no Image Source defined, or, Loaded all Medias and no Media Source defined."
			stopFlag = true
		else
			activeMediaIndex = activeMediaIndex + 1
			text = activeMediaList[ activeListIndexs[activeMediaIndex] ]
			if text == nil then text = "" end
			debugLog( 3 , "Next Item - "..activeMediaIndex.." of "..#activeMediaList.." via index# "..activeListIndexs[activeMediaIndex]..", FSpec: "..text)
			stopFlag = false
		end
	else
		stopFlag = true
	end
	if stopFlag then
		--
		-- Got here due to no items available or stopFlag left list empty
		-- either way, send back **STOP** text return value
		--
		text = "**STOP**"
		debugLog( 2 , "getNextMediaItem - "..text.." re: "..stopReason )
	end
	debugLog( 3 , "LEAVE: getNextMediaItem" )
	return text
end
--
--	Function to service callbacks for events that occur in the frontend.
--	Will look at this more in future.
--	Nothing needed here for SMSS yet anyway.
--
function onEventCallback(event)
	debugLog( 4 , "ENTER: onEventCallback - event: "..event )
	if event == obs.OBS_FRONTEND_EVENT_STREAMING_STARTING then
		debugLog( 4 , "Triggered when streaming is starting." )
	end
	if event == obs.OBS_FRONTEND_EVENT_STREAMING_STARTED then
		debugLog( 4 , "Triggered when streaming has successfully started." )
	end
	if event == obs.OBS_FRONTEND_EVENT_STREAMING_STOPPING then
		debugLog( 4 , "Triggered when streaming is stopping." )
	end
	if event == obs.OBS_FRONTEND_EVENT_STREAMING_STOPPED then
		debugLog( 4 , "Triggered when streaming has fully stopped." )
	end
	if event == obs.OBS_FRONTEND_EVENT_RECORDING_STARTING then
		debugLog( 4 , "Triggered when recording is starting." )
	end
	if event == obs.OBS_FRONTEND_EVENT_RECORDING_STARTED then
		debugLog( 4 , "Triggered when recording has successfully started." )
	end
	if event == obs.OBS_FRONTEND_EVENT_RECORDING_STOPPING then
		debugLog( 4 , "Triggered when recording is stopping." )
	end
	if event == obs.OBS_FRONTEND_EVENT_RECORDING_STOPPED then
		debugLog( 4 , "Triggered when recording has fully stopped." )
	end
	if event == obs.OBS_FRONTEND_EVENT_RECORDING_PAUSED then
		debugLog( 4 , "Triggered when the recording has been paused." )
	end
	if event == obs.OBS_FRONTEND_EVENT_RECORDING_UNPAUSED then
		debugLog( 4 , "Triggered when the recording has been unpaused." )
	end
	if event == obs.OBS_FRONTEND_EVENT_SCENE_CHANGED then
		debugLog( 4 , "Triggered when the current scene has changed." )
	end
	if event == obs.OBS_FRONTEND_EVENT_SCENE_LIST_CHANGED then
		debugLog( 4 , "Triggered when a scenes has been added/removed/reordered by the user." )
	end
	if event == obs.OBS_FRONTEND_EVENT_TRANSITION_CHANGED then
		debugLog( 4 , "Triggered when the current transition has changed by the user." )
	end
	if event == obs.OBS_FRONTEND_EVENT_TRANSITION_STOPPED then
		debugLog( 4 , "Triggered when a transition has completed." )
	end
	if event == obs.OBS_FRONTEND_EVENT_TRANSITION_LIST_CHANGED then
		debugLog( 4 , "Triggered when the user adds/removes transitions." )
	end
	if event == obs.OBS_FRONTEND_EVENT_TRANSITION_DURATION_CHANGED then
		debugLog( 4 , "Triggered when the transition duration has been changed by the user." )
	end
	if event == obs.OBS_FRONTEND_EVENT_TBAR_VALUE_CHANGED then
		debugLog( 4 , "Triggered when the transition bar is moved." )
	end
	if event == obs.OBS_FRONTEND_EVENT_SCENE_COLLECTION_CHANGING then
		debugLog( 4 , "Triggered when the current scene collection is about to change." )
	end
	if event == obs.OBS_FRONTEND_EVENT_SCENE_COLLECTION_CHANGED then
		debugLog( 4 , "Triggered when the current scene collection has changed." )
	end
	if event == obs.OBS_FRONTEND_EVENT_SCENE_COLLECTION_LIST_CHANGED then
		debugLog( 4 , "Triggered when a scene collection has been added or removed." )
	end
	if event == obs.OBS_FRONTEND_EVENT_SCENE_COLLECTION_RENAMED then
		debugLog( 4 , "Triggered when a scene collection has been renamed." )
	end
	if event == obs.OBS_FRONTEND_EVENT_PROFILE_CHANGING then
		debugLog( 4 , "Triggered when the current profile is about to change." )
	end
	if event == obs.OBS_FRONTEND_EVENT_PROFILE_CHANGED then
		debugLog( 4 , "Triggered when the current profile has changed." )
	end
	if event == obs.OBS_FRONTEND_EVENT_PROFILE_LIST_CHANGED then
		debugLog( 4 , "Triggered when a profile has been added or removed." )
	end
	if event == obs.OBS_FRONTEND_EVENT_PROFILE_RENAMED then
		debugLog( 4 , "Triggered when a profile has been renamed." )
	end
	if event == obs.OBS_FRONTEND_EVENT_FINISHED_LOADING then
		debugLog( 4 , "Triggered when the program has finished loading." )
	end
	if event == obs.OBS_FRONTEND_EVENT_SCRIPTING_SHUTDOWN then
		debugLog( 4 , "Triggered when scripts need to know that OBS is exiting. The " )
		debugLog( 4 , "OBS_FRONTEND_EVENT_EXIT event is normally called after scripts " )
		debugLog( 4 , "have been destroyed." )
	end
	if event == obs.OBS_FRONTEND_EVENT_EXIT then
		debugLog( 4 , "Triggered when the program is about to exit." )
	end
	if event == obs.OBS_FRONTEND_EVENT_REPLAY_BUFFER_STARTING then
		debugLog( 4 , "Triggered when the replay buffer is starting." )
	end
	if event == obs.OBS_FRONTEND_EVENT_REPLAY_BUFFER_STARTED then
		debugLog( 4 , "Triggered when the replay buffer has successfully started." )
	end
	if event == obs.OBS_FRONTEND_EVENT_REPLAY_BUFFER_STOPPING then
		debugLog( 4 , "Triggered when the replay buffer is stopping." )
	end
	if event == obs.OBS_FRONTEND_EVENT_REPLAY_BUFFER_STOPPED then
		debugLog( 4 , "Triggered when the replay buffer has fully stopped." )
	end
	if event == obs.OBS_FRONTEND_EVENT_REPLAY_BUFFER_SAVED then
		debugLog( 4 , "Triggered when the replay buffer has been saved." )
	end
	if event == obs.OBS_FRONTEND_EVENT_STUDIO_MODE_ENABLED then
		debugLog( 4 , "Triggered when the user has turned on studio mode." )
	end
	if event == obs.OBS_FRONTEND_EVENT_STUDIO_MODE_DISABLED then
		debugLog( 4 , "Triggered when the user has turned off studio mode." )
	end
	if event == obs.OBS_FRONTEND_EVENT_PREVIEW_SCENE_CHANGED then
		debugLog( 4 , "Triggered when the current preview scene has changed in studio mode." )
	end
	if event == obs.OBS_FRONTEND_EVENT_SCENE_COLLECTION_CLEANUP then
		debugLog( 4 , "Triggered when a scene collection has been completely unloaded, " )
		debugLog( 4 , "and the program is either about to load a new scene collection, " )
		debugLog( 4 , "or the program is about to exit." )
	end
	if event == obs.OBS_FRONTEND_EVENT_VIRTUALCAM_STARTED then
		debugLog( 4 , "Triggered when the virtual camera is started." )
	end
	if event == obs.OBS_FRONTEND_EVENT_VIRTUALCAM_STOPPED then
		debugLog( 4 , "Triggered when the virtual camera is stopped." )
	end
	debugLog( 4 , "LEAVE: onEventCallback")
end
--
--	Function to show the visibility stats etc of all the sources that are used in a slideshow.
--
function logShowSourceVisStats()
	debugLog( 3 , "" )
	debugLog( 3 , "Current Show Source Stats are as follows:" )
	local sceneSourceObj = obs.obs_frontend_get_current_scene()											-- getObj sceneSourceObj
	local sceneSceneObj  = obs.obs_group_or_scene_from_source(sceneSourceObj)
	obs.obs_source_release(sceneSourceObj)																-- release sceneSourceObj
	local sceneItemObj = obs.obs_scene_find_source_recursive( sceneSceneObj, prmShowControlGroup )
	local source = obs.obs_get_source_by_name( prmShowControlGroup )									-- getObj source
	local stat = ""
	stat = stat .. ", CurVis:"..tf(obs.obs_sceneitem_visible(sceneItemObj))
	stat = stat .. ", Active:"..tf(obs.obs_source_active(source))
	stat = stat .. ", Showing:"..tf(obs.obs_source_showing(source))
	stat = stat .. ", Hidden:"..tf(obs.obs_source_is_hidden(source))
	obs.obs_source_release(source)																		-- release source
	debugLog( 3 , "Stat: prmShowControlGroup "..stat )
	for prm,srcdat in pairs(prmSourceNames) do
		if prmSourceNames[prm].sceneItemObj ~= nil then
			local stat = ""
			stat = stat .. ", CurVis:"..tf(obs.obs_sceneitem_visible(prmSourceNames[prm].sceneItemObj))
			stat = stat .. ", Active:"..tf(obs.obs_source_active    (prmSourceNames[prm].sourceObj))
			stat = stat .. ", Showing:"..tf(obs.obs_source_showing  (prmSourceNames[prm].sourceObj))
			stat = stat .. ", Hidden:"..tf(obs.obs_source_is_hidden (prmSourceNames[prm].sourceObj))
			if prm == "prmTargetMediaSource" then
				stat = stat .. ", Volume:"..obs.obs_source_get_volume(prmSourceNames[prm].sourceObj)
			end
			debugLog( 3 , "Stat: "..string.format("%-20s",prm)..stat )
		end
	end
	if prmBgAudioData.sourceObj ~= nil then
		local stat = ""
		stat = stat .. ", CurVis:N"
		stat = stat .. ", Active:"..tf(obs.obs_source_active   (prmBgAudioData.sourceObj))
		stat = stat .. ", Showing:"..tf(obs.obs_source_showing (prmBgAudioData.sourceObj))
		stat = stat .. ", Hidden:"..tf(obs.obs_source_is_hidden(prmBgAudioData.sourceObj))
		stat = stat .. ", Volume:"..obs.obs_source_get_volume  (prmBgAudioData.sourceObj)
		debugLog( 3 , "Stat: prmBgAudioFadeSource"..stat )
	end
	debugLog( 3 , "" )
end
--
--	Function callback that is invoked when the timer for displaying a image has expired
--	when this occurs, the image is set visibility false so it transitions to not
--	visible where it then triggers a source_deactivated callback where the next media item
--	is loaded and set to visible, so it would thus trigger a source_activated callback
--	where that callback would set a timer (in the case of an image) to wait for the image
--	to transition to visible and display until the timer fires - and the cycle continues.
--
function timer_ImageCallback()
	debugLog( 5 , "ENTER: timer_ImageCallback")
	--
	debugLog( 3 , "timer_ImageCallback Triggered, Remove Timer and Turn Off Visibility of "..prmTargetImageSource )
	obs.timer_remove(timer_ImageCallback)
	table.insert(ctx.set_visible, { item = prmSourceNames.prmTargetImageSource.sceneItemObj , delay = cbVisDelay , visible = false , name = prmSourceNames.prmTargetImageSource.value })
	--setSceneItemVisibility( prmTargetImageSource , false )
	--obs.obs_sceneitem_set_visible( prmSourceNames.prmTargetImageSource.sceneItemObj , false )
	--
	debugLog( 5 , "LEAVE: timer_ImageCallback")
end
--
--	Function invoked by OBS as a callback when the signal media_stopped occurs.
--	We do not care about this callback as we have seen that in the OBS Media source that
--	when the user presses the Stop button on the media player, we do get this signal
--	which is then immediately followed by media_ended signal/callback.  Thus, getting this
--	signal is rather useless for our needs.
--
function mediaStoppedCallback(callDataa)
	debugLog( 5 , "ENTER: mediaStoppedCallback")
	if gbl_activatedState then
		debugLog( 3 , "Show active, media_stopped signal occured. Ignoring... SlideType="..activeSlideTypeString )
	else
		debugLog( 5 , "Show NOT active, media_stopped signal occured. Ignoring... SlideType="..activeSlideTypeString )
	end
	debugLog( 5 , "LEAVE: mediaStoppedCallback")
end
--
--	Function invoked by OBS as a callback when the signal media_ended occurs.
--	This happens when the media ends (plays to end) or if the user presses the player
--	Stop button (signal media_stopped - see above media_stopped callback).
--
function mediaEndedCallback(callData)
	debugLog( 4 , "ENTER: mediaEndedCallback")
	if gbl_activatedState then
		if activeSlideType == slideTypeMedia then
			debugLog( 3 , "Show active, media_ended signal occured. Ending this Media, SlideType="..activeSlideTypeString )
			--	Might want to change the source to an empty filespec here???
			--	Set the source to not visible to generate a source_deactivated invocation
			table.insert(ctx.set_visible, { item = prmSourceNames.prmTargetMediaSource.sceneItemObj ,
										   delay = cbVisDelay , visible = false ,
										   name = prmSourceNames.prmTargetMediaSource.value })
		else
			debugLog( 2 , "Show active, media_ended signal occured. But MediaType Mismatch: "..activeSlideTypeString..", a WTF incident." )
		end
	else
		debugLog( 2 , "Show NOT active, media_ended signal occured. Event Ignored... Current SlideType="..activeSlideTypeString )
	end
	debugLog( 4 , "LEAVE: mediaEndedCallback")
end
--
--	script_tick
--	Auto called by OBS at every tick of the life of the running OBS (while the script is loaded)
--	it is a bit worth mentioning that each call to this function seems to occur at the defined
--	framerate the user has configured. ie: 60fps, 30fps etc.
--	I did not include script ENTER/LEAVE debugs.  Want this function kept lean as its called a lot.
--	Eventually, will comment out debugs etc...  Eventually... :-)
--
function script_tick (seconds)
	--debugLog(0,"script_tick: "..seconds)
	--
	--	The following is a construct that allows the script to perform a delay and then
	--	perform a set_sceneitem_visible per the table data set elsewhere.  Forgot where I
	--	got this core chunk of code - but Huge Massive Thanks to that person!!!
	--
    local i = 1
    while i <= #ctx.set_visible do
		debugLog( 5 , "script_tick - in ctx.set_visible loop "..seconds.." , delayCountdown: "..ctx.set_visible[i].delay )
		ctx.set_visible[i].delay = ctx.set_visible[i].delay - (seconds * 1000)
		if ctx.set_visible[i].delay <= 0 then
			local wasVis = obs.obs_sceneitem_visible(ctx.set_visible[i].item)
			debugLog( 3 , "script_tick - Setting visibility on item "..ctx.set_visible[i].name.." to: "..sfbool(ctx.set_visible[i].visible).." Was: "..sfbool(wasVis) )
			obs.obs_sceneitem_set_visible(ctx.set_visible[i].item, ctx.set_visible[i].visible)
			table.remove(ctx.set_visible, i)
		else
			i = i + 1
		end
    end
	--
	--	The following is a construct to fade the volume up or down on a source
	--	for the time duration desired.  The time is split into script_tick steps.
	--	Note pending numbers plugged in, a fade can reach a ToVol before the steps
	--	run out as the looping is controlled by fade time/seconds not watching for
	--	the closing in on the target. Updated, Got a check for this in the code now.
	--
	local j = 1
    while j <= #ctx.set_audioFade do
		local msElapsed = 1000 * seconds
		local cSteps = ctx.set_audioFade[j].fTime / msElapsed				-- compute increments of volume change
		debugLog( 5 , "script_tick - ctx.set_audioFade "..seconds.." , fadeCountdown: "..ctx.set_audioFade[j].fTime..", msElapsed: "..msElapsed..", cSteps: "..cSteps )
		ctx.set_audioFade[j].fTime = ctx.set_audioFade[j].fTime - msElapsed
		if ctx.set_audioFade[j].fTime <= 0 then
			debugLog( 3 , "script_tick - Final Set Volume on: "..ctx.set_audioFade[j].name.." to: "..ctx.set_audioFade[j].toVol )
			obs.obs_source_set_volume(ctx.set_audioFade[j].item, ctx.set_audioFade[j].toVol)
			if ctx.set_audioFade[j].rlSrc then
				obs.obs_source_release(ctx.set_audioFade[j].item)			-- release SourceObj Flagged to do by end of show stuff
			end
			table.remove(ctx.set_audioFade, j)
		else
			local volIncr = ctx.set_audioFade[j].wkVol - ctx.set_audioFade[j].toVol
			if volIncr == 0 then
				debugLog( 3 , "script_tick - Early To-Volume reached, Final Set Volume on: "..ctx.set_audioFade[j].name.." to: "..ctx.set_audioFade[j].toVol )
				obs.obs_source_set_volume(ctx.set_audioFade[j].item, ctx.set_audioFade[j].toVol)
				if ctx.set_audioFade[j].rlSrc then
					obs.obs_source_release(ctx.set_audioFade[j].item)			-- release SourceObj Flagged to do by end of show stuff
				end
				table.remove(ctx.set_audioFade, j)
			else
				if cSteps ~= 0 then
					volIncr = volIncr / cSteps
				end
				ctx.set_audioFade[j].wkVol = ctx.set_audioFade[j].wkVol - volIncr
				debugLog( 4 , "script_tick - Changing Volume by Increment: "..volIncr.." to: "..ctx.set_audioFade[j].wkVol )
				obs.obs_source_set_volume(ctx.set_audioFade[j].item, ctx.set_audioFade[j].wkVol)
			end
		end
		j = j + 1
    end
	--
	--	The following is a construct that allows the script to perform a delay and then
	--	perform a set_current_scene and then release the source used for the operation.
	--
    local k = 1
    while k <= #ctx.set_scene do
		debugLog( 5 , "script_tick - in ctx.set_scene loop "..seconds.." , delayCountdown: "..ctx.set_scene[k].delay )
		ctx.set_scene[k].delay = ctx.set_scene[k].delay - (seconds * 1000)
		if ctx.set_scene[k].delay <= 0 then
			debugLog( 2 , "script_tick - Now Setting Scene "..ctx.set_scene[k].name )
			obs.obs_source_release(ctx.set_scene[k].item)									-- release sceneSourceObj - see show shutdown code b4 or after?
			obs.obs_frontend_set_current_scene(ctx.set_scene[k].item)
			table.remove(ctx.set_scene, k)
		else
			k = k + 1
		end
    end
	--
end
--
--	Function invoked when things in the loaded function setup a signal handler for them, change their visibility
--	doc say the signal returns these args - ptr scene, ptr item, bool visible
--	have to check lua wrapper stuff to see if callData is actually the right thing.
--
function src_visible(callData)
    local targetVis  = obs.calldata_bool(callData,"visible")
    local itemObj    = obs.calldata_sceneitem(callData,"item")
    local source     = obs.obs_sceneitem_get_source(itemObj)
    local sourceName = obs.obs_source_get_name(source)
	debugLog( 3 , "ENTER: src_visible - "..sourceName )
	local stat =   ", TargetVis:"..tf(targetVis)
	stat = stat .. ", CurVis:"..tf(getSceneItemVisibility(itemObj))
	stat = stat .. ", Active:"..tf(obs.obs_source_active(source))
	stat = stat .. ", Showing:"..tf(obs.obs_source_showing(source))
	stat = stat .. ", Hidden:"..tf(obs.obs_source_is_hidden(source))
	debugLog( 2 , "src_visible - "..sourceName..stat )
	debugLog( 3 , "LEAVE: src_visible")
end
--
--	Function callback when vis changes on a source with a target visibility change to true.
--	This seems to always execute immediately after src_visible callback (again, based on the target visibility t/f)
--	It has also been observed that after these show/hide callbacks, the next thing that gets a callback is source_activated or source_deactivated
--
function source_show(callData)
	local source = obs.calldata_source(callData, "source")
	local sourceName = obs.obs_source_get_name( source )
	local stat = "Active:"..sfbool(obs.obs_source_active(source))..", Showing:"..sfbool(obs.obs_source_showing(source))..", Hidden:"..sfbool(obs.obs_source_is_hidden(source))
	debugLog( 3 , "ENTER: source_show - "..sourceName..", "..stat )
	debugLog( 3 , "LEAVE: source_show")
end
--
--	Function callback when vis changes on a source with a target visibilty change to false.
--	This seems to always execute immediately after src_visible callback (again, based on the target visibility t/f)
--	It has also been observed that after these show/hide callbacks, the next thing that gets a callback is source_activated or source_deactivated
--
function source_hide(callData)
	local source = obs.calldata_source(callData, "source")
	local sourceName = obs.obs_source_get_name( source )
	debugLog( 3 , "ENTER: source_hide - "..sourceName )
	--
	if sourceName == prmShowControlGroup then
		--
		--	Our group that controls all is being DEactivated.
		--	This constitutes the Ending of the show, or a user interrupt.
		--	It is not deactivated - yet, but it is on its way.
		--	Our notion of action here is that we want and need to shutdown whatever media is up and running NOW.
		--	These things need to be done before the internals of the Group deactivation beat us to the punch of
		--	initiating deactivation of the Media, Image and Text sources under its control.
		--
		--	Then we will let the rest of the flow take care of things.
		--	The user or some/this automation must have overtly deactivated the Group
		--
		if activeSlideRunning then
			debugLog( 2 , "Show Interrupt - Slide "..activeSlideTypeString.." Still Running, User Interrupt!!!! - Initiate Show Shutdown." )
			--
			--	Show was interrupted
			--	Need to set vis to false on sceneItemObj of whatever media type is still running, so it will naturally itself
			--	go into deactivation.  This will make it ask for the next item but that code will know to return the **STOP**
			--	code so the overall show exits cleanly.
			--
			gbl_ShowInterrupt = true
			if activeSlideType == slideTypeImage then
				obs.timer_remove(timer_ImageCallback)
				obs.obs_sceneitem_set_visible( prmSourceNames.prmTargetImageSource.sceneItemObj , false )	-- do now, not after source_hide finishes
			end
			if activeSlideType == slideTypeMedia then
				-- No timer to remove for media, I suppose the source stops itself as it deactivates
				-- When the vis change occurs, the source signals media_stopped and in turn media_ended
				-- which would then trigger its media_ended callback which will set vis to false, which is already
				-- and things end up back here in deactivate (below) to get a stop from the next item request.
				-- Thus, the show winds down.
				obs.obs_sceneitem_set_visible( prmSourceNames.prmTargetMediaSource.sceneItemObj , false )	-- do now, not after source_hide finishes
			end
		else
			--	No slide is running.  So this must be just a normal shutdown (media ran out normally, non interrupt).
			--	Here, we do not have to do anything.
		end
		logShowSourceVisStats()
	end
	debugLog( 3 , "LEAVE: source_hide")
end
--
--	Function to take a filespec and make it absolute as needed with the help of prmHomeFolderPath
--
function makePathAbsolute( fileSpec )
	local rtnFileSpec = fileSpec
	if isPlatformWindows() then
		-- on Windows a file is absolute path if it has a device at front.
		-- Not thinking about UNC paths at this time either.
		local aDevice = string.match(fileSpec,"^([%u%l]:)" )
		if aDevice == nil or aDevice == "" then
			-- no device, must be relative, then construct full path
			rtnFileSpec = prmHomeFolderPath.."\\"..fileSpec
		end
	else
		-- for this purpose, MacOS and Linux same - *nix
		local aLeadingSlash = string.match(fileSpec,"^(/)")
		if aLeadingSlash == nil or aLeadingSlash == "" then
			-- no device, must be relative, then construct full path
			rtnFileSpec = prmHomeFolderPath.."/"..fileSpec
		end
	end
	return rtnFileSpec
end
--
--	Function to do the work of getting the next media item for the show and changing relevant
--	sources with the new/next media item.  It also decides the media type and returns both the
--	next item(filespec) and the matching slideType.  Of course it also updates the text source
--	which basically always comes alone for the ride with the overall slideshow.
--
function setupNextItemIntoSources()
	debugLog( 3 , "ENTER: setupNextItemIntoSources")
	--
	--	Just in case the IMAGE or MEDIA sources are not defined, we need to loop here until we
	--	have a media type slide that is acceptable.  Otherwise, get the next item until one
	--	that is acceptable or the show ends.  Part of the problem is what happens if NO Media and
	--	no Image sources are defined...  We could get into a place where nothing happens and the
	--	show hangs.  The whole premise of the show cycling is based on the events of the sources
	--	activating/deactivating based on visibility changes.  It would seem that either Image or
	--	Media sources could be blank but NOT BOTH.
	--
	local nextItem     = ""
	local nextItemAbs  = ""
	local slideType    = slideTypeNone
	local slideString  = "slideTypeNone"
	local okayToReturn = false
	repeat
		nextItem    = getNextMediaItem()
		nextItemAbs = makePathAbsolute( nextItem )
		debugLog( 3 , "nextItemAbs spec is:"..nextItemAbs )
		slideType   = slideTypeNone			-- actually yet to be determined
		slideString = "slideTypeNone"		-- actually yet to be determined
		--
		if nextItem == "**STOP**" then
			okayToReturn = true
		else
			activeLastSlideType = activeSlideType
			--
			--	To find and accept a next item, the target source name must be non blank (sceneItemObj ~= nil) and
			--	it must have a beginVisibility of true (was showing and ought be used, otherwise ignored).
			--	This is true for both IMAGE and MEDIA.  This way, if the source was set off in the group and they
			--	start the show, we ignore all items in the list for that source.  We ought be able to observe that
			--	a show of all pictures, and that source is off, then the show effectively runs to end doing nothing.
			--
			local gotValidType = false
			local typeWasUsed  = false
			local typeWasType  = slideString
			local sourceExists = nil
			local beganVisible = nil
			if isTypeMedia( nextItem ) then
				gotValidType = true
				--
				sourceExists = prmSourceNames.prmTargetMediaSource.sceneItemObj ~= nil
				beganVisible = prmSourceNames.prmTargetMediaSource.beginVisibility
				--
				if  sourceExists and beganVisible then
					typeWasUsed = true
					slideType   =  slideTypeMedia
					slideString = "slideTypeMedia"
					debugLog( 3 , "Updating: "..prmTargetMediaSource..":local_file to Item: "..nextItem )
					changeSourceSetting( prmTargetMediaSource, "local_file" , nextItemAbs , "string" )
					if activeLastSlideType ~= slideType and prmSourceNames.prmTargetImageSource.sceneItemObj ~= nil then
						-- arguably, this step is not even needed. But using a lastSlideType allows this to not happen EVERY time
						debugLog( 3 , "Clearing: "..prmTargetImageSource..":file to blank. Slide Type Not Same as Last" )
						changeSourceSetting( prmTargetImageSource, "file" , "" , "string" )
					end
				end
			end
			if isTypeImage( nextItem ) then
				gotValidType = true
				--
				sourceExists = prmSourceNames.prmTargetImageSource.sceneItemObj ~= nil
				beganVisible = prmSourceNames.prmTargetImageSource.beginVisibility
				--
				if  sourceExists and beganVisible then
					typeWasUsed = true
					slideType   =  slideTypeImage
					slideString = "slideTypeImage"
					debugLog( 3 , "Updating: "..prmTargetImageSource..":file to Item: "..nextItem )
					changeSourceSetting( prmTargetImageSource, "file" , nextItemAbs , "string" )
					if activeLastSlideType ~= slideType and prmSourceNames.prmTargetMediaSource.sceneItemObj ~= nil then
						-- arguably, this step is not even needed. But using a lastSlideType allows this to not happen EVERY time
						debugLog( 3 , "Clearing: "..prmTargetMediaSource..":local_file to blank. Slide Type Not Same as Last" )
						changeSourceSetting( prmTargetMediaSource, "local_file" , "" , "string" )
					end
				end
			end
			if gotValidType then
				if typeWasUsed then
					--
					--	Decide if the Text source ought be setup
					--	If the text source is not currently visible, then skip loading a new entry into it.
					--	This is probably becasue of the cmdTextQuiet bool from the bang on the MediaCollectioCommand
					--	specified for this show.  COuld have just checked that bool here instead of checking
					--	visibility state.  But at startup, if that bool was set, then the text source was set
					--	to be invisible. 
					--
					okayToReturn = true
					if obs.obs_sceneitem_visible( prmSourceNames.prmTargetTextSource.sceneItemObj ) then
						if  prmSourceNames.prmTargetTextSource.sceneItemObj ~= nil
						and prmSourceNames.prmTargetTextSource.beginVisibility then
							local pathText = "- "..trimPathFolderLevels ( prmFolderTrimOnLeft , prmFolderTrimLevel , nextItem ).." -"
							debugLog( 3 , "Updating: "..prmTargetTextSource..":text to Item: "..pathText )
							changeSourceSetting( prmTargetTextSource, "text" , pathText , "string" )
						end
					end
				else
					debugLog( 3 , "Skip Item "..activeMediaIndex..", "..typeWasType..", sourceExists: "..sfbool(sourceExists)..", beganVisible: "..sfbool(beginVisible) )
					-- validType ignored due to source not defined or was not initially visible and ought be ignored.
				end
			else
				--
				--	ignore this item as it was not IMAGE OR MEDIA.
				--	junk file - ought have already screened when loaded out but reasonable to double check here.
				--	besides, if the loaded list was not screened so well, then we could have other file types
				--	processed that ought be skipped and later, with suitable extensions, could be processed. 6of1Hdo
				--
				debugLog( 3 , "Skip Item "..activeMediaIndex..", "..typeWasType..", List item was determined unknown/unusable..." )
			end
		end
	until okayToReturn
	--
	debugLog( 3 , "LEAVE: setupNextItemIntoSources - Returns 3 values, nextItem:"..nextItem..": , SlideType:"..slideType.."("..slideString..")" )
	return nextItem,slideType,slideString
end
--
--	Function to set the gbl_ShowInterrupt variable to let the next media request act like end of list/file.
--	Updated to now set vis on whatever slide type source is running to false to cause it immediate deactivation.
--	No more of this waiting for the current media to finish itself.  Images were always closed by timer firing and
--	this is no different.  Media is killed via vis change but hopefully it will tolerate it all fine.
--
function showSafeTerminateCallback(pressed)
	debugLog( 2 , "ENTER: showSafeTerminateCallback - pressed="..sfbool(pressed) )
	--	Came to see that pressed=true means the hotkey was being pressed, pressed=false=key being released.
	--	Thus, a single keypress results in two invocations, pressed and released.
	--	Seems a clever programmer could use this in a global so something like script_tick could know the key is
	--	still pressed from tick to tick and could do things while it is pressed and then something else when released.
	--	Be creative...
	if pressed then
		debugLog( 1 , "" )
		debugLog( 1 , "showSafeTerminateCallback has been invoked!" )
		debugLog( 1 , "" )
		gbl_ShowInterrupt = true
		gbl_ShowInterruptViaHotkey = true
		if gbl_activatedState then
			debugLog( 2 , "Show active, Ending Image/Media Source via set Visibility to false, SlideType="..activeSlideTypeString )
			if activeSlideType == slideTypeMedia then
				table.insert(ctx.set_visible, { item = prmSourceNames.prmTargetMediaSource.sceneItemObj ,
											   delay = cbVisDelay , visible = false ,
											   name = prmSourceNames.prmTargetMediaSource.value })
			end
			if activeSlideType == slideTypeImage then
				obs.timer_remove(timer_ImageCallback)
				table.insert(ctx.set_visible, { item = prmSourceNames.prmTargetImageSource.sceneItemObj ,
												delay = cbVisDelay , visible = false ,
												name = prmSourceNames.prmTargetImageSource.value })
			end
		else
			debugLog( 2 , "Show NOT active, Nothing to Interrupt/Stop" )
		end
	end
	debugLog( 2 , "LEAVE: showSafeTerminateCallback" )
end
--
--	Function to perform various shutdown things when the show ends or is made to end somehow
--
function timer_SlideShowShutdown_Callback()
	debugLog( 4 , "ENTER: timer_SlideShowShutdown_Callback" )
	--
	obs.remove_current_callback()
	gbl_TickSeconds = 0
	gbl_LoopCount = 0
	gbl_activatedState = false
	obs.timer_remove(timer_ImageCallback)
	activeSlideType = slideTypeNone
	activeMediaIndex = 0
	activeMediaList = {}
	activeMediaItem = ""
	countTargetTextSource  = 0
	countTargetImageSource = 0
	countTargetMediaSource = 0
	activeSlideRunning = false
	activeStartupWaiting = false
	activeShutdownWaiting = false
	activeWaitingCount = 0
	gbl_SceneEntryAutoStarting = false		-- ought not be important clear this, was done in start when show become active
	--
	--	Dump a stats view of the full set of sources in the show
	--
	logShowSourceVisStats()
	--
	-- 	Find and disconnect visibility, show and hide signal handler for the prmShowControlGroup
	--	Because we got into the show etc, we are expecting these next operations will return valid Obj items and not error 
	--
	local sceneSourceObj = obs.obs_frontend_get_current_scene()											-- getObj sceneSourceObj
	local sceneSceneObj  = obs.obs_group_or_scene_from_source(sceneSourceObj)
	obs.obs_source_release(sceneSourceObj)																-- release sceneSourceObj
	local tmpSceneItemObj = obs.obs_scene_find_source_recursive( sceneSceneObj, prmShowControlGroup )
	debugLog( 4 , "Disconnecting item_visible SignalHandlers for Group: "..prmShowControlGroup )
	local sh = obs.obs_source_get_signal_handler(obs.obs_sceneitem_get_source(tmpSceneItemObj))
	obs.signal_handler_disconnect(sh, "item_visible" ,src_visible)
	--
	--	Disconnect the show/hide signal handlers
	--
	debugLog( 4 , "Disconnecting source_show/hide SignalHandlers." )
	local sh = obs.obs_get_signal_handler()
	obs.signal_handler_disconnect(sh, "source_show"  ,source_show)
	obs.signal_handler_disconnect(sh, "source_hide"  ,source_hide)
	--
	--	We have to do the inverse of setup/start operations on the MEDIA source. Disconnect signal handlers, restore states.
	--
	if prmSourceNames.prmTargetMediaSource.sceneItemObj ~= nil then
		debugLog( 5 , "Disconnecting media_ended/stopped callbacks for source: "..prmTargetMediaSource )
		local sh = obs.obs_source_get_signal_handler(prmSourceNames.prmTargetMediaSource.sourceObj)
		obs.signal_handler_disconnect(sh, "media_ended"  ,mediaEndedCallback)
		obs.signal_handler_disconnect(sh, "media_stopped",mediaStoppedCallback)
		--	Restore original pre show settings
		changeSourceSetting ( prmTargetMediaSource , "local_file" , prmSourceNames["prmTargetMediaSource" ].beginItemValue , "string" )
	end
	--
	--	We have to do some work on the IMAGE source.
	--
	if prmSourceNames.prmTargetImageSource.sceneItemObj ~= nil then
		--	Restore original pre show settings
		changeSourceSetting ( prmTargetImageSource , "file" , prmSourceNames["prmTargetImageSource" ].beginItemValue , "string" )
	end
	--
	--	We have to do some work on the TEXT source.
	--
	if prmSourceNames.prmTargetTextSource.sceneItemObj ~= nil then
		--	Restore original pre show settings
		changeSourceSetting ( prmTargetTextSource , "text" , prmSourceNames["prmTargetTextSource" ].beginItemValue , "string" )
	end
	--
	for prm,srcdat in pairs(prmSourceNames) do
		if prmSourceNames[prm].sceneItemObj ~= nil then
			-- some to none of these could/ought be nil.
			debugLog( 3 , "Restoring Original Visibility of "..sfbool(prmSourceNames[prm].beginVisibility).." to Source "..prm.." of name: "..prmSourceNames[prm].value )
			obs.obs_sceneitem_set_visible( prmSourceNames[prm].sceneItemObj , prmSourceNames[prm].beginVisibility )
		end
	end
	--
	if gbl_SceneRecFlags.endSceneEndRecord then
		--	need to fade bg audio to zero and continue to next scene
		--	do not stop recording
		if prmBgAudioData.sourceObj ~= nil then
			local curVolume = obs.obs_source_get_volume(prmBgAudioData.sourceObj)
			if curVolume > 0 then
				--
				--	Have to preserve the original volume of the BgAudio Source for possible future needs.
				--
				gbl_LastBgVolume = prmBgAudioData.origVolume
				--
				debugLog( 4 , "Show End, Next-Scene:"..gbl_ShowNextScene..", Fade To Zero, CurVol: "..curVolume..", time: "..prmBgAudioData.fadeTime )
				table.insert(ctx.set_audioFade, { 	item  = prmBgAudioData.sourceObj    ,		-- the sourceObj needed for the API call to change volume
													name  = prmBgAudioData.sourceName   ,		-- just the name for debug output
													fTime = prmBgAudioData.fadeTime * 2 ,		-- working time for the fade, decrements until done
													wkVol = curVolume                   ,		-- working volume, decrements toward fadedVolume by computed (signed) vol steps per script_tick
													toVol = 0 ,									-- destination volume, last script_tick step set vol to this value
													rlSrc = true
												} )
			else
				-- If decided to not use a last Script_tick to final adjust the volume, gotta release that source obj yet.
				obs.obs_source_release(prmBgAudioData.sourceObj)										-- release sceneSourceObj
			end
		end
	else
		--	Restore BG Audio to original volume if needed...
		if prmBgAudioData.sourceObj ~= nil then
			local curVolume = obs.obs_source_get_volume(prmBgAudioData.sourceObj)
			if curVolume < prmBgAudioData.origVolume then
				debugLog( 4 , "Orig Vol: "..prmBgAudioData.origVolume..", curVolume: "..curVolume.." --> fadedVolume: "..prmBgAudioData.fadedVolume..", time: "..prmBgAudioData.fadeTime )
				debugLog( 3 , "Restoring Original Volumne back to BG Audio Source: "..prmBgAudioData.sourceName )
				table.insert(ctx.set_audioFade, { 	item  = prmBgAudioData.sourceObj  ,		-- the sourceObj needed for the API call to change volume
													name  = prmBgAudioData.sourceName ,		-- just the name for debug output
													fTime = prmBgAudioData.fadeTime   ,		-- working time for the fade, decrements until done
													wkVol = curVolume                 ,		-- working volume, decrements toward fadedVolume by computed (signed) vol steps per script_tick
													toVol = prmBgAudioData.origVolume ,		-- destination volume, last script_tick step set vol to this value
													rlSrc = true
												} )
			else
				-- If decided to not use a last Script_tick to final adjust the volume, gotta release that source obj yet.
				obs.obs_source_release(prmBgAudioData.sourceObj)										-- release sceneSourceObj
			end
		end
	end
	--
	--
	--	Dump a stats view of the full set of sources in the show
	--
	logShowSourceVisStats()
	--
	--	Read a posting that seems to say that having an event callback in place when trying to change a scene
	--	causes a hang/lock to occur - just what I have been seeing also.  Yep, this works!
	--
	obs.obs_frontend_remove_event_callback( onEventCallback )				-- Turn off this event callback
	--
	--	Seems to be fully complete in undoing things as much as possible when finished,
	--	it appears that I ought also unregister the hotkey.  But, does this just remove the callback
	--	and leave the registered hotkey in the OBS settings???  I want that to stay!!!!
	--	we need to keep this thing active as we do show start/end cycles across scenes
	--
	--obs.obs_hotkey_unregister(showSafeTerminateCallback)
	--
	activeStartupWaiting = true
	activeWaitingCount = 0
	obs.timer_add( timer_ShutWaitForBgAudio_Callback , 10 )
	--
	debugLog( 4 , "LEAVE: timer_SlideShowShutdown_Callback" )
end
--
--	Function to wait for any Bg Audio to finish any fading it may be doing.
--	When done, it moves to a function that stops the recording and wait for its full stop.
--	Then, when that is done, then it goes to the switch to next scene function.
--
function timer_ShutWaitForBgAudio_Callback()
	debugLog( 4 , "ENTER: timer_ShutWaitForBgAudio_Callback" )
	obs.remove_current_callback()
	local maxWaitCount = 8																	-- an arbitrary max wait count, for safety
	if prmBgAudioData.sourceObj ~= nil then													-- not using this unless I MUST wait for Bg-Audio
		if prmBgAudioData.fadeTime ~= 0 then
			-- the divisor of 50 here must match the timer each wait cycle.
			maxWaitCount = ( 2 * prmBgAudioData.fadeTime / 50 ) + 20						-- ok, padding is kind of arbitrary, just for safety anyway
		end
	end
	--
	--	For this code, we are not needing to check if a fade is needed or not, we are just waiting for any fade that
	--	may be in process in the script_tick side of things.
	--
	repeat
		activeWaitingCount = activeWaitingCount + 1
		debugLog( 3 , "bgAudioWait - Entered - count: "..activeWaitingCount.." ctx.set_audioFade Size: "..#ctx.set_audioFade )
		if activeWaitingCount <= maxWaitCount then
			if #ctx.set_audioFade == 0 then
				debugLog( 2 , "timer_ShutWaitForBgAudio_Callback - Done Waiting for Bg-Audio Ready. WaitCount="..activeWaitingCount )
				activeStartupWaiting = false
				--	However, I would like to see a tiny bit more pause before the recording stops.  It seems
				--	to my ear that there is a lag between what it says and is.
				obs.os_sleep_ms(300)
			else
				debugLog( 2 , "LEAVE: timer_ShutWaitForBgAudio_Callback - Wait some More... WaitCount="..activeWaitingCount )
				obs.timer_add( timer_ShutWaitForBgAudio_Callback , 50 )
				return
			end
		else
			debugLog( 2 , "timer_ShutWaitForBgAudio_Callback - Give Up, Too Many Retries on BgAudi Wait. WaitCount="..activeWaitingCount )
			activeStartupWaiting = false				-- Not Happy - we had to give up for too many reties - troubleshoot this.
		end
	until not activeStartupWaiting			-- This loop ought not ever iterate more than once, every time
	--
	--	Getting here means that, if any ctx.set_audioFade operation was in progress, it is now done.
	--
	activeStartupWaiting = true
	activeWaitingCount = 0
	obs.timer_add( timer_StopRecordAndWait_Callback , 10 )
	--
	debugLog( 4 , "LEAVE: timer_ShutWaitForBgAudio_Callback - Callback set for: timer_StopRecordAndWait_Callback" )
end
--
--	Function to stop recording (if requested and if active) and then wait for it to come to full stop.
--	Then, when that is done, then it goes to the switch to next scene function.
--
function timer_StopRecordAndWait_Callback()
	debugLog( 4 , "ENTER: timer_StopRecordAndWait_Callback" )
	obs.remove_current_callback()
	-- 200 waits of 5ms is only a timeout max give up time of 10 seconds.
	local maxWaitCount = 400																	-- an arbitrary max wait count, for safety
	local recordingActive = false
	repeat
		activeWaitingCount = activeWaitingCount + 1
		recordingActive = obs.obs_frontend_recording_active()
		debugLog( 3 , "recordingStop - Entered - count: "..activeWaitingCount..", recActive:"..sfbool(recordingActive) )
		if activeWaitingCount <= maxWaitCount then
			if gbl_SceneRecFlags.endSceneEndRecord and gbl_ShowNextScene == "" then
				-- Record Stop is requested
				if not gbl_RecordStopping and recordingActive then
					-- effectively the 1st time here, stop recording
					obs.obs_frontend_recording_stop()
					gbl_RecordStopping = true
					debugLog( 2 , "LEAVE: timer_StopRecordAndWait_Callback - Recording Stopping, Begin Waiting. WaitCount="..activeWaitingCount )
					obs.timer_add( timer_StopRecordAndWait_Callback , 50 )
					return
				else
					--	Now we are waiting - so far, we are assuming that the API call to check if recording is active
					--	will not come false until it is successfully stopped.
					if recordingActive then
						debugLog( 2 , "LEAVE: timer_StopRecordAndWait_Callback - Waiting for Recording to be Stop. WaitCount="..activeWaitingCount )
						obs.timer_add( timer_StopRecordAndWait_Callback , 50 )
						return
					else
						if activeWaitingCount == 1 then
							gbl_RecordWasInactive = true
						end
						debugLog( 2 , "timer_StopRecordAndWait_Callback - Done Waiting Recording Stop. WaitCount="..activeWaitingCount )
						activeStartupWaiting = false		-- Done Waiting
						gbl_RecordStopped = true			-- Recording is inactive
					end
				end
			else
				-- Recording startup is NOT requested
				debugLog( 2 , "timer_StopRecordAndWait_Callback - Recording STOP NOT Needed, Do Nothing, Proceeding..." )
				activeStartupWaiting = false
			end
		else
			debugLog( 2 , "timer_StopRecordAndWait_Callback - Give Up, Too Many Retries on Recording Stop/Wait. WaitCount="..activeWaitingCount )
			activeStartupWaiting = false				-- Not Happy - we had to give up for too many reties - troubleshoot this.
		end
	until not activeStartupWaiting			-- This loop ought not ever iterate more than once, every time
	--
	gbl_RecordStopping = false		-- just to clean up on the way out
	--
	--	Getting here means that, IF Recording Stop was called for it is now stopped,
	--	Before leaving this code to get to the next step, there is one last thing to do.
	--	If we faded out the a BgAudio source to zero, so we could stop the recording,
	--	then we need to reset the volume back to its original full volume level so its
	--	there for some next time.  If we leave it at zero, then that becomes the next
	--	starting point, which is probably wrong.
	--
	if gbl_SceneRecFlags.endSceneEndRecord and gbl_ShowNextScene == "" and prmBgAudioData.sourceObj ~= nil then
		obs.obs_source_set_volume(prmBgAudioData.sourceObj,prmBgAudioData.origVolume)
	end
	--
	activeStartupWaiting = true
	activeWaitingCount = 0
	obs.timer_add( timer_SwitchToNextScene_Callback , 10 )
	--
	debugLog( 4 , "LEAVE: timer_StopRecordAndWait_Callback - Callback set for: timer_SwitchToNextScene_Callback" )
end
--
--	Function has misleading name - will switch to a next scene if specified but
--	before doing so, will wait (if needed) for recording to become inactive and BgAudio fade to finish if fading
--
function timer_SwitchToNextScene_Callback()
	debugLog( 4 , "ENTER: timer_SwitchToNextScene_Callback" )
	obs.remove_current_callback()
	--
	--	Getting here means that any Recording Stop and or Bg Audio fade operations are all done.
	--	We can now go ahead and change to the NextScene - if any...
	--	If not, then basically its the end of the show and all final cleanup
	--
	if not gbl_ShowInterrupt then
		if prmSceneAutoStart then
			if gbl_ShowNextScene ~= "" then
				local sceneSourceObj = obs.obs_get_source_by_name( gbl_ShowNextScene )					-- getObj sceneSourceObj
				--obs.obs_source_release(sceneSourceObj)												-- release occurs in script_tick w/scene change
				debugLog( 3 , "Setting script_tick delayed change scenes function. Target Source: "..gbl_ShowNextScene )
				table.insert( ctx.set_scene, { item = sceneSourceObj , delay = 10 , name = gbl_ShowNextScene } )
			else
				debugLog( 3 , "No attempt to switch scenes as there is no Next Scene Defined!" )
			end
		else
			debugLog( 3 , "No attempt to switch to scene:"..gbl_ShowNextScene..": (if defined) as Show SceneAutoStart is Disabled!" )
		end
	else
		debugLog( 3 , "No attempt to switch to scene:"..gbl_ShowNextScene..": (if defined) as the show was interrupted!" )
	end
	--
	debugLog( 4 , "LEAVE: timer_SwitchToNextScene_Callback" )
end
--
--	Function to come into play moments after the prmShowControlGroup becomes deactivated.
--
function timer_ShutdownCallback()
	debugLog( 3 , "ENTER: timer_ShutdownCallback" )
	obs.remove_current_callback()
	showEndTime = os.time()		--	The show ends - when? Now!
	local showBegClock = os.date( "%H:%M:%S" , showBegTime )
	local showEndClock = os.date( "%H:%M:%S" , showEndTime )
	local ssElapsedTime = os.difftime( showEndTime , showBegTime )
	debugLog( 1 , "" )
	debugLog( 1 , "Slideshow Statistics" )
	debugLog( 1 , "Slideshow Interrupted   = "..sfbool(gbl_ShowInterrupt) )
	debugLog( 1 , "Interrupted Via Hotkey  = "..sfbool(gbl_ShowInterruptViaHotkey) )
	debugLog( 1 , "Slideshow  Start  Time  = "..showBegClock )
	debugLog( 1 , "Slideshow   End   Time  = "..showEndClock )
	debugLog( 1 , "Slideshow Elapsed Time  = "..os.date("!%H:%M:%S",ssElapsedTime).." seconds." )
	debugLog( 1 , "Slideshow Loop Count    = "..gbl_LoopCount )
	debugLog( 1 , "Total Text  Items Shown = "..countTargetTextSource )
	debugLog( 1 , "Total Image Items Shown = "..countTargetImageSource )
	debugLog( 1 , "Total Media Items Shown = "..countTargetMediaSource )
	debugLog( 1 , "Grand Total Items Shown = "..countTargetImageSource + countTargetMediaSource.." (Note: text Items not included)" )
	debugLog( 1 , "Stopped at Media Slide# = "..activeMediaIndex )
	debugLog( 1 , "Stopped at Slide Type   = "..activeSlideTypeString )
	debugLog( 1 , "Loaded Media List Size  = "..#activeMediaList )
	debugLog( 1 , "" )
	debugLog( 1 , "Thank You - THE SHOW HAS ENDED -" )
	debugLog( 1 , "Thank You - THE SHOW HAS ENDED - I hope this passed your Audition." )
	debugLog( 1 , "Thank You - THE SHOW HAS ENDED -" )
	debugLog( 1 , "" )
	obs.timer_add( timer_SlideShowShutdown_Callback , 10 )
	debugLog( 1 , "" )
	debugLog( 3 , "LEAVE: timer_ShutdownCallback - All ought be quiet now (except recording stop, audio fades, scene changes etc)." )
end
--
--	Function to save some startup states in case things like a mid reset occur, original states were save for restoration
--
function saveAndSetStartupStates()
	debugLog( 4 , "ENTER: saveAndSetStartupStates" )
	--
	--	The show begins - when?
	--
	showBegTime  = os.time() -- Now, of course
	--
	local returnNow = false
	--
	prmPicDelayPeriod    = obs.obs_data_get_int   (gbl_settings, "PictureViewTime")
	prmBgAudioCutPercent = obs.obs_data_get_int   (gbl_settings, "BgAudioCutPercent")
	prmBgAudioFadeTime   = obs.obs_data_get_int   (gbl_settings, "BgAudioFadeTime")
	prmRandomizeShow     = obs.obs_data_get_bool  (gbl_settings, "RandomizeShow")
	--
	local msg = ""
	if  ( prmTargetImageSource == nil or prmTargetImageSource == "" )
	and ( prmTargetMediaSource == nil or prmTargetMediaSource == "" ) then
		msg = "Both IMAGE and MEDIA sources are blank, at least ONE of them MUST be defined."
		returnNow = true
	end
	--
	gbl_SceneRecFlags = { 	begSceneBegRecord=false,		-- when scene begins, set Bg Audio to 0, fade up (if defined) and start recording, waiting for ready
							endSceneEndRecord=false,		-- when scene ends,   fade Bg Audio to 0, stop recording if a Next-Scene is not specified
							VT={flag=false,valu=0},			-- Set/override Pic View Time      if falg=true
							AF={flag=false,valu=0},			-- Set/override BgAudio Fade Time  if flag=true
							AP={flag=false,valu=0},			-- Set/override Audio Fade Percent if flag=true
							RN={flag=false,valu=false},		-- Set/override RandomizeShow      if flag=true
							QT={flag=false,valu=false} }	-- Set/override Quiet Text view    if flag=true
	--
	--	Ensure that the user has defined a command to collect slides or nothing is going to happen.
	--
	local aScene,aCommand,nxtScene,recCtl = getMediaCmdDataForCurScene()
	if aCommand == "" then
		msg = "Media Collection Command undefined! - "..aScene
		returnNow = true
	else
		gbl_ShowSceneName = aScene
		gbl_ShowMediaCommand = aCommand
		gbl_ShowNextScene = nxtScene
		if gbl_ShowNextScene == "!" then gbl_ShowNextScene = "" end			-- Insurance ?? the ! ought not have been here
		gbl_SceneRecFlags = recCtl
	end
	--	Do all the overrides of settings here that can be done here.  TEXT is diff - see below vis set false on QT=T valu
	if gbl_SceneRecFlags.VT.flag then									-- Override settings Image View Period
		prmPicDelayPeriod = gbl_SceneRecFlags.VT.valu
		debugLog( 3 , "saveAndSetStartupStates - Override Settings PicDelayPeriod: "..prmPicDelayPeriod )
	end
	if gbl_SceneRecFlags.AF.flag then									-- Override settings Fade Time
		prmBgAudioFadeTime = gbl_SceneRecFlags.AF.valu
		debugLog( 3 , "saveAndSetStartupStates - Override Settings Bg Audio Fade Time: "..prmBgAudioFadeTime )
	end
	if gbl_SceneRecFlags.AP.flag then									-- Override settings Cut To Percent 
		prmBgAudioCutPercent = gbl_SceneRecFlags.AP.valu
		debugLog( 3 , "saveAndSetStartupStates - Override Settings Bg Audio Cut to Percent: "..prmBgAudioCutPercent )
	end
	if gbl_SceneRecFlags.RN.flag then									-- Override settings Randomize Show
		prmRandomizeShow = gbl_SceneRecFlags.RN.valu
		debugLog( 3 , "saveAndSetStartupStates - Override Settings Randomize Show: "..sfbool(prmRandomizeShow) )
	end
	--
	-- Find and attach visibility signal handler for the prmShowControlGroup
	--
	if prmShowControlGroup ~= nil and prmShowControlGroup ~= "" then
		local sceneSourceObj = obs.obs_frontend_get_current_scene()												-- getObj sceneSourceObj
		if sceneSourceObj ~= nil then
			local sceneSceneObj = obs.obs_group_or_scene_from_source(sceneSourceObj)
			obs.obs_source_release(sceneSourceObj)																-- release sceneSourceObj
			local tmpSceneItemObj = obs.obs_scene_find_source_recursive( sceneSceneObj, prmShowControlGroup )
			if tmpSceneItemObj ~= nil then
				if obs.obs_sceneitem_is_group(tmpSceneItemObj) then
					debugLog( 5 , "Disconnect/Connect item_visibility SignalHandler for Group: "..prmShowControlGroup )
					local sh = obs.obs_source_get_signal_handler(obs.obs_sceneitem_get_source(tmpSceneItemObj))
					--	it is interesting that I set this signal handler on the sceneitem (group) but I never see an invocation
					--	of the src_visible callback for changes to the Group itself, only it's children sources.
					obs.signal_handler_disconnect(sh, "item_visible" ,src_visible)				-- item_visible relates to scenes/groups, not plain sources
					obs.signal_handler_connect   (sh, "item_visible" ,src_visible)
				else
					msg = "prmShowControlGroup names a source that is not a Group: "..prmShowControlGroup
					returnNow = true
				end
			else
				msg = "prmShowControlGroup: "..prmShowControlGroup.." Not Found in the current scene."
				returnNow = true
			end
		else
			msg = "obs_frontend_get_current_scene unexpectedly returned nil."
			returnNow = true
		end
	else
		msg = "Required setting prmShowControlGroup is empty/nil."
		returnNow = true
	end
	if returnNow then
		-- These are intended to be hard errors.
		-- We want the error log to show up so they see it.
		local emsg = "Error - saveAndSetStartupStates - "..msg
		assert( false , emsg )
		debugLog( 4 , "LEAVE: saveAndSetStartupStates - "..msg )
		return false
	end
	--
	activeSlideType     = slideTypeNone
	activeLastSlideType = slideTypeNone
	activeMediaIndex = 0
	activeMediaList  = {}
	activeListIndexs = {}
	activeMediaItem  = ""
	gbl_activatedState = false
	activeSlideRunning = false
	gbl_ShowInterrupt  = false
	gbl_ShowInterruptViaHotkey = false
	activeStartupWaiting = false
	activeShutdownWaiting = false
	activeWaitingCount = 0
	--
	-- Keep this up to date this list/table/array
	--
	prmSourceNames["prmTargetTextSource"]  = {value=prmTargetTextSource ,beginVisibility=nil,sceneItemObj=nil,sourceObj=nil,beginItemValue=nil}
	prmSourceNames["prmTargetImageSource"] = {value=prmTargetImageSource,beginvisibility=nil,sceneItemObj=nil,sourceObj=nil,beginItemValue=nil}
	prmSourceNames["prmTargetMediaSource"] = {value=prmTargetMediaSource,beginvisibility=nil,sceneItemObj=nil,sourceObj=nil,beginItemValue=nil}
	--
	--	By setting up the SceneItemObj into this table before the slideshow	the code can directly
	--	use these items to do the work or at least not have to repeat all the lookup stuff each time.
	--	This avoids using other functions that constantly find these objects by name (saving work)
	--	and memory management with the constant releases needed by doing such finds.
	--
	--	Collecting sceneItemObj is based on the following essential core sequence of code.
	--
	--local sceneSourceObj = obs.obs_frontend_get_current_scene()										-- getObj sceneSourceObj
	--local sceneSceneObj  = obs.obs_group_or_scene_from_source(sceneSourceObj)
	--local sceneItemObj   = obs.obs_scene_find_source_recursive(sceneSceneObj,prmTargetImageSource)
	--obs.obs_source_release(sceneSourceObj)															-- release sceneSourceObj
	--
	local sceneSourceObj = obs.obs_frontend_get_current_scene()											-- getObj sceneSourceObj
	if sceneSourceObj ~= nil then
		local sceneSceneObj  = obs.obs_group_or_scene_from_source(sceneSourceObj)
		obs.obs_source_release(sceneSourceObj)															-- release sceneSourceObj
		for prm,srcdat in pairs(prmSourceNames) do
			if prmSourceNames[prm].value ~= nil and prmSourceNames[prm].value ~= "" then
				debugLog( 3 , "Collecting sceneItemObj and Visibility for SlideShow Source Item: "..prm.." of value: "..prmSourceNames[prm].value )
				local aSceneItemObj = obs.obs_scene_find_source_recursive( sceneSceneObj, prmSourceNames[prm].value )
				if aSceneItemObj ~= nil then
					prmSourceNames[prm].sceneItemObj    = aSceneItemObj
					prmSourceNames[prm].sourceObj       = obs.obs_sceneitem_get_source(aSceneItemObj)
					prmSourceNames[prm].beginVisibility = obs.obs_sceneitem_visible( aSceneItemObj )
				else
					msg = "obs_scene_find_source_recursive for "..prm.." returned nil"
					returnNow = true
				end
			else
				debugLog( 2 , "Warning! - "..prm.." is blank/nil. This source will not be used in the show.")
			end
		end
	else
		msg = "Unable to get SourceObj for current Scene! Something bad is going on."
		returnNow = true
	end
	if returnNow then
		-- These are intended to be hard errors.
		-- We want the error log to show up so they see it.
		local emsg = "Error - saveAndSetStartupStates - "..msg
		assert( false , emsg )
		debugLog( 4 , "LEAVE: saveAndSetStartupStates - "..msg )
		return false
	end
	--
	--	Since we now have checked our Media Collection Command as not blank (trusting), and we have already established
	--	key data about our sources present etc, we can now also load the list and peek at the first item to get its media
	--	type for any first slide Bg Audio initial fading settings.
	--	Also, if we get a **STOP** message back, we know the show will not start so we can head that off here also.
	--	NOTE: Since we are peeking ahead, we will have to Decr activeMediaIndex so the actual start gets same item
	--
	gbl_FirstSlideItem       = getNextMediaItem()
	gbl_FirstSlideType       = slideTypeNone
	gbl_FirstSlideTypeString = "slideTypeNone"
	activeMediaIndex = 0												-- Force back to zero to cause next get to get same thing
	if gbl_FirstSlideItem  == "**STOP**" then
		msg = "Initial Media Load returned **STOP**, Nothing Loaded! - "..aScene
		returnNow = true
	else
		-- Okay, got something
		if isTypeImage(gbl_FirstSlideItem) then
			gbl_FirstSlideType = slideTypeImage
			gbl_FirstSlideTypeString = "slideTypeImage"
		else
			gbl_FirstSlideType = slideTypeMedia
			gbl_FirstSlideTypeString = "slideTypeMedia"
		end
	end
	if returnNow then
		local emsg = "Error - saveAndSetStartupStates - "..msg
		--assert( false , emsg )
		debugLog( 4 , "LEAVE: saveAndSetStartupStates - "..msg )
		return false
	end
	--
	obs.obs_frontend_add_event_callback( onEventCallback )				-- Turn on this event callback - but at this time, it is unused
	--
	--	Now to setup for the Background Audio Source stuff
	--	prmBgAudioFadeSource
	--	prmBgAudioCutPercent
	--	prmBgAudioFadeTime
	--	void obs_source_set_volume(obs_source_t *source, float volume)
	--	float obs_source_get_volume(const obs_source_t *source)
	--	Sets/gets the user volume for a source that has audio output.
	--
	prmBgAudioData = { 	sourceName=prmBgAudioFadeSource,
						sourceObj=nil,
						cutToPercent=prmBgAudioCutPercent,
						fadeTime=prmBgAudioFadeTime,
						origVolume=0,
						fadedVolume=0
					 }
	--
	if prmBgAudioData.sourceName ~= nil and prmBgAudioData.sourceName ~= "" then
		prmBgAudioData.sourceObj = obs.obs_get_source_by_name( prmBgAudioData.sourceName )				-- getObj sourceObj
		if prmBgAudioData.sourceObj ~= nil then
			debugLog( 3 , "Setting up Background Audio Source etc. for "..prmBgAudioData.sourceName..", CutTo%: ".. prmBgAudioData.cutToPercent )
			--obs.obs_source_release( prmBgAudioData.sourceObj )										-- release sourceObj !!! Doing this in script_tick on final fade(restore).
			prmBgAudioData.origVolume = obs.obs_source_get_volume(prmBgAudioData.sourceObj)
			gbl_PrelaunchVolume = prmBgAudioData.origVolume												-- Insurance so far - TBD
			-- prmBgAudioData.cutToPercent is actually CUT TO PERCENT, Not CUT BY PERCENT
			prmBgAudioData.fadedVolume = ( prmBgAudioData.cutToPercent / 100 ) * prmBgAudioData.origVolume		
			debugLog( 3 , "Orig Vol: "..prmBgAudioData.origVolume.." for: "..prmBgAudioData.sourceName..", CutTo%: "..prmBgAudioData.cutToPercent.." fadedVolume: "..prmBgAudioData.fadedVolume )
		else
			debugLog( 3 , "Unable to setup Background Audio Fader Source for "..prmBgAudioData.sourceName..", get_source_by_name returned nil." )
		end
	else
		debugLog( 2 , "Warning! - "..prmBgAudioData.sourceName.." is blank/nil. This source will not be used in the show.")
	end
	--
	--	Dump a stats view of the full set of sources in the show
	--
	logShowSourceVisStats()
	--
	--	Connect the show/hide signal handlers
	--
	local sh = obs.obs_get_signal_handler()
	obs.signal_handler_connect(sh, "source_show"  ,source_show)
	obs.signal_handler_connect(sh, "source_hide"  ,source_hide)
	--
	--	We have to do some setup on the MEDIA source. Attach signal handler, get begin states, set not visible.
	--
	if prmSourceNames.prmTargetMediaSource.sceneItemObj ~= nil then
		--	Need these signal handlers to know if media played finishes.
		debugLog( 4 , "Attaching Media Ended/Stopped callbacks to source: "..prmTargetMediaSource )
		local sh = obs.obs_source_get_signal_handler(prmSourceNames.prmTargetMediaSource.sourceObj)
		obs.signal_handler_disconnect(sh, "media_ended"  ,mediaEndedCallback)
		obs.signal_handler_connect   (sh, "media_ended"  ,mediaEndedCallback)
		obs.signal_handler_disconnect(sh, "media_stopped",mediaStoppedCallback)
		obs.signal_handler_connect   (sh, "media_stopped",mediaStoppedCallback)
		--	Get its current settings value so we can restore it at end of show.
		prmSourceNames.prmTargetMediaSource.beginItemValue = getSourceSetting( prmTargetMediaSource , "local_file" , "string" )
		--	Make it NOT visible - ought become deactivated, per our other observations
		--	Starting the show, it ought be not visible.
		obs.obs_sceneitem_set_visible( prmSourceNames.prmTargetMediaSource.sceneItemObj , false )
		--	Change its settings local_file value to nothing.
		changeSourceSetting ( prmTargetMediaSource , "local_file" , "" , "string" )
		--
		prmMediaShowTranTime = 0
		prmMediaHideTranTime = 0
		local tranObj = obs.obs_sceneitem_get_show_transition(prmSourceNames.prmTargetMediaSource.sceneItemObj)
		if tranObj ~= nil then
			prmMediaShowTranTime = obs.obs_sceneitem_get_show_transition_duration(prmSourceNames.prmTargetMediaSource.sceneItemObj)
		end
		local tranObj = obs.obs_sceneitem_get_hide_transition(prmSourceNames.prmTargetMediaSource.sceneItemObj)
		if tranObj ~= nil then
			prmMediaHideTranTime = obs.obs_sceneitem_get_hide_transition_duration(prmSourceNames.prmTargetMediaSource.sceneItemObj)
		end
		debugLog( 3 , "Media SceneItem Transition Times, SHOW: "..prmMediaShowTranTime..", HIDE: "..prmMediaHideTranTime )
		--
	end
	--
	--	We have to do some setup on the IMAGE source. Attach signal handler, get begin states, set not visible.
	--
	if prmSourceNames.prmTargetImageSource.sceneItemObj ~= nil then
		--	Get its current settings value so we can restore it at end of show.
		prmSourceNames.prmTargetImageSource.beginItemValue = getSourceSetting( prmTargetImageSource , "file" , "string" )
		--	Make it NOT visible - ought become deactivated, per our other observations
		--	Starting the show, it ought be not visible.
		obs.obs_sceneitem_set_visible( prmSourceNames.prmTargetImageSource.sceneItemObj , false )
		--	And now change its settings local_file value to nothing.
		changeSourceSetting ( prmTargetImageSource , "file" , "" , "string" )
		--
		prmImageShowTranTime = 0
		prmImageHideTranTime = 0
		local tranObj = obs.obs_sceneitem_get_show_transition(prmSourceNames.prmTargetImageSource.sceneItemObj)
		if tranObj ~= nil then
			prmImageShowTranTime = obs.obs_sceneitem_get_show_transition_duration(prmSourceNames.prmTargetImageSource.sceneItemObj)
		end
		local tranObj = obs.obs_sceneitem_get_hide_transition(prmSourceNames.prmTargetImageSource.sceneItemObj)
		if tranObj ~= nil then
			prmImageHideTranTime = obs.obs_sceneitem_get_hide_transition_duration(prmSourceNames.prmTargetImageSource.sceneItemObj)
		end
		debugLog( 3 , "Image SceneItem Transition Times, SHOW: "..prmImageShowTranTime..", HIDE: "..prmImageHideTranTime  )
		--
	end
	--
	--	We have to do some setup on the TEXT source. get begin states, leave its visibility alone.
	--
	if prmSourceNames.prmTargetTextSource.sceneItemObj ~= nil then
		--	Get its current settings value so we can restore it at end of show.
		prmSourceNames.prmTargetTextSource.beginItemValue = getSourceSetting( prmTargetTextSource , "text" , "string" )
		--	And now change its settings text value to nothing.
		changeSourceSetting ( prmTargetTextSource , "text" , "" , "string" )
		--
		if gbl_SceneRecFlags.QT.flag then									-- Override/force TEXT source to be quiet this show
			if gbl_SceneRecFlags.QT.valu then								-- so then we make it not visible
				obs.obs_sceneitem_set_visible( prmSourceNames.prmTargetTextSource.sceneItemObj , false )
				debugLog( 3 , "saveAndSetStartupStates - Override/Force TEXT Source to be Quiet this show, make invisible." )
			end
		end
	end
	--
	activeStartupWaiting = true
	activeWaitingCount = 0
	--
	debugLog( 4 , "LEAVE: saveAndSetStartupStates" )
	return true
end
--
--	This function is actually called via timer callback to start a show by the source_activated
--	code for the ShowControlGroup.  When this function finishes it MUST do the same to the
--	timer_SetupSceneNeeds2_Callback so things keep moving and finally start.
--
--	Function to do things needed at the start of a Scene.  These include starting recording.
--	If starting recording, we have to check is a BgAudio Source is active or not and if Recording
--	is already active or not.  If recording is already active, we do nothing but initiate via
--	timer callback the timer_SetupSceneNeeds2_Callback.  If recording is not active and this scene
--	calls for recording to start, we have to set the Bg Audio volume to zero and start recording and
--	wait for it to become fully active.  Only then do we move to the Phase 2 function to then fade
--	the BgAudio source (if needed) and wait for it.  After all this, then we move to the RunTheShow
--	code to get the show going.
--
--	FYI - these events are relevant:
--	obs.OBS_FRONTEND_EVENT_RECORDING_STARTING = 4
--	obs.OBS_FRONTEND_EVENT_RECORDING_STARTED  = 5
--	obs.OBS_FRONTEND_EVENT_RECORDING_STOPPING = 6
--	obs.OBS_FRONTEND_EVENT_RECORDING_STOPPED  = 7
--
function timer_SetupSceneNeeds1_Callback()
	debugLog( 4 , "ENTER: timer_SetupSceneNeeds1_Callback" )
	obs.remove_current_callback()
	local maxWaitCount = 80											-- safety max wait count, factored against the 50ms wait cycle = 4.0 seconds total
	local recordingActive = false
	local volumeAtZero = false
	local curVolume = 1
	repeat
		activeWaitingCount = activeWaitingCount + 1
		debugLog( 4 , "recordingStartup - Entered - count: "..activeWaitingCount..", gbl_RecordStarting:"..sfbool(gbl_RecordStarting)..", recActive:"..sfbool(recordingActive) )
		if activeWaitingCount <= maxWaitCount then
			if gbl_SceneRecFlags.begSceneBegRecord then
				if activeWaitingCount == 1 then
					if prmBgAudioData.sourceObj ~= nil then
						volumeAtZero = obs.obs_source_get_volume(prmBgAudioData.sourceObj) == 0
						if not volumeAtZero then
							obs.obs_source_set_volume(prmBgAudioData.sourceObj,0)
							debugLog( 3 , "LEAVE: timer_SetupSceneNeeds1_Callback - BgAudio Volume Set zero, Begin Waiting. WaitCount="..activeWaitingCount )
							obs.timer_add( timer_SetupSceneNeeds1_Callback , 50 )
							return
						end
					else
						-- No Audio source to fade, so go right to start recording
						recordingActive = obs.obs_frontend_recording_active()
						if not recordingActive then
							obs.obs_frontend_recording_start()
							gbl_RecordStarting = true
							debugLog( 3 , "LEAVE: timer_SetupSceneNeeds1_Callback - Recording Starting, Begin Waiting. WaitCount="..activeWaitingCount )
							obs.timer_add( timer_SetupSceneNeeds1_Callback , 50 )
							return
						else
							gbl_RecordWasActive = true
						end
					end
				else
					if prmBgAudioData.sourceObj ~= nil then
						volumeAtZero = obs.obs_source_get_volume(prmBgAudioData.sourceObj) == 0
						if not volumeAtZero then
							debugLog( 4 , "LEAVE: timer_SetupSceneNeeds1_Callback - Continue BgAudio Zero Waiting. WaitCount="..activeWaitingCount )
							obs.timer_add( timer_SetupSceneNeeds1_Callback , 50 )
							return
						else
							obs.os_sleep_ms(300)				-- It says volume is zero but give it a tad more clock time before record start
						end
					end
					-- Getting here means that BgAudio is done zeroing out.
					recordingActive = obs.obs_frontend_recording_active()
					if not gbl_RecordStarting then
						-- Recording not yet started, do it now, pending recordingActive state
						if recordingActive then
							gbl_RecordWasActive = true
							debugLog( 3 , "timer_SetupSceneNeeds1_Callback - Recording Was Active Already, Done Waiting. WaitCount="..activeWaitingCount )
							activeStartupWaiting = false		-- Done Waiting
							gbl_RecordStarted = true			-- Recording is active
						else
							obs.obs_frontend_recording_start()
							gbl_RecordStarting = true
							debugLog( 3 , "LEAVE: timer_SetupSceneNeeds1_Callback - After BgAudio Zeroed, Recording Starting, Waiting. WaitCount="..activeWaitingCount )
							obs.timer_add( timer_SetupSceneNeeds1_Callback , 50 )
							return
						end
					else
						if not recordingActive then
							debugLog( 4 , "LEAVE: timer_SetupSceneNeeds1_Callback - Continue Recording Start Wait. WaitCount="..activeWaitingCount )
							obs.timer_add( timer_SetupSceneNeeds1_Callback , 50 )
							return
						else
							debugLog( 3 , "timer_SetupSceneNeeds1_Callback - Done Waiting Recording Started. WaitCount="..activeWaitingCount )
							activeStartupWaiting = false		-- Done Waiting
							gbl_RecordStarted = true			-- Recording is active
							--	But wait, I see log entries intermingled with the timer_SetupSceneNeeds2_Callback log messages
							--	showing the starting of the recording.  I am seeing several script_ticks of volume fade in ticks
							--	and then I see a Recording Start OBS message.  Here again, I see some lag in things.  So I am
							--	going to sleep here a bit more to help these things sync.
							obs.os_sleep_ms(80)		-- duration perhaps educated guess
						end
					end
				end
			else
				debugLog( 3 , "timer_SetupSceneNeeds1_Callback - Recording Start, BgAudio Zeroing  NOT Needed, Do Nothing, Proceeding..." )
				activeStartupWaiting = false
			end
		else
			debugLog( 1 , "timer_SetupSceneNeeds1_Callback - Give Up, Too Many Retries on Recording+BgAudioZero Start/Wait. WaitCount="..activeWaitingCount )
			activeStartupWaiting = false				-- Not Happy - we had to give up for too many reties - troubleshoot this.
		end
	until not activeStartupWaiting			-- This loop ought not ever iterate more than once, every time
	--
	--	Getting here means that, IF Recording was called for, it is now started amd ready to go.
	--	It also means that if Bg-Audio was defined, it had its volume set to zero.
	--	If no recording startup was requested, then we just fell through to here and we continue to callback the
	--	next function of the similar name to this one but #2 in sequence.  SOmetime I will have to come up with a
	--	better and more generalized way of doing things with a wait requirement.  There must be a better way.
	--
	gbl_RecordStarting = false			-- clean up on this global on the way out
	activeStartupWaiting = true
	activeWaitingCount = 0
	obs.timer_add( timer_SetupSceneNeeds2_Callback , 10 )
	--
	debugLog( 4 , "LEAVE: timer_SetupSceneNeeds1_Callback - Callback set for: timer_SetupSceneNeeds2_Callback" )
end
--
--	See the comments above the sister code just above this function of the similar name.
--
--	This function is supposed to (if needed) initiate a fade up of a defined BgAudio and wait for it to complete.
--	The it can move to the RunTheSHow code to move the process along.
--
--	Getting to this function means that Recording is supposedly already active (if called for) and any BgAudio source
--	was set to zero.
--
function timer_SetupSceneNeeds2_Callback()
	debugLog( 4 , "ENTER: timer_SetupSceneNeeds2_Callback" )
	obs.remove_current_callback()
	local maxWaitCount = 8																	-- an arbitrary max wait count, for safety
	if gbl_SceneRecFlags.begSceneBegRecord and prmBgAudioData.sourceObj ~= nil then			-- not using this unless I MUST wait for Bg-Audio
		if prmBgAudioData.fadeTime ~= 0 then
			-- but if Bg-Audio fade up is needed, then we need to allow enough worst case wait counts to let the fade up reach its target
			maxWaitCount = ( 2 * prmBgAudioData.fadeTime / 50 ) + 20						-- ok, padding for insurance
		end
	end
	repeat
		activeWaitingCount = activeWaitingCount + 1
		debugLog( 3 , "bgAudioWait - Entered - count: "..activeWaitingCount.." ctx.set_audioFade Size: "..#ctx.set_audioFade )
		if activeWaitingCount <= maxWaitCount then
			if gbl_SceneRecFlags.begSceneBegRecord and prmBgAudioData.sourceObj ~= nil then
				if activeWaitingCount == 1 then
					-- set script_tick code to fade from zero up to prmBgAudioData.origVolume or fadedVolume pending first media slide type
					local curVolume = obs.obs_source_get_volume(prmBgAudioData.sourceObj)
					local toVolume = prmBgAudioData.origVolume
					if gbl_FirstSlideType == slideTypeMedia then
						toVolume = prmBgAudioData.fadedVolume										-- first slide is Media, do not fade up to loud Orig level
					end
					table.insert(ctx.set_audioFade, { 	item  = prmBgAudioData.sourceObj     ,		-- the sourceObj needed for the API call to change volume
														name  = prmBgAudioData.sourceName    ,		-- just the name for debug output
														fTime = prmBgAudioData.fadeTime * 2  ,		-- working time for the fade, decrements until done
														wkVol = curVolume                    ,		-- working volume, decrs toward toVol by signed vol steps per script_tick
														toVol = toVolume                     ,		-- destination volume, last script_tick step set vol to this value
														rlSrc = false
													} )
					debugLog( 2 , "LEAVE: timer_SetupSceneNeeds2_Callback - Initiated Fade Up of BgAudio Volume to: "..toVolume..". WaitCount="..activeWaitingCount )
					obs.timer_add( timer_SetupSceneNeeds2_Callback , 50 )
					return
				else
					if #ctx.set_audioFade == 0 then
						debugLog( 2 , "timer_SetupSceneNeeds2_Callback - Done Waiting for Bg-Audio Ready. WaitCount="..activeWaitingCount )
						activeStartupWaiting = false		-- Done Waiting
					else
						debugLog( 2 , "LEAVE: timer_SetupSceneNeeds2_Callback - Continue Waiting on BgAudio Fade Up completion. WaitCount="..activeWaitingCount )
						obs.timer_add( timer_SetupSceneNeeds2_Callback , 50 )
						return
					end
				end
			else
				-- Recording startup is NOT requested
				debugLog( 2 , "timer_SetupSceneNeeds2_Callback - Recording NOT Needed and or Bg Audio is not defined, Do Nothing, Proceeding..." )
				activeStartupWaiting = false
			end
		else
			debugLog( 2 , "timer_SetupSceneNeeds2_Callback - Give Up, Too Many Retries on BgAudi Fade Up Wait. WaitCount="..activeWaitingCount )
			activeStartupWaiting = false				-- Not Happy - we had to give up for too many reties - troubleshoot this.
		end
	until not activeStartupWaiting			-- This loop ought not ever iterate more than once, every time
	--
	--	Getting here means that, IF Recording was called for, and a Bg Audio source was active, then we have set the fade up
	--	and successfully waited for it to complete.  Recording would now supposedly be active and motion can now continue.
	--
	activeStartupWaiting = true
	activeWaitingCount = 0
	obs.timer_add( timer_RunTheShow_Callback , 10 )
	--
	debugLog( 4 , "LEAVE: timer_SetupSceneNeeds2_Callback - Callback set for: timer_RunTheShow_Callback" )
end
--
--	Function to start/run the show
--
function timer_RunTheShow_Callback()
	debugLog( 2 , "ENTER: timer_RunTheShow_Callback" )
	--
	--	Our group that controls all has been activated.
	--	This constitutes the starting of the show.
	--	However - nothing is as easy as one thinks...
	--
	--	The saveAndSetStartupStates code does a bit of visibility fiddling.  This, along with the
	--	natural startup of the group and the items within, generates some activation and deactivation
	--	actions and we have to wait for them to all occur and settle.  Otherwise, the observed
	--	behavior was that an action or two would slip by and occur after this code and confuse the
	--	startup causing things like seemingly skipping slide 1 and working on 2 instead.  This
	--	was actually caused by a stray deactivation unaccounted for.  Therefore, on entry to this code,
	--	we always wait an extra waiting cycle (callback to self) so we can be sure that these
	--	deactivations and activations can all become complete.  Only then can we proceed.  I found
	--	that these things ocurred within the first extra wait loop.
	--
	--	Again, All this next chunk of code is doing is 1) trying to ensure that both the IMAGE and MEDIA sources
	--	are inactive so the show has a clean start.  2) Because, when the group activates, all its children
	--	likewise do same and we undo this in the initial set/save function by setting IMAGE and MEDIA vis
	--	to false so we can load the 1st item and then activate it to prime the pump and get the cycle going.
	--	But, again, all these things happen in a flurry and our main code gets ahead of them, hence, we force
	--	a bit of waiting to give them time to complete their state changes.
	--
	obs.remove_current_callback()
	if activeStartupWaiting then
		activeWaitingCount = activeWaitingCount + 1
		debugLog( 3 , "activeStartupWaiting - Entered - count: "..activeWaitingCount )
		logShowSourceVisStats()
		local numSourcesInactive = 0
		local madeVisChanges = false
		repeat
			if obs.obs_source_active(prmSourceNames.prmTargetImageSource.sourceObj) then
				local wasVisible = obs.obs_sceneitem_visible( prmSourceNames.prmTargetImageSource.sceneItemObj )
				debugLog( 3 , "activeStartupWaiting - Image Vis was: "..sfbool(wasVisible).." Toggling now" )
				obs.obs_sceneitem_set_visible( prmSourceNames.prmTargetImageSource.sceneItemObj , not wasVisible )
				madeVisChanges = true
			else
				debugLog( 3 , "activeStartupWaiting - IMAGE is Inactive bump num count" )
				numSourcesInactive = numSourcesInactive + 1
			end
			if obs.obs_source_active(prmSourceNames.prmTargetMediaSource.sourceObj) then
				local wasVisible = obs.obs_sceneitem_visible( prmSourceNames.prmTargetMediaSource.sceneItemObj )
				debugLog( 3 , "activeStartupWaiting - MEDIA Vis was: "..sfbool(wasVisible).." Toggling now" )
				obs.obs_sceneitem_set_visible( prmSourceNames.prmTargetMediaSource.sceneItemObj , not wasVisible )
				madeVisChanges = true
			else
				debugLog( 3 , "activeStartupWaiting - MEDIA is Inactive bump num count" )
				numSourcesInactive = numSourcesInactive + 1
			end
			debugLog( 3 , "activeStartupWaiting - B4 until Test, numSourcesInactive: "..numSourcesInactive )
		until numSourcesInactive == 2 or activeWaitingCount > 8 or madeVisChanges
		if activeWaitingCount <= 16 then
			if madeVisChanges then
				--	Attempt to use change of Vis to get these things to go back to inactive.
				--	Set a timer to give them a chance to cycle such that they may yet deactivate.
				--	This seems to happen if the show was terminated, probably via clicking on the group icon,
				--	killing things and leaving things in unknown states.
				--	Trying to start the show again like this seems a ongoing problem...
				obs.timer_add( timer_RunTheShow_Callback , 1000 )
				debugLog( 2 , "LEAVE: timer_RunTheShow_Callback - Had Active Source(s), vis changed attempting to get to Inactive. WaitCount="..activeWaitingCount )
				return
			else
				if activeWaitingCount <= 1 then
					-- This one more cycle of waiting ought to take care of startup flurry things.
					-- Need to ensure the activations and then initial deactivations all settle to get a clean show startup.
					obs.timer_add( timer_RunTheShow_Callback , 500 )
					debugLog( 2 , "LEAVE: timer_RunTheShow_Callback - Waiting a tad longer for initial burst of source activity to settle - WaitCount="..activeWaitingCount )
					return
				else
					if numSourcesInactive < 2 then
						-- This is a Just in case, but not observed...
						obs.timer_add( timer_RunTheShow_Callback , 200 )
						debugLog( 2 , "LEAVE: timer_RunTheShow_Callback - Not all sources ready yet. Do Timer again, hope things change in another wait cycle..." )
						return
					else
						debugLog( 3 , "activeStartupWaiting - COMPLETED - SUCCESS - HORRAY!!!" )
						activeStartupWaiting = false
					end
				end
			end
		else
			debugLog( 3 , "activeStartupWaiting - WARNING - Exceeded Wait Limit on initial Source Inactive status checks... WTF" )
			activeStartupWaiting = false
		end
	end
	--
	--	It is noteworthy, for the unsure reader. Because the group was activated, and we finally got here,
	--	we setup the sources as needed (here) for the 1st item and we set visibility to true, causing an
	--	activate of the items IMAGE/MEDIA source.  That, gets the show cycling.
	--
	gbl_LoopCount        = 0		-- this gets incremented each time media list is loaded
	gbl_TickSeconds      = 0
	--
	--	Load the next (first) media item
	--
	activeMediaItem,activeSlideType,activeSlideTypeString = setupNextItemIntoSources()
	debugLog( 1 , "Next Item Info: #"..activeMediaIndex.." of "..#activeMediaList..", Item:"..activeMediaItem..": , slideType:"..activeSlideType..":"..activeSlideTypeString )
	--
	local showAction = "ActionYetUndefined"
	if activeMediaItem == "**STOP**" then
		--
		--	Nothing left to show - setup end of show
		--	This ought not happen on the very first slide.  But it could if no media items were found for the available
		--	sources (image and or Media) and the list was spun through finding nothing eligible to show.
		--
		debugLog( 3 , "Next Item says STOP -- setting "..prmShowControlGroup.." Vis:false triggering shutdown." )
		setSceneItemVisibility( prmShowControlGroup , false )
		showAction = "No Items to show."
		--
		--	Perhaps ought not assert error - perhaps this is not an error. Consider if the user had both video and pictures not initially visible
		--	in the group or the list of items were all one or the other such that nothing was selected due to initial vis or list contents.
		--	In certain cases, the list quietly and properly returns nothing leaving the show potentially showing nothing and seeming useless.
		--	but such a behavior ought be correct.  Arguably letting them know via error log window showing, could be useful...
		--	maybe justified to do this as this kind of startup is unusual.
		--	After testing, I think the assert is not nice here.  popup logging window is irritating.
		--
		--assert(false,showAction)	-- Alert an error back thru OBS - script log window ought to appear and show error.
	else
		--	Assuming we got an item to show
		if activeSlideType == slideTypeImage then
			--obs.obs_sceneitem_set_visible( prmSourceNames.prmTargetImageSource.sceneItemObj , true )
			table.insert(ctx.set_visible, { item = prmSourceNames.prmTargetImageSource.sceneItemObj , delay = cbVisDelay , visible = true  , name = prmSourceNames.prmTargetImageSource.value })
			showAction = "Starting with Slide: "..activeMediaIndex.." of "..#activeMediaList.." of "..activeSlideTypeString.." Item: "..activeMediaItem
		end
		if activeSlideType == slideTypeMedia then
			--obs.obs_sceneitem_set_visible( prmSourceNames.prmTargetMediaSource.sceneItemObj , true )
			table.insert(ctx.set_visible, { item = prmSourceNames.prmTargetMediaSource.sceneItemObj , delay = cbVisDelay , visible = true  , name = prmSourceNames.prmTargetMediaSource.value })
			showAction = "Starting with Slide: "..activeMediaIndex.." of "..#activeMediaList.." of "..activeSlideTypeString.." Item: "..activeMediaItem
		end
		gbl_activatedState = true				-- we are considered started now
		gbl_SceneEntryAutoStarting = false		-- done starting, now active
		showBegTime = os.time() 				-- The show begins when? - Now, of course
	end
	--
	debugLog( 2 , "LEAVE: timer_RunTheShow_Callback - Show, "..showAction )
end
--
-- This thing is called for ANY/ALL sources activated
-- gotta screen them for ones that only apply herein.
--
function source_activated(callData)
	local source = obs.calldata_source(callData,"source")
	local requestingSourceName = obs.obs_source_get_name( source )
	local stat = "Active:"..sfbool(obs.obs_source_active(source))..", Showing:"..sfbool(obs.obs_source_showing(source))..", Hidden:"..sfbool(obs.obs_source_is_hidden(source))
	local lmsg = ""
	debugLog( 3 , "ENTER: source_activated - "..requestingSourceName..", "..stat )
	--
	--	Critical event in grand scheme of things - walk carefully
	--	This is when the top level Group Source becomes activated.
	--
	if not prmShowsDisabled and requestingSourceName == prmShowControlGroup then
		if saveAndSetStartupStates() then
			obs.timer_add( timer_SetupSceneNeeds1_Callback , 10 )
			lmsg = "timer_SetupSceneNeeds1_Callback Queued."
		else
			gbl_SceneEntryAutoStarting = false							-- If startup fails, dont leave this hanging true
			setSceneItemVisibility( prmShowControlGroup , false )		-- set main group vis to false to ensure event to cause full SS shutdown
			lmsg = "saveAndSetStartupStates Failed - The Show Will Not Go On!"
		end
		debugLog( 3 , "LEAVE: source_activated - "..lmsg )
		return
	end
	--
	--	Handle activations for the worker sources
	--
	if not prmShowsDisabled and requestingSourceName == prmTargetImageSource or requestingSourceName == prmTargetMediaSource then
		--
		--	Our Image/Media Source has been activated.
		--	This happens normally when the source is set vis true and this activated code is a side effect event.
		--	When a source is set vis=true, it starts a transition to fully visible and activate happens
		--	simultaneously.  Generally, we presume the source had been setup/configured prior to vis=true.
		--	The setup of the source occurs elsewhere (deactivated ie: at end of prior slide).  Therefore,
		--	we largely just want to set a timer callback for the image+transition duration which will delay
		--	suitably till timer expires and then the image is moved to its end of life for the next one.
		--
		if gbl_activatedState then
			if ( activeSlideType == slideTypeMedia and requestingSourceName == prmTargetMediaSource )
			or ( activeSlideType == slideTypeImage and requestingSourceName == prmTargetImageSource ) then
				local didAnActivation = false
				if activeSlideType == slideTypeImage then
					debugLog( 3 , "Timer for "..requestingSourceName.." Image Duration Set to: "..prmPicDelayPeriod.."-"..prmImageHideTranTime.."="..prmPicDelayPeriod-prmImageHideTranTime)
					if prmBgAudioData.sourceObj ~= nil and activeLastSlideType ~= slideTypeImage then
						local curVolume = obs.obs_source_get_volume(prmBgAudioData.sourceObj)
						debugLog( 3 , "Orig Vol: "..prmBgAudioData.origVolume..", curVolume: "..curVolume.." --> fadedVolume: "..prmBgAudioData.fadedVolume..", time: "..prmBgAudioData.fadeTime )
						table.insert(ctx.set_audioFade, { 	item  = prmBgAudioData.sourceObj  ,		-- the sourceObj needed for the API call to change volume
															name  = prmBgAudioData.sourceName ,		-- just the name for debug output
															fTime = prmBgAudioData.fadeTime   ,		-- working time for the fade, decrements until done
															wkVol = curVolume                 ,		-- working volume, decrements toward fadedVolume by computed (signed) vol steps per script_tick
															toVol = prmBgAudioData.origVolume ,		-- destination volume, last script_tick step set vol to this value
															rlSrc = false
														} )
					end
					countTargetTextSource  = countTargetTextSource  + 1
					countTargetImageSource = countTargetImageSource + 1
					didAnActivation = true
					obs.timer_remove(timer_ImageCallback)
					obs.timer_add(timer_ImageCallback, prmPicDelayPeriod - prmImageHideTranTime)
					activeSlideRunning = true
				end
				if activeSlideType == slideTypeMedia then
					debugLog( 3 , "Media Source "..requestingSourceName.." Starting." )
					if prmBgAudioData.sourceObj ~= nil and activeLastSlideType ~= slideTypeMedia then
						local curVolume = obs.obs_source_get_volume(prmBgAudioData.sourceObj)
						debugLog( 3 , "Item Media, CurVolume:"..curVolume..", fadedVolume:"..prmBgAudioData.fadedVolume )
						debugLog( 3 , "Orig Vol: "..prmBgAudioData.origVolume..", curVolume: "..curVolume.." --> fadedVolume: "..prmBgAudioData.fadedVolume..", time: "..prmBgAudioData.fadeTime )
						table.insert(ctx.set_audioFade, { 	item  = prmBgAudioData.sourceObj  ,		-- the sourceObj needed for the API call to change volume
															name  = prmBgAudioData.sourceName ,		-- just the name for debug output
															fTime = prmBgAudioData.fadeTime   ,		-- working time for the fade, decrements until done
															wkVol = curVolume                 ,		-- working volume, decrements toward fadedVolume by computed (signed) vol steps per script_tick
															toVol = prmBgAudioData.fadedVolume,		-- fadedVolume - destination volume, last script_tick step set vol to this value
															rlSrc = false
														} )
					end
					countTargetTextSource  = countTargetTextSource  + 1
					countTargetMediaSource = countTargetMediaSource + 1
					didAnActivation = true
					activeSlideRunning = true
				end
				if didAnActivation then
					lmsg = activeSlideTypeString..", Activation Processed."
				else
					lmsg = "(Ignored) ActiveSlideType is "..activeSlideTypeString..", Not applicable activation."
				end
			else
				--	Best to ignore this instance, it happens all the time with videos in testing and is normal as it is deactivated when made invis at start of show
				--	Inversely, this can also happen with Images.
				lmsg = requestingSourceName.." Changed Visibility... User Clicked or other. Probably no big deal."
			end
		else
			lmsg = "(Ignored) Slide Show Inactive."
		end
		debugLog( 3 , "LEAVE: source_activated - "..lmsg )
		return
	end
	if not gbl_SceneEntryAutoStarting and not prmShowsDisabled and prmSceneAutoStart and not gbl_activatedState then
		-- Check the activated item to see if this is a scene and if it is in our list and
		-- this scene is suitably configured to be able to run a show.  If so, then activate the
		-- group and see if it all starts as desired...  This savs a lot of extra wasted lookup work on
		-- the show scenes list, for scene matches.
		gbl_SceneEntryAutoStarting = false		-- When true, it helps stop wasted entries into this code path when things are starting
		local thisSourcesScene = obs.obs_scene_from_source(source)
		if thisSourcesScene ~= nil then
			-- Now we know that this activated source is a SCENE.
			local sceneSourceObj = obs.obs_frontend_get_current_scene()						-- getObj sceneSourceObj
			if sceneSourceObj ~= nil then
				local curSceneName = obs.obs_source_get_name(sceneSourceObj)
				obs.obs_source_release(sceneSourceObj)										-- release sceneSourceObj
				local aScene,aCommand,nxtScene,recCtl = getMediaCmdDataBySceneName( curSceneName )	-- NB: could get back default for aScene
				if aScene == requestingSourceName and aScene == curSceneName and aScene ~= "" and aScene ~= "default" then
					--
					--	This constitutes a Scene Entered Auto Start instance.  It could be from a prior SMSS show setting or
					--	it could be from the user merely Clicking on the Scene and entering it.  Nonetheless, the recCtl array
					--	from the scene lookup needs to carry forward globally so things related to it can all be handled...
					--
					gbl_SceneEntryAutoStarting = true
					gbl_ShowSceneName = aScene
					gbl_ShowMediaCommand = aCommand
					gbl_ShowNextScene = nxtScene
					if gbl_ShowNextScene == "!" then gbl_ShowNextScene = "" end
					gbl_SceneRecFlags = recCtl
					setSceneItemVisibility( prmShowControlGroup , true )					-- Activate/start the Show Control group
					lmsg = requestingSourceName.." Activating Vis:True on ShowControlGroup, is scene Matching Scenes List Entry (non-default)."
				else
					lmsg = requestingSourceName.." is NOT the curScene:"..curSceneName..": and aScene was:"..aScene..":"
				end
			else
				lmsg = "OBS Starting?, got activated source but no Current Scene Available."
			end
		else
			lmsg = "(Ignored) This Activated Source: "..requestingSourceName.." is NOT a SCENE."
		end
	else
		lmsg = "(Ignored) This Activated Source: "..requestingSourceName.." Scene Entry Code is Not Open."
	end
	debugLog( 3 , "LEAVE: source_activated - "..lmsg )
end
--
-- This thing is called for ANY/ALL sources deactivated
-- gotta screen them for ones that only apply herein.
--
function source_deactivated(callData)
	local source = obs.calldata_source(callData,"source")
	local requestingSourceName = obs.obs_source_get_name( source )
	local lmsg = ""
	local stat = "Active:"..sfbool(obs.obs_source_active(source))..", Showing:"..sfbool(obs.obs_source_showing(source))..", Hidden:"..sfbool(obs.obs_source_is_hidden(source))
	debugLog( 3 , "ENTER: source_deactivated - "..requestingSourceName..", "..stat )
	--
	if gbl_activatedState and requestingSourceName == prmShowControlGroup then
		obs.timer_add(timer_ShutdownCallback, 60)
		debugLog( 3 , "LEAVE: source_deactivated - Show Shutdown Initiated." )
		return
	end
	--
	if requestingSourceName == prmTargetImageSource or requestingSourceName == prmTargetMediaSource then
		--
		--	Our Image/Media Source has been deactivated.
		--	This happens when the last image was finished.  At that time, the vis was set false, it transitioned
		--	to not visible which then caused the source_deactivate function (this function) to be entered.
		--	Thus we end up here.  We then need to get the next slide item and load it into the source getting all
		--	prepared for the next showing.  When that prep work is done, we set the vis=true and let the events
		--	transpire for another cycle.  Yes, we do have to check for end of media items etc.
		--
		if gbl_activatedState then
			if ( activeSlideType == slideTypeMedia and requestingSourceName == prmTargetMediaSource )
			or ( activeSlideType == slideTypeImage and requestingSourceName == prmTargetImageSource ) then
				--
				activeSlideRunning = false
				--
				--	This source deactivation matches the current slide type and the sourcename matches the
				--	slide type so it makes sense to process this deactivation as a ligit part of the show.
				--	otherwise, it is a non-sensical deactivation that ought be ignored.  eg: while pictures
				--	were being shown (with no media at all in list), I deactivated the video in the group
				--	and expected a clean no op but instead it clobbered the show jumping to the next item.
				--	This test is expected to make that deactivation quietly ignored.  If videos were in the
				--	list, they ought not be processed anymore.  Hmmm - we will see...
				--
				activeMediaItem,activeSlideType,activeSlideTypeString = setupNextItemIntoSources()
				debugLog( 1 , "Next Item Info: #"..activeMediaIndex.." of "..#activeMediaList..", Item:"..activeMediaItem..": , slideType:"..activeSlideType..":"..activeSlideTypeString )
				if activeMediaItem == "**STOP**" then
					--	Nothing left to show - setup end of show
					debugLog( 2 , "Next Item says STOP -- setting "..prmShowControlGroup.." Vis:false triggering shutdown." )
					debugLog( 2 , "ShowInterrupt: "..sfbool(gbl_ShowInterrupt)..", ShowInterruptViaHotkey: "..sfbool(gbl_ShowInterruptViaHotkey) )
					if gbl_ShowInterrupt and not gbl_ShowInterruptViaHotkey then
						-- A non hotkey or normal interrupt is probably the group icon clicked off - which already
						-- deactivated the group and members, which is why we are here.  Hence, make the shutdown code execute via a quick timer cb.
						-- NB we could be here also due to a scene change by the user pulling rug out from under us, similar to clicking off the group icon.
						obs.timer_add(timer_ShutdownCallback, 50)
						lmsg = "timer_ShutdownCallback Queued, Abrupt Non-Hotkey Show Interrupt."
					else
						-- This is for normal (or hotkey emulated) shutdown - end of show via end of media list
						setSceneItemVisibility( prmShowControlGroup , false )	-- set main group vis to false to ensure event to cause full SS shutdown
						lmsg = "Set ShowControlGropup Vis False, NextMedia Returned **STOP**, Hotkey Interrupt:"..sfbool(gbl_ShowInterruptViaHotkey)
					end
				else
					--	Assuming we got another item to show
					debugLog( 4 , "Continuing to next item: "..activeMediaIndex.." of "..activeSlideTypeString.." item: "..activeMediaItem )
					if activeSlideType == slideTypeImage then
						table.insert(ctx.set_visible, { item = prmSourceNames.prmTargetImageSource.sceneItemObj , delay = cbVisDelay , visible = true , name = prmSourceNames.prmTargetImageSource.value })
						lmsg = "Set Image Vis True, Next Item "..activeMediaIndex..", Item: "..activeMediaItem
					end
					if activeSlideType == slideTypeMedia then
						table.insert(ctx.set_visible, { item = prmSourceNames.prmTargetMediaSource.sceneItemObj , delay = cbVisDelay , visible = true , name = prmSourceNames.prmTargetMediaSource.value })
						lmsg = "Set Media Vis True, Next Item "..activeMediaIndex..", Item: "..activeMediaItem
					end
				end
			else
				lmsg = "(Ignored) "..requestingSourceName.." Changed Vis, User Clicked or Probably a Startup effect."
			end
		else
			lmsg = "(Ignored) - Show Inactive."
		end
	else
		lmsg = "(Ignored) Deactivation."
	end
	debugLog( 3 , "LEAVE: source_deactivated - "..lmsg )
end
--
-- end of script
--