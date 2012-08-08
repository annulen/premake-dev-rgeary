--
-- _ninja.lua
-- Define the Ninja Build action.
--

	premake.actions.ninja = {}
	local ninja = premake.actions.ninja
	local solution = premake.solution
	local project = premake5.project
	local clean = premake.actions.clean
	ninja.slnconfigs = {}		-- all configurations
	ninja.buildFileHandle = nil
--
-- The Ninja build action
--
	newaction {
		trigger         = "ninja",
		shortname       = "Ninja Build",
		description     = "Generate build.ninja files for Ninja Build.", -- Currently only tested with C++",

		-- temporary
		isnextgen = true,
		
		valid_kinds     = { "ConsoleApp", "WindowedApp", "StaticLib", "SharedLib" },

		valid_languages = { "C", "C++" },

		valid_tools     = {
			cc     = { "gcc", "icc" },
		},
		
		buildFileHandle = nil,

		onsolution = function(sln)
			if ninja.buildFileHandle then
				error("Not supported : Can't start more than one solution at once")
			end
			ninja.buildFileHandle = premake.generateStart(sln, "build.ninja")
			ninja.generate_solution(sln)
		end,
		
		onSolutionEnd = function(sln)
			if ninja.buildFileHandle then
				premake.generateEnd(ninja.buildFileHandle)
			end
			ninja.buildFileHandle = nil
		end,

		onproject = function(prj)
			ninja.generate_project(prj)
		end,
		
		execute = function()
			ninja.onExecute()
		end,
		
		oncleansolution = function(sln)
			clean.file(sln, "build.ninja")
		end,
		
		oncleanproject = function(prj)
			--clean.file(prj, ninja.getBuildFilename(prj))
		end
	}
	
	function ninja.onExecute()
		local args = Seq:new(_ARGS) 
		
		if args:contains('build') then
			return os.execute('ninja')
		
		elseif args:contains('print') then
			local printAction = premake.action.get('print')
			premake.action.call(printAction.trigger)
		end
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


	-- returns the input files per config
	--  files which are in all configs are under ['']
	--
	--	local filesInAllConfigs = getInputFiles(prj)['']
	--  local filesOnlyInConfig =  getInputFiles(prj)[cfg.shortname]
	
	function ninja.getInputFiles(prj)
		if prj.filesPerConfig then
			return prj.filesPerConfig
		end
		
		local tr = project.getsourcetree(prj)
		local filesPerConfig = {}	-- list of files per config
		
		filesPerConfig[''] = {}
		for cfg in project.eachconfig(prj) do
			filesPerConfig[cfg] = {}
		end			
		
		premake.tree.traverse(tr, {
			onleaf = function(node, depth)
				-- figure out what configurations contain this file
				local inall = true
				local filename = node.abspath
				local incfg = {}
				local inall = true
				local custom = false
				
				for cfg in project.eachconfig(prj) do
					local filecfg = premake5.config.getfileconfig(cfg, node.abspath)
					if filecfg then
						incfg[cfg] = filecfg
						custom = (filecfg.buildrule ~= nil)
					else
						inall = false
					end
				end

				-- if this file exists in all configurations, write it to
				-- the project's list of files, else add to specific cfgs
				if inall then
					table.insert(filesPerConfig[''], filename)
				else
					for cfg in project.eachconfig(prj) do
						if incfg[cfg] then
							table.insert(filesPerConfig[cfg], filename)
						end
					end
				end
					
			end
		})
		prj.filesPerConfig = filesPerConfig
		return filesPerConfig
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
	
	-- Get the syntax for accessing a variable, with correct escaping
	 
	function ninja.escVarName(varName)
    	varName = '$' .. varName
    	if string.find(varName, ".", 1, true) then
    		varName = '${' .. k .. '}'
    	end
    	return varName
	end
	
	-- Returns a mangled varName which will refer to the specified unique value. 2nd return var is if it's already set
	--  Just to make the ninja file look nicer
	ninja.globalVars = {}  
	function ninja.setGlobal(varName, value, alternateVarNames)
		local varNameM = varName
		local i = 1
		while ninja.globalVars[varNameM] do
			-- Found a var which already exists with this value
			if ninja.globalVars[varNameM] == value then
				return varNameM,true
			end
			
			if alternateVarNames and #alternateVarNames > 0 then
				varNameM = alternateVarNames[1]
				alternateVarNames = table.remove(alternateVarNames, 1)
			else
				i = i + 1
				varNameM = varName .. tostring(i)
			end
		end
		ninja.globalVars[varNameM] = value
		return varNameM,false
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


