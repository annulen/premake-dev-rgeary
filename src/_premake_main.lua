--
-- _premake_main.lua
-- Script-side entry point for the main program logic.
-- Copyright (c) 2002-2011 Jason Perkins and the Premake project
--


	local scriptfile    = "premake4.lua"
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
		if( errobj and _HandlingError == 0 ) then
		 	_HandlingError = 1
		    local errStr = tostring(errobj) or "("..type(errobj)..")"
		    if( type(errobj)=='table' ) then
		      errStr = ("Table: {" ..
		      	table.concat(map(errobj, function (k,v) return '[' .. tostring(k) .. '] = ' .. tostring(v); end)
		      	, ',') .. "}"):sub(1,1500)
		    end
			print("Error: \"" .. errStr .. "\"")
	    	--for k ,v in pairs(_G) do print("GLOBAL:" , k,v) end
	    	if( type(errobj)=='thread' ) then
	    		print(debug.traceback(errobj))
	    	else
	    		print(debug.traceback('',2))
	    	end
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
		
		
		-- If there is a project script available, run it to get the
		-- project information, available options and actions, etc.
		
		local fname = _OPTIONS["file"]
		if not fname then
			local premakeFiles = os.matchfiles('premake*.lua')
			if #premakeFiles == 1 then
				fname = premakeFiles[1]
			end
		end
		
		if (os.isfile(fname)) then
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

		
		-- If there wasn't a project script I've got to bail now
		
		if (not os.isfile(fname)) then
			error("No Premake script ("..scriptfile..") found!", 2)
		end

		
		-- Validate the command-line arguments. This has to happen after the
		-- script has run to allow for project-specific options
		
		local action = premake.action.current()
		if not action and premake.defaultaction then
			-- retry with default action
			_ACTION = premake.defaultaction
			action = premake.action.current()
		end
		if (not action) then
			error("Error: no such action '" .. _ACTION .. "'", 0)
		end

		ok, err = premake.option.validate(_OPTIONS)
		if (not ok) then error("Error: " .. err, 0) end
		

		-- Sanity check the current project setup

		ok, err = premake.checktools()
		if (not ok) then error("Error: " .. err, 0) end
		
		
		-- If a platform was specified on the command line, inject it now

		ok, err = injectplatform(_OPTIONS["platform"])
		if (not ok) then error("Error: " .. err, 0) end

		
		-- Quick hack: disable the old configuration baking logic for the new
		-- next-gen actions; this code will go away when everything has been
		-- ported to the new API
		if not action.ishelp then
			timer.start('Bake configurations')
			if not action.isnextgen then
				print("Building configurations...")
				premake.bake.buildconfigs()		
				ok, err = premake.checkprojects()
				if (not ok) then error("Error: " .. err, 0) end
			else
				premake5.globalContainer.bakeall()
			end
			timer.stop()
		end
			
		
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