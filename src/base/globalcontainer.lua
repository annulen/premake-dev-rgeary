--
-- Container for all projects, and global-level solution configurations
--

	premake5.globalContainer = premake5.globalContainer or {}
	local globalContainer = premake5.globalContainer
	local project 	= premake5.project
	local oven 		= premake5.oven
	local solution	= premake.solution  
	local keyedblocks = premake.keyedblocks  
	local targets = premake5.targets
	local config = premake5.config
	targets.prjToBuild = {}		-- prjToBuild[prjName] = prj
	targets.slnToBuild = {}		-- slnToBuild[slnName] = sln
	targets.prjToExport = {}	-- prjToExport[prjName] = prj
	
--
-- Apply any command line target filters
--
	function globalContainer.filterTargets()
		local prjToBuild = targets.prjToBuild
		local slnToBuild = targets.slnToBuild
		
		for _,v in ipairs(_ARGS) do
			if v:endswith('/') then v = v:sub(1,#v-1) end
			 
			if not premake.action.get(v) then
				
				-- Check if any command line arguments are solutions
				local sln = targets.solution[v] 
				if sln then
					slnToBuild[sln.name] = sln
					for _,v2 in ipairs(sln.projects) do
						prjToBuild[v2.name] = project.getRealProject(v2.name)
					end
				end
				
				-- Check if any command line arguments are projects
				local prj = project.getRealProject(v)
				if prj then
					prjToBuild[prj.name] = prj
				end
			end
		end
		
		if table.isempty(slnToBuild) and table.isempty(prjToBuild) then
			for _,sln in ipairs(targets.solution) do
				slnToBuild[sln.name] = sln
			end
			for _,prj in pairs(targets.allReal) do
				prjToBuild[prj.name] = prj
			end
		end		
	end

--
-- Bake all the projects
--
	function globalContainer.bakeall()
	
		-- Message
		if _ACTION ~= 'clean' then
			local cfgNameList = Seq:new(targets.solution):select('configurations'):flatten():unique()
			if cfgNameList:count() == 0 then
				error("No configurations to build")
			elseif cfgNameList:count() == 1 then
				print("Generating configuration '"..cfgNameList:first().."' ...")
			else
				print("Generating configurations : "..cfgNameList:mkstring(', ').." ...")
			end
		end
		
		-- Filter targets to bake
		globalContainer.filterTargets()
		
		local toBake = table.shallowcopy(targets.prjToBuild)
				
		-- Bake all real projects, but don't resolve usages		
		local tmr = timer.start('Bake projects')
		for prjName,prj in pairs(toBake) do
			project.bake(prj)

			-- Add default configurations
						
			local cfglist = project.bakeconfigmap(prj)
			for _,cfgpair in ipairs(cfglist) do
				local buildVariant = {
					buildcfg = cfgpair[1],
					platform = cfgpair[2],				
				}
				
				-- Add any command-line variants
				if _OPTIONS['define'] then
					local defines = _OPTIONS['define']:split(' ')
					for _,v in ipairs(defines) do
						buildVariant[v] = v
					end
				end
				
				project.addconfig(prj, buildVariant)
			end
			
		end
		timer.stop(tmr)
		
		-- Assign unique object directories to every project configurations
		-- Note : objdir & targetdir can't be inherited from a usage for ordering reasons 
		--globalContainer.bakeobjdirs(toBake)
		
		-- expand all tokens (must come after baking objdirs)
		--[[
		for i,prj in pairs(toBake) do
			oven.expandtokens(prj, "project")
			for cfg in project.eachconfig(prj) do
				oven.expandtokens(cfg, "config")
			end
		end]]
		
		-- Bake all solutions
		solution.bakeall()
	end
	
	-- May recurse
	function globalContainer.bakeUsageProject(usageProj)
	
		-- Look recursively at the uses statements in each project and add usage project defaults for them  
		if usageProj.hasBakedUsage then
			return true
		end
		usageProj.hasBakedUsage = true
		
		local parent
		if ptype(usageProj) == 'project' and usageProj.solution then
			parent = project.getUsageProject( usageProj.solution.name )
		end
		keyedblocks.create(usageProj, parent)

		local realProj = project.getRealProject(usageProj.name, usageProj.namespace)
		if realProj then
		
			-- Bake the real project (RP) first, and apply RP's usages to RP
			project.bake(realProj)
			
			-- Set up the usage target defaults from RP
			for _,buildVariant in ipairs(realProj.buildVariantList) do

				config.addUsageConfig(realProj, usageProj, buildVariant)

			end
		end -- realProj

	end

--
-- Assigns a unique objects directory to every configuration of every project
-- taking any objdir settings into account, to ensure builds
-- from different configurations won't step on each others' object files. 
-- The path is built from these choices, in order:
--
--   [1] -> the objects directory as set in the config
--   [2] -> [1] + the project name
--   [3] -> [2] + the build configuration name
--   [4] -> [3] + the platform name
--

--[[	function globalContainer.bakeobjdirs(allProjects)
		
		if premake.fullySpecifiedObjdirs then
			-- Assume user has assiged unique objdirs
			for _,prj in pairs(allProjects) do
				for cfg in project.eachconfig(prj) do
					-- expand any tokens contained in the field
					oven.expandtokens(cfg, "config", nil, "objdir")
				end
			end
			return
		end
		
		-- function to compute the four options for a specific configuration
		local function getobjdirs(cfg)
			local dirs = {}
			
			local dir = path.getabsolute(path.join(project.getlocation(cfg.project), cfg.objdir or "obj"))
			table.insert(dirs, dir)

			dir = path.join(dir, cfg.project.name)
			table.insert(dirs, dir)
			
			dir = path.join(dir, cfg.buildcfg)
			table.insert(dirs, dir)
			
			if cfg.platform and cfg.platform ~= '' then
				dir = path.join(dir, cfg.platform)
				table.insert(dirs, dir)
			end
			
			return dirs
		end

		-- walk all of the configs in the solution, and count the number of
		-- times each obj dir gets used
		local counts = {}
		local configs = {}
		
		for _,prj in pairs(allProjects) do
			for cfg in project.eachconfig(prj) do
				-- expand any tokens contained in the field
				oven.expandtokens(cfg, "config", nil, "objdir")
				
				-- get the dirs for this config, and remember the association
				local dirs = getobjdirs(cfg)
				configs[cfg] = dirs
				
				for _, dir in ipairs(dirs) do
					counts[dir] = (counts[dir] or 0) + 1
				end
			end
		end

		-- now walk the list again, and assign the first unique value
		for cfg, dirs in pairs(configs) do
			for _, dir in ipairs(dirs) do
				if counts[dir] == 1 then
					cfg.objdir = dir 
					break
				end
			end
		end
	end
]]

