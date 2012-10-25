--
-- _premake_main.lua
-- Script-side entry point for the main program logic.
-- Copyright (c) 2002-2011 Jason Perkins and the Premake project
--


	local scriptfile    = "premake*.lua"
	local shorthelp     = "Type 'premake4 --help' for help"
	local versionhelp   = "premake4 (Premake Build Script Generator) %s"
	
	_WORKING_DIR        = os.getcwd()


--
-- Inject a new target platform into each solution; called if the --platform
-- argument was specified on the command line.
--

	local function injectplatform(platform)
		if not platform then return true end
		platform = premake.api.checkvalue(platform, premake.fields.platforms.allowed)
		
		for sln in premake.solution.each() do
			local platforms = sln.platforms or { }
			
			-- an empty table is equivalent to a native build
			if #platforms == 0 then
				table.insert(platforms, "Native")
			end
			
			-- the solution must provide a native build in order to support this feature
			if not table.contains(platforms, "Native") then
				return false, sln.name .. " does not target native platform\nNative platform settings are required for the --platform feature."
			end
			
			-- add it to the end of the list, if it isn't in there already
			if not table.contains(platforms, platform) then
				table.insert(platforms, platform)
			end
			
			sln.platforms = platforms
		end
		
		return true
	end
	
	local _HandlingError = 0
	function _ErrorHandler ( errobj )
		if _HandlingError == 0 then
			local stack
	    	if( type(errobj)=='thread' ) then
	    		stack = debug.traceback(errobj)
	    	else
	    		stack = debug.traceback('',2)
	    	end
	    	
	    	if stack:find("/debugger.lua",1,true) then
	    		return false
	    	end
		 	_HandlingError = 1

		    local errStr = tostring(errobj) or "("..type(errobj)..")"
		    if( type(errobj)=='table' ) then
		    	local errMsg = {}
				for k,v in pairs(errobj) do
					table.insert(errMsg, '[' .. tostring(k) .. '] = ' .. tostring(v))
				end
		      errStr = ("Table: {"..
		      	table.concat(errMsg, ',') 
		      	.. "}"):sub(1,1500)
		    end
			print("Error: \"" .. errStr .. "\"")
			print(stack)
	    	--for k ,v in pairs(_G) do print("GLOBAL:" , k,v) end
	    	print('')
	    	_HandlingError = 0
	    end
    	return false
	end
	
--
-- Script-side program entry point.
--

	function _premake_main(scriptpath)

		-- Attach Debugger
		local ok,err
		if(_OPTIONS["attach"] ) then
			local debuggerIP = _OPTIONS["attach"]
			if(debuggerIP=='') then debuggerIP = '127.0.0.1'; end
			print("Waiting to connect to debugger on " .. tostring(debuggerIP) .. ':10000')
			local connection = require("debugger")
			connection(debuggerIP,10000, nil, 100)
			print('Connected to debugger')
		elseif(_OPTIONS["attachNoWait"] ) then
			local debuggerIP = _OPTIONS["attachNoWait"]
			if(debuggerIP=='') then debuggerIP = '127.0.0.1'; end
			--print("Listening for debugger on " .. tostring(debuggerIP) .. ':10000')
			local connection = require("debugger")
			ok, err = xpcall(function() connection(debuggerIP,10000, nil, 0); end, function(errobj) end)
			if ok then
				print('Connected to debugger')
			end
		end

		-- if running off the disk (in debug mode), load everything 
		-- listed in _manifest.lua; the list divisions make sure
		-- everything gets initialized in the proper order.
		
		if (scriptpath) then
			local scripts  = dofile(scriptpath .. "/_manifest.lua")
			for _,v in ipairs(scripts) do
				dofile(scriptpath .. "/" .. v)
			end
		end

		path.setRepoRoot(_OPTIONS['reporoot'] or _WORKING_DIR)

		-- Start profiling
		if (_OPTIONS['profile']) then
			timer.enable()
		end
				
		-- Make it easier to test for build args
		for _,v in ipairs(_ARGS) do
			_ARGS[v] = v
		end
		
		-- Expose flags as root level objects, so you can write "flags { Symbols }"
		local field = premake.fields["flags"]
		local insertList = {}
		for k,v in pairs(field.allowedList) do
			if type(k) == 'number' then
				table.insert( insertList, v )
			else
				table.insert( insertList, k )
				for _,v2 in ipairs(v) do
					table.insert( insertList, v2 )
				end
			end
		end
		for _,v in pairs(field.aliases) do
			table.insert( insertList, v )
		end
		for _,v in ipairs(insertList) do
			if _G[v] and _G[v] ~= v then
				print('Warning : '..v..' is already set to '.._G[v]..', can\'t reassign _G["'..v..'"]=\"'..v..'"')
			else
				_G[v] = v
			end 
		end
		
		-- Set up global container
		global()
		
		-- Enable quiet mode. In quiet mode, Print with printAlways 
		if _OPTIONS['quiet'] then
			print = function() end
		end
		
		-- Search for a system-level premake4-system.lua file
		local systemScript
		if os.getenv('PREMAKE_PATH') then
			systemScript = os.getenv("PREMAKE_PATH").."/premake-system.lua"
		else
			systemScript = _OPTIONS['systemScript']
			if systemScript and os.isdir(systemScript) then
				systemScript = systemScript..'/premake-system.lua'
			end
		end
		if systemScript and os.isfile(systemScript) then
			timer.start('Load system script')
			dofile(systemScript, true)
			timer.stop()
		end 
		
		-- Set up the environment for the chosen action early, so side-effects
		-- can be picked up by the scripts.

		premake.action.set(_ACTION or '')

		
		-- Seed the random number generator so actions don't have to do it themselves
		
		math.randomseed(os.time())
		
		local action = premake.action.current()
		local ishelp = (action or {}).ishelp
		local requirePremakeFile = (not ishelp) and (not _OPTIONS.interactive) 
		
		-- If there is a project script available, run it to get the
		-- project information, available options and actions, etc.
		
		local fname = _OPTIONS["file"]
		local premakeFiles = {}
		if not fname then
			premakeFiles = os.matchfiles(scriptfile)
			if #premakeFiles == 1 then
				fname = premakeFiles[1]
			elseif table.contains(premakeFiles, 'premake4.lua') then
				-- legacy support
				fname = 'premake4.lua' 
			end
		end
		
		if (os.isfile(fname) and requirePremakeFile) then
			timer.start('Load build script')
			dofile(fname, true)
			timer.stop()
		end

		-- Process special options
		
		if (_OPTIONS["version"]) then
			printf(versionhelp, _PREMAKE_VERSION)
			return 1
		end
		
		if (_OPTIONS["help"]) then
			premake.showhelp()
			return 1
		end
		
			
		-- If no action was specified, show a short help message
		
		if (not _ACTION) or (_ACTION == '') then
			print(shorthelp)
			return 1
		end

		-- Refetch action as file script may have altered it		
		action = premake.action.current()
		ishelp = (action or {}).ishelp
		
		if not action and premake.defaultaction then
			-- retry with default action
			_ACTION = premake.defaultaction
			action = premake.action.current()
		end


		-- Validate the command-line arguments. This has to happen after the
		-- script has run to allow for project-specific options
		ok, err = premake.option.validate()
		if (not ok) then error("Error: " .. err, 0) end
		

		-- Run interactive mode
		if _OPTIONS.interactive then
			print("Premake interactive shell. Press Ctrl-C to exit.")
			debug.dotty()
			return 0
		end
		
		-- If there wasn't a project script I've got to bail now
		if (not os.isfile(fname) and not ishelp) then
			if #premakeFiles == 0 then
				error("No Premake script ("..scriptfile..") found!", 2)
			else
				error("Multiple Premake scripts found : "..table.concat(premakeFiles, ' '), 2)
			end
		end
		
		if (not action) then
			error("Error: no such action '" .. _ACTION .. "'", 0)
		end

		
		-- Sanity check the current project setup

		ok, err = premake.checktools()
		if (not ok) then error("Error: " .. err, 0) end
		
		
		-- If a platform was specified on the command line, inject it now

		ok, err = injectplatform(_OPTIONS["platform"])
		if (not ok) then error("Error: " .. err, 0) end

		premake.spellCheckEnable(_G, "_G")
		
		-- Quick hack: disable the old configuration baking logic for the new
		-- next-gen actions; this code will go away when everything has been
		-- ported to the new API
		if not ishelp then
			timer.start('Bake configurations')
			if not action.isnextgen then
				error("Action \""..action.trigger.."\" not implemented")
			else
				premake5.globalContainer.bakeall()
			end
			timer.stop()
		end
			
		premake.spellCheckDisable(_G)

		-- Hand over control to the action
		printDebug("Running action '%s'...", action.trigger)
		timer.start('Run action ' .. action.trigger)
		premake.action.call(action.trigger)
		timer.stop()

		timer.print()
		
		if not action.ishelp then
			print("Done.")
		end
		return 0

	end
	
	function defaultaction(actionName)
		_ACTION = _ACTION or actionName
		premake.defaultaction = actionName
	end