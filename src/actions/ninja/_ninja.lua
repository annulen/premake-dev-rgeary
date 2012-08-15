--
-- _ninja.lua
-- Define the Ninja Build action.
--

	premake.actions.ninja = {}
	local ninja = premake.actions.ninja
	local solution = premake.solution
	local project = premake5.project
	local clean = premake.actions.clean
	local config = premake5.config
	ninja.slnconfigs = {}		-- all configurations
	ninja.buildFileHandle = nil
	
	ninjaRoot = ninjaRoot or os.getcwd()
	
--
-- The Ninja build action
--
	newaction {
		trigger         = "ninja",
		shortname       = "Ninja Build",
		description     = "Generate ninja files for Ninja Build.", -- Currently only tested with C++",

		-- temporary
		isnextgen = true,
		
		valid_kinds     = { "ConsoleApp", "WindowedApp", "StaticLib", "SharedLib" },

		valid_languages = { "C", "C++" },

		valid_tools     = {
			cc     = { "gcc", "icc" },
		},
		
		buildFileHandle = nil,
		
		onsolution = function(sln)
			premake.generate(sln, ninja.getDefaultBuildFilename(sln), ninja.generate_defaultbuild) 
			if ninja.buildFileHandle then
				error("Not supported : Can't start more than one solution at once")
			end
			ninja.buildFileHandle = premake.generateStart(sln, ninja.getSolutionBuildFilename(sln))
			ninja.generate_solution(sln)
		end,
		
		onSolutionEnd = function(sln)
			if ninja.buildFileHandle then
				local fileLen = ninja.buildFileHandle:seek('end', 0)
				if fileLen then
					printf('  %.0f kb', fileLen/1024.0)
				end
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
			clean.file(sln, ninja.getSolutionBuildFilename(sln))
		end,
		
		oncleanproject = function(prj)
			clean.file(prj, ninja.getDefaultBuildFilename(prj))
		end
	}
	
	function ninja.getDefaultBuildFilename(obj)
		return path.join(obj.basedir, 'build.ninja')
	end
	
	function ninja.getSolutionBuildFilename(sln)
		return path.join(sln.basedir, 'build_'..sln.name .. '.ninja')
	end
	
	function ninja.onExecute()
		local args = Seq:new(_ARGS) 
		
		if args:contains('build') then
			return os.executef('ninja')
		
		elseif args:contains('print') then
			local printAction = premake.action.get('print')
			premake.action.call(printAction.trigger)
		end
	end

--
-- Write out a file which sets environment variables then subninjas to the actual build
--
	function ninja.generate_defaultbuild(sln)
		local rootDir = ninjaRoot
		_p('root=' .. ninjaRoot)
		_p('rule exec')
		_p(' command=$cmd')
		_p(' description=$description')
		_p('')
		_p('subninja $root/' .. path.getrelative(rootDir, ninja.getSolutionBuildFilename(sln)))
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


	-- returns the input files per config, per buildaction
	--  local filesInConfig =  getInputFiles(prj)[cfg.shortname][buildaction]
	
	function ninja.getInputFiles(prj)
		if prj.filesPerConfig then
			return prj.filesPerConfig
		end
		
		local tr = project.getsourcetree(prj)
		local filesPerConfig = {}	-- list of files per config
		local defaultAction = 'Compile'
		
		for cfg in project.eachconfig(prj) do
			filesPerConfig[cfg] = {}
		end			
		
		premake.tree.traverse(tr, {
			onleaf = function(node, depth)
				-- figure out what configurations contain this file
				local inall = true
				local filename = node.abspath
				local custom = false
				
				for cfg in project.eachconfig(prj) do
					local filecfg = config.getfileconfig(cfg, filename)
					local buildaction = filecfg.buildaction or defaultAction
					
					filesPerConfig[cfg][buildaction] = filesPerConfig[cfg][buildaction] or {}
					table.insert( filesPerConfig[cfg][buildaction], filename)  
					--custom = (filecfg.buildrule ~= nil)
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
		if string.sub(varName,1,1) == '$' then
			return varName
		end
    	if true or string.find(varName, ".", 1, true) then
    		varName = '${' .. varName .. '}'
    	else
    	   	varName = '$' .. varName
    	end
    	return varName
	end
	
	-- Returns (newVarName, found) 
	--	newVarName : a mangled varName which will refer to the specified unique value
	--  found : true is if it's already found
	--  Just to make the ninja file look nicer
	ninja.globalVars = {}  
	ninja.globalVarValues = {}  
	function ninja.setGlobalVar(varName, value, alternateVarNames)
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
		ninja.globalVarValues[value] = varNameM
		return varNameM,false
	end
	
	function ninja.getGlobalVar(value, setNameIfNew)
		local var = ninja.globalVarValues[value]
		if (not var) and setNameIfNew then
			return ninja.setGlobalVar(setNameIfNew, value)
		end
		return var, true
	end
	
	-- Substitutes variables in to v, to make the string the smallest size  
	function ninja.getBestGlobalVar(v)
		-- try $root first
		v = string.replace(v, ninja.globalVars['root'], '$root')
		local bestV = v
		
		for varName,varValue in pairs(ninja.globalVars) do
			local varNameN = ninja.escVarName(varName)
			local replaced = string.replace(v, varValue, varNameN)
			local replaced2 = string.replace(bestV, varValue, varNameN)
			if #replaced < #bestV then
				bestV = replaced
			end
			if #replaced2 < #bestV then
				bestV = replaced2
			end
		end
		return bestV
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


