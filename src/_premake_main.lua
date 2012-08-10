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
		if( (errobj ~= nil) and _HandlingError == 0 ) then
		 	_HandlingError = 1
		    local errStr = tostring(errobj) or "("..type(errobj)..")"
		    if( type(errobj)=='table' ) then
		      errStr = "Table: {" ..
		      	table.concat(map(errobj, function (k,v) return '[' .. tostring(k) .. '] = ' .. tostring(v); end)
		      	, ',') .. "}"
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
			local ok, err = xpcall(function() connection(debuggerIP,10000, nil, 0); end, function(errobj) end)
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
		
		-- Expose flags as root level objects, so you can write "flags { Symbols }"
		local field = premake.fields["flags"]
		for _,v in pairs(field.allowed) do
			_G[v] = v
		end
		
		-- Set up global container
		premake.createGlobalContainer()
		
		-- Search for a system-level premake4-system.lua file
		local systemScript = os.getenv("PREMAKE_PATH") or ''
		local systemScriptFullpath = systemScript .. '/' .. "premake-" .. _PREMAKE_VERSION .. '-system.lua'
		if( os.isfile(systemScriptFullpath) ) then
			dofile(systemScriptFullpath)
		end 
		
		-- Set up the environment for the chosen action early, so side-effects
		-- can be picked up by the scripts.

		premake.action.set(_ACTION)

		
		-- Seed the random number generator so actions don't have to do it themselves
		
		math.randomseed(os.time())
		
		
		-- If there is a project script available, run it to get the
		-- project information, available options and actions, etc.
		
		local fname = _OPTIONS["file"] or scriptfile
		if (os.isfile(fname)) then
			dofile(fname)
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
		
		if (not _ACTION) then
			print(shorthelp)
			return 1
		end

		
		-- If there wasn't a project script I've got to bail now
		
		if (not os.isfile(fname)) then
			error("No Premake script ("..scriptfile..") found!", 2)
		end

		
		-- Validate the command-line arguments. This has to happen after the
		-- script has run to allow for project-specific options
		
		action = premake.action.current()
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
		print("Building configurations...")
		if not action.isnextgen then
			premake.bake.buildconfigs()		
			ok, err = premake.checkprojects()
			if (not ok) then error("Error: " .. err, 0) end
		else
			premake.solution.bakeall()
		end
			
		
		-- Hand over control to the action
		printf("Running action '%s'...", action.trigger)
		premake.action.call(action.trigger)

		print("Done.")
		return 0

	end
	
	function defaultaction(osName, actionName)
	   if (actionName == nil) then
	     _ACTION = _ACTION or osName
	   end	   
	   if os.is(osName) then
	      _ACTION = _ACTION or actionName
	   end
	end