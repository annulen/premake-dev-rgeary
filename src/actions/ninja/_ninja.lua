--
-- _ninja.lua
-- Define the Ninja Build action.
--

	premake.actions.ninja = {}
	premake.abstract.ninjaVar = {}
	local ninja = premake.actions.ninja
	local ninjaVar = premake.abstract.ninjaVar

	local targets = premake5.targets
	local solution = premake.solution
	local project = premake5.project
	local clean = premake.actions.clean
	local config = premake5.config
	ninja.buildFileHandle = {}
	local slnDone = {}
	local globalScope = {}
	
--
-- The Ninja build action. Currently only tested with C++
--
	newaction {
		trigger         = "ninja",
		shortname       = "Ninja Build",
		description     = { "Generate ninja files for Ninja Build. Default action will place ninja files in the targetdir", }, 
							--"'ninja local' will place ninja files in the source tree"},
		-- temporary
		isnextgen = true,
		
		valid_kinds     = { "ConsoleApp", "WindowedApp", "StaticLib", "SharedLib" },

		valid_languages = { "C", "C++" },

		valid_tools     = {
			cc     = { "gcc", "icc" },
		},
		
		buildFileHandle = nil,
		
		onStart = function()
			local slnList = Seq:ipairs(targets.solution)
			if slnList:count() > 1 then
				printDebug('Building solutions : '..slnList:select('name'):mkstring(', '))
			else 
				printDebug('Building solution : '..slnList:first().name)
			end
		end,
		
		onSolution = function(sln)
			ninja.onSolution(sln.name)
		end,

		onProject = function(sln)
			ninja.onProject(sln.name)
		end,
		
		onEnd = function()
			ninja.onEnd()
		end,
		
		execute = function()
			ninja.onExecute()
		end,
		
		oncleansolution = function(sln)
			--clean.file(sln, ninja.getSolutionBuildFilename(sln))
			clean.file(sln, path.join(sln.basedir, 'build.ninja'))
			ninja.setNinjaBuildDir(sln)
			clean.file(sln, path.join(ninja.builddir, 'buildedges.ninja'))
			clean.file(sln, path.join(ninja.builddir, '.ninja_log'))
		end,
	}
	
	function ninja.onSolution(slnName)
		local sln = targets.solution[slnName]
		if not sln then
			print('Could not find solution '..tostring(slnName))
			return
		end
		
		-- Build included solutions first
		if not slnDone[slnName] then
			if sln.includesolution then
				for _,v in ipairs(sln.includesolution) do
					ninja.onSolution(v)
				end
			end

			ninja.setNinjaBuildDir(sln)
			ninja.openFile(path.join(ninja.builddir, 'buildedges.ninja'))
			ninja.generateSolution(sln, globalScope)

			-- Must come after the main buildedges.ninja as we need to write out the default build statements
			ninja.checkIgnoreFiles(sln.basedir)
			ninja.generateDefaultBuild(sln, sln.basedir, globalScope)

			slnDone[slnName] = true
		end
	end
	
	function ninja.onProject(prjName)
		local prj = project.getRealProject(prjName)
		if not prj then
			print("Warning : Could not find project "..prjName)
		else
			local sln = prj.solution
			ninja.onSolution(sln.name)
		end
	end
	
	-- After the last solution
	function ninja.onEnd()
		if not ninja.builddir then return end
		local f = ninja.openFile(path.join(ninja.builddir, 'buildedges.ninja'))
		ninja.writeFooter(globalScope)
		ninja.closeFile(f)

		-- Write a default build for the repoRoot		
		if repoRoot ~= ninja.builddir and (not ninja.scope[repoRoot]) then
			ninja.checkIgnoreFiles(repoRoot)
			--ninja.generateDefaultBuild(nil, repoRoot, globalScope)
		end 
		
		slnDone = {}
	end
	
	function ninja.openFile(filename)
		if not ninja.buildFileHandle[filename] then
			ninja.buildFileName = filename
			ninja.buildFileHandle[filename] = premake.generateStart(filename, true)
			globalScope = ninja.newScope(filename)
		else
			io.output(ninja.buildFileHandle[filename])
			globalScope = ninja.scope[filename]
		end
		return filename
	end
	
	function ninja.closeFile(filename)
		if filename ~= ninja.buildFileName then
			error('Close files in order. Expected '..ninja.buildFileName)
		end
		if filename and ninja.buildFileHandle[filename] then
			local h = ninja.buildFileHandle[filename]
			
			if _OPTIONS['debug'] and type(h) == 'userdata' then
				local fileLen = h:seek('end', 0)
				local cwd = os.getcwd()
				
				if fileLen then
					printf('Generated %s : %.0f kb', path.getrelative(cwd, filename), fileLen/1024.0)
				end
			end
			
			premake.generateEnd(h, filename)
			ninja.buildFileHandle[filename] = nil
		end
		ninja.buildFileName = nil
	end

	function ninja.getSolutionBuildFilename(sln)
		return path.join(sln.basedir, 'build_'..sln.name..'.ninja')
	end

	function ninja.setNinjaBuildDir(sln)
		-- builddir is where the build log & main ninja file is placed
		if (not ninja.builddir) then
			ninja.builddir = iif( sln.ninjaBuildDir, sln.ninjaBuildDir, repoRoot)
			ninja.builddir = ninja.builddir:replace("$root",repoRootPlain)
			ninja.checkIgnoreFiles(ninja.builddir)
		end
		ninja.builddir = path.getabsolute(ninja.builddir)
	end
	
	function ninja.onExecute()
		local args = Seq:new(_ARGS) 
		
		if not _OPTIONS['nobuild'] then
			local cmd = 'ninja'
			if _OPTIONS['threads'] then
				cmd = cmd .. ' -j'..tostring(_OPTIONS['threads'])
			end
			
			if os.isfile('build.ninja') then
				print('Building with ninja...')
			else

				local dir = os.getcwd()
				while dir ~= '/' do
					if os.isfile(path.join(dir,'build.ninja')) then
						break
					end
					dir = path.getdirectory(dir)
				end
				if dir == '/' then
					print('Unknown build, no solution found in current directory or its parents')
					return
				end
				
				local ninjadir = path.getrelative(os.getcwd(), dir)
				if ninjadir:startswith('..') then ninjadir = dir end					
				print('Running ninja on '..ninjadir)
				
				cmd = cmd .. ' -q -C ' .. dir
			end
			
			if _OS == 'windows' then
				cmd = "IS_RUNNING_PREMAKE=TRUE && "..cmd
			else
				cmd = "export IS_RUNNING_PREMAKE=TRUE && "..cmd
			end
			local rv = os.executef(cmd)
			if rv ~= 0 then
				os.exit(rv)
			end
		elseif args:contains('print') then
			local printAction = premake.action.get('print')
			premake.action.call(printAction.trigger)
		end
	end
	
	function ninja.checkIgnoreFiles(dir)
		local sourceControls = {
			{ dir = '.git', ignore = '.gitignore' },
			{ dir = '.hg',  ignore = '.hgignore'  },
		}
		local foundFile = {}
		
		if _OPTIONS['automated'] then
			return
		end
		
		for _,sc in ipairs(sourceControls) do
			if os.isdir(path.join(dir, sc.dir)) then  
				
				local ignoreFile = path.join(dir, sc.ignore)
				local foundIgnore = false
				if os.isfile(ignoreFile) then
					local f = io.open(ignoreFile, "r")
					for line in f:lines() do
						if line:find('.ninja',1,true) then
							foundIgnore = true
						end
					end
					io.close(f)
				end
	
				if not foundIgnore then
					-- Not found
					print('Did not find *.ninja in the '..sc.ignore..' file ('..dir..'). Do you want to add it? [Recommended] (Y/n)')
					local key = io.input():read(1)
					if key:lower() == 'y' then
						local f
						if os.isfile(ignoreFile) then
							f = io.open(ignoreFile, "a")
						else
							f = io.open(ignoreFile, "w")
						end
						f:write('*.ninja\n')
						io.close(f)				
					end
				end
			end
		end
	end

	-- returns the input files per config, per buildaction
	--  local filesInConfig =  getInputFiles(prj)[cfg.shortname][buildaction]
	
	function ninja.getInputFiles(prj)
		if prj.filesPerConfig then
			return prj.filesPerConfig
		end
		
local tmr = timer.start('ninja.getInputFiles')
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
					local filecfg = config.getfileconfig(cfg, filename) or {}
					local buildaction = filecfg.buildaction or defaultAction
					
					local t = filesPerConfig[cfg][buildaction] or {}
					filesPerConfig[cfg][buildaction] = t
					--table.insert( filesPerConfig[cfg][buildaction], filename)  
					t[filename] = filecfg
					table.insert( t, filename )
					--custom = (filecfg.buildrule ~= nil)
				end
				
			end
		})
		prj.filesPerConfig = filesPerConfig
		
timer.stop(tmr)		
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
			result = value:gsub("%$%(", "%$%$%(")
			return result
		end
	end
	
	function ninja.escPath(value)
		return value
	end
	
	-- Get the syntax for accessing a variable, with correct escaping
	 
	function ninja.escVarName(varName)
		if string.sub(varName,1,1) == '$' then
			return varName
		end
		if #varName == 0 then
			return varName
		end
   		varName = '${' .. varName .. '}'
    	return varName
	end
	
	-- Prepare a string to be a variable name
	function ninja.replaceSpecialChars(s)
		return s:gsub("[=!\"£$%^&*()+{}%[%];:'@,<>/?|\\]","_")
	end
	
-- Returns (newVarName, found) 
--	newVarName : a mangled varName which will refer to the specified unique value
--  found : true is if it's already found
--  Just to make the ninja file look nicer
	ninja.scope = {}
	ninjaVar = {}
	ninjaVar.nameToValue = {}
	ninjaVar.findNameIdx = {}
	ninjaVar.valueToName = {}
	ninjaVar.valueToWeight = {}
	
	function ninja.newScope(scopeName)
		local s = inheritFrom(ninjaVar)
		
		ninja.scope[scopeName] = s
		
		s:set('','')
		s:set('builddir', ninja.builddir)
		s:set('root', repoRoot)
		s:set('tmp', '')
		
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
		
		local count = (self.valueToWeight[value] or 0) + 1
		self.valueToWeight[value] = count
		
		if count > threshold then
			-- Create a new var
			self:set(varName, value)
			return ninja.escVarName(varName), true
		else
			return value, false
		end		
	end
	
	-- returns varName, alreadyExists
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
				i = (self.findNameIdx[varName] or i) + 1
				self.findNameIdx[varName] = i
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

	-- returns varName, alreadyExists
	function ninjaVar:getName(value, setNameIfNew)
		local var = self.valueToName[value]
		if (not var) and setNameIfNew then
			return self:set(setNameIfNew, value)
		end
		return var, true
	end
	
	-- Substitutes variables in to v, to make the string the smallest size  
	function ninjaVar:getBest(v)
		if v == '' then return '' end
		
		local tmr = timer.start('ninja.getBest')
		-- try $root first
		v = string.replace(v, repoRoot, "$root/")
		local bestV = self.valueToName[v]
		--[[
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
		]]
		if bestV then
			v = ninja.escVarName(bestV)
		end
		timer.stop(tmr)
		return v
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

	function ninjaVar:getBuildVars(inputs, weight, newVarPrefix)
		newVarPrefix = newVarPrefix or 'tmp'
		local rv = {}
		for k,v in pairs(inputs or {}) do
			if v ~= '' and not v:startswith('$') then
			
				if v:find(repoRoot,1,true) then
					v = string.replace(v, repoRoot, "$root/")
					inputs[k] = v
				end
			
				local vWeight = (self.valueToWeight[v] or 0) + weight
				self.valueToWeight[v] = vWeight
				local createNewVars = iif( vWeight > 5, newVarPrefix, nil)
			
				local varName, alreadyExists = self:getName(v, createNewVars)
				if varName and k ~= varName then
					inputs[k] = ninja.escVarName(varName)
				end
				if not alreadyExists then
					rv[varName] = v
				end
			end
		end
		return rv
	end