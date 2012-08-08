--
-- _codeblocks.lua
-- Define the Code::Blocks action(s).
-- Copyright (c) 2002-2011 Jason Perkins and the Premake project
--

	premake.codeblocks = { }
	local clean = premake.actions.clean

	newaction {
		trigger         = "codeblocks",
		shortname       = "Code::Blocks",
		description     = "Generate Code::Blocks project files",
		
		valid_kinds     = { "ConsoleApp", "WindowedApp", "StaticLib", "SharedLib" },
		
		valid_languages = { "C", "C++" },
		
		valid_tools     = {
			cc   = { "gcc", "ow" },
		},
		
		onsolution = function(sln)
			premake.generate(sln, "%%.workspace", premake.codeblocks.workspace)
		end,
		
		onproject = function(prj)
			premake.generate(prj, "%%.cbp", premake.codeblocks.cbp)
		end,
		
		oncleansolution = function(sln)
			clean.file(sln, "%%.workspace")
		end,
		
		oncleanproject = function(prj)
			clean.file(prj, "%%.cbp")
			clean.file(prj, "%%.depend")
			clean.file(prj, "%%.layout")
		end
	}
