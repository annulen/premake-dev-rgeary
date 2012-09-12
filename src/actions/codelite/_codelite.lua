--
-- _codelite.lua
-- Define the CodeLite action(s).
-- Copyright (c) 2008-2009 Jason Perkins and the Premake project
--

	premake.codelite = { }
	local clean = premake.actions.clean

	newaction {
		trigger         = "codelite",
		shortname       = "CodeLite",
		description     = "Generate CodeLite project files",
	
		valid_kinds     = { "ConsoleApp", "WindowedApp", "StaticLib", "SharedLib" },
		
		valid_languages = { "C", "C++" },
		
		valid_tools     = {
			cc   = { "gcc" },
		},
		
		onsolution = function(sln)
			premake.generate(sln, "%%.workspace", premake.codelite.workspace)
		end,
		
		onproject = function(prj)
			premake.generate(prj, "%%.project", premake.codelite.project)
		end,
		
		oncleansolution = function(sln)
			clean.file(sln, "%%.workspace")
			clean.file(sln, "%%_wsp.mk")
			clean.file(sln, "%%.tags")
		end,
		
		oncleanproject = function(prj)
			clean.file(prj, "%%.project")
			clean.file(prj, "%%.mk")
			clean.file(prj, "%%.list")
			clean.file(prj, "%%.out")
		end
	}
