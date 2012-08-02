--
-- _ninja.lua
-- Define the Ninja Build action.
--

	premake.actions.ninja = {}
	local ninja = premake.actions.ninja
	local solution = premake.solution
	local project = premake5.project

--
-- The Ninja build action
--
	newaction {
		trigger         = "ninja",
		shortname       = "Ninja Build",
		description     = "Generate build.ninja files for Ninja Build. Currently only tested with C++",

		-- temporary
		isnextgen = true,
		
		valid_kinds     = { "ConsoleApp", "WindowedApp", "StaticLib", "SharedLib" },

		valid_languages = { "C", "C++" },

		valid_tools     = {
			cc     = { "gcc", "icc" },
		},

		onsolution = function(sln)
			premake.generate(sln, ninja.getBuildFilename(sln), ninja.generate_solution)
		end,

		onproject = function(prj)
			premake.generate(prj, ninja.getBuildFilename(prj), ninja.generate_project)
		end,
		
		oncleansolution = function(sln)
			premake.clean.file(sln, ninja.getBuildFilename(sln))
		end,
		
		oncleanproject = function(prj)
			premake.clean.file(prj, ninja.getBuildFilename(prj))
		end
	}
	
	-- Get the filename of the ninja build file, usually "build.ninja"
	function ninja.getBuildFilename(sln)
		return "build.ninja"
	end

--
-- Write out the default configuration rule for a solution or project.
-- @param target
--    The solution or project object for which a build file is being generated.
--

	function ninja.defaultconfig(target)
		-- find the configuration iterator function
		local eachconfig = iif(target.project, project.eachconfig, solution.eachconfig)
		local iter = eachconfig(target)
		
		-- grab the first configuration and write the block
		local cfg = iter()
		if cfg then
			_p("# " + target.name)
			_p('')
		end
	end


--
-- Escape a string so it can be written to a ninja build file.
--

	function ninja.esc(value)
		local result
		if (type(value) == "table") then
			result = { }
			for _,v in ipairs(value) do
				table.insert(result, ninja.esc(v))
			end
			return result
		else
			-- handle simple replacements
			result = value:gsub("$", "$$")
			return result
		end
	end

--
-- Write out raw ninja rules for a configuration.
--
	function ninja.settings(cfg, toolset)
		if #cfg.rawninja > 0 then
			for _, value in ipairs(cfg.rawninja) do
				_p(value)
			end
		end
	end

