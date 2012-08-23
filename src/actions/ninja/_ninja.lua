--
-- _ninja.lua
-- Define the Ninja Build action.
--

	premake.actions.ninja = {}
	premake.abstract.ninjaVar = {}
	local ninja = premake.actions.ninja
	local ninjaVar = premake.abstract.ninjaVar

	local solution = premake.solution
	local project = premake5.project
	local clean = premake.actions.clean
	local config = premake5.config
	ninja.buildFileHandle = nil
	local slnDone = {}
	local globalScope = {}
	
	ninjaRoot = ninjaRoot or repoRoot
	
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
		
		onStart = function()
			ninjaRoot = ninjaRoot or path.getabsolute(_WORKING_DIR)
			ninja.openFile(path.join(ninjaRoot, 'build.ninja'))
			globalScope = ninja.newScope('build.ninja')
		end,
		
		onSolution = function(sln)
			ninja.onSolution(sln.name)
		end,
		
		onSolutionEnd = function()
			ninja.onSolutionEnd()
		end,
		
		execute = function()
			ninja.onExecute()
		end,
		
		oncleansolution = function(sln)
			clean.file(sln, ninja.getSolutionBuildFilename(sln))
			clean.file(sln, ninja.getDefaultBuildFilename(sln))
		end,
	}
	
	function ninja.onSolution(slnName)
		local sln = solution.list[slnName]
		-- Build included solutions first
		
		if not slnDone[slnName] then
			if sln.includesolution then
				for _,v in ipairs(sln.includesolution) do
					ninja.onSolution(v)
				end
			end
							
			ninja.generateSolution(sln, globalScope)
			--premake.generate(sln, ninja.getSolutionBuildFilename(sln), ninja.generateSolution)
			--premake.generate(sln, ninja.getDefaultBuildFilename(sln), ninja.generateDefaultBuild) 
			slnDone[slnName] = true
		end
	end
	
	function ninja.onSolutionEnd()
		ninja.writeFooter(globalScope)
		ninja.closeFile()
		slnDone = {}
	end
	
	function ninja.openFile(filename)
		if ninja.buildFileName ~= filename then
			ninja.closeFile()
		end
		if not ninja.buildFileHandle then
			ninja.buildFileName = filename
			ninja.buildFileHandle = premake.generateStart(filename)
			return true
		end
		return false
	end
	
	function ninja.closeFile()
		if ninja.buildFileHandle then
			premake.generateEnd(ninja.buildFileHandle)
		end
		ninja.buildFileHandle = nil
		ninja.buildFileName = nil
	end

	function ninja.getSolutionBuildFilename(sln)
		return path.join(sln.basedir, 'build_'..sln.name..'.ninja')
	end
	
	function ninja.getDefaultBuildFilename(sln)
		return path.join(sln.basedir, 'build.ninja')
	end
	
	function ninja.onExecute()
		local args = Seq:new(_ARGS) 
		
		if not args:contains('nobuild') then
			print('Running ninja...')
			local cmd = 'ninja'
			if _OPTIONS['threads'] then
				cmd = cmd .. ' -j'..tostring(_OPTIONS['threads'])
			end
			return os.executef(cmd)
		
		elseif args:contains('print') then
			local printAction = premake.action.get('print')
			premake.action.call(printAction.trigger)
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
	ninja.scope = {}
	ninjaVar = {}
	ninjaVar.nameToValue = {}
	ninjaVar.valueToName = {}
	ninjaVar.valueSeen = {}
	
	function ninja.newScope(scopeName)
		local s = inheritFrom(ninjaVar)
		
		ninja.scope[scopeName] = s
		
		s:set('root', ninjaRoot)
		
		return s
	end
	
	-- Call this function 'threshold' times with the same value & it'll set the var
	-- returns : useThis, isNewVar
	function ninjaVar:trySet(varName, value, threshold)
		-- Check if it is already a variable
		local existingVarName = self.valueToName[value]
		if existingVarName then
			return ninja.escVarName(existingVarName), false
		end
		
		local count = (self.valueSeen[value] or 0) + 1
		self.valueSeen[value] = count
		
		if count > threshold then
			-- Create a new var
			self:set(varName, value)
			return ninja.escVarName(varName), true
		else
			return value, false
		end		
	end
	
	function ninjaVar:set(varName, value, alternateVarNames)
		local varNameM = varName
		local i = 1
		while self.nameToValue[varNameM] do
			-- Found a var which already exists with this value
			if self.nameToValue[varNameM] == value then
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
		self.nameToValue[varNameM] = value
		self.valueToName[value] = varNameM
		return varNameM,false
	end
	
	function ninjaVar:add(name, valuesToAdd)
		local r = self.nameToValue[name]
		if r then
			if type(r) ~= 'table' then
				r = { r }
			end
			for _,v in ipairs(valuesToAdd) do
				table.insert(r, v)
			end
			self.nameToValue[name] = r
		else
			self.nameToValue[name] = valuesToAdd
		end
	end
	
	function ninjaVar:get(name)
		return self.nameToValue[name]
	end

	function ninjaVar:getName(value, setNameIfNew)
		local var = self.valueToName[value]
		if (not var) and setNameIfNew then
			return self:set(setNameIfNew, value)
		end
		return var, true
	end
	
	-- Substitutes variables in to v, to make the string the smallest size  
	function ninjaVar:getBest(v)
		local tmr = timer.start('getBest')
		-- try $root first
		v = string.replace(v, ninjaRoot, '$root')
		local bestV = v
		
		for varValue,varName in pairs(self.valueToName) do
			if type(varValue) == 'string' and #varValue > 0 then
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
		end
		timer.stop(tmr)
		return bestV
	end
	
	function ninjaVar:include(otherScopeName)	
		local otherScope = ninja.scope[otherScopeName]
		if not otherScope then
			error('Could not find ninja var scope ' .. otherScopeName)
		end
		for k,v in pairs(otherScope.nameToValue) do
			self.nameToValue[k] = v
			self.valueToName[v] = k 
		end
	end
