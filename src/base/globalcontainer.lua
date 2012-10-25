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
	targets.prjToBuild = {}
	targets.slnToBuild = {}
	
--
-- Apply any command line target filters
--
	function globalContainer.filterTargets()
		local prjToBuild = targets.prjToBuild
		local slnToBuild = targets.slnToBuild
		for _,v in ipairs(_ARGS) do
			if v:endswith('/') then v = v:sub(1,#v-1) end 
			if not premake.action.get(v) then
				local sln = targets.solution[v] 
				if sln then
					table.insert( slnToBuild, sln )
					for _,v2 in ipairs(sln.projects) do
						table.insert( prjToBuild, v2 )
					end
				end
				local prj = project.getRealProject(v)
				if prj then
					table.insert( prjToBuild, prj )
				end
			end
		end
		
		if #targets.slnToBuild == 0 and #targets.prjToBuild == 0 then
			targets.slnToBuild = targets.solution
			targets.prjToBuild = targets.allReal
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
		
		local toBake = targets.prjToBuild
				
		-- Bake all real projects, but don't resolve usages		
		local tmr = timer.start('Bake projects')
		for prjName,prj in pairs(toBake) do
			project.bake(prj)
		end
		timer.stop(tmr)
		
		-- Assign unique object directories to every project configurations
		-- Note : objdir & targetdir can't be inherited from a usage for ordering reasons 
		globalContainer.bakeobjdirs(toBake)
		
		-- Apply the usage requirements now we have resolved the objdirs
		--  This function may recurse
		for _,prj in pairs(toBake) do
			globalContainer.applyUsageRequirements(prj)
		end		
				
		-- expand all tokens (must come after baking objdirs)
		for i,prj in pairs(toBake) do
			oven.expandtokens(prj, "project")
			for cfg in project.eachconfig(prj) do
				oven.expandtokens(cfg, "config")
			end
		end
		
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
			globalContainer.applyUsageRequirements(realProj)
			
			-- Set up the usage target defaults from RP
			for _,cfgPairing in ipairs(realProj.cfglist) do
				
				local buildcfg = cfgPairing[1]
				local platform = cfgPairing[2]
				local realCfg = project.getconfig(realProj, buildcfg, platform)

				local usageKB = keyedblocks.createblock(usageProj.keyedblocks, { buildcfg, platform })

				-- To use a library project, you need to link to its target
				--  Copy the build target from the real proj
				if realCfg.buildtarget and realCfg.buildtarget.abspath then
					local realTargetPath = realCfg.buildtarget.abspath
					if realCfg.kind == 'SharedLib' then
						-- link to the target as a shared library
						oven.mergefield(usageKB, "linkAsShared", { realTargetPath })
					elseif realCfg.kind == 'StaticLib' then
						-- link to the target as a static library
						oven.mergefield(usageKB, "linkAsStatic", { realTargetPath })
					elseif realCfg.kind == 'SourceGen' then
						oven.mergefield(usageKB, "compiledepends", { realProj.name })
					elseif not realCfg.kind then
						error("Can't use target, missing cfg.kind")
					end
				end
				
				-- Propagate fields
				for fieldName, field in pairs(premake.propagatedFields) do
					local usagePropagate = field.usagePropagation
					local value = realCfg[fieldName]
					local propagateValue = false
					
					if realCfg[fieldName] then
						if usagePropagate == "Always" then
							propagateValue = value
						elseif usagePropagate == "StaticLinkage" and realCfg.kind == "StaticLib" then
							propagateValue = value
						elseif usagePropagate == "SharedLinkage" and realCfg.kind == "StaticLib" or realCfg.kind == "SharedLib" then
							propagateValue = value
						elseif type(usagePropagate) == 'function' then
							propagateValue = usagePropagate(realCfg, value)
						end
						
						if propagateValue then
							oven.mergefield(usageKB, fieldName, propagateValue )
						end
					end						
				end
				
				keyedblocks.resolveUses(usageKB, usageProj)
				
			end
		end -- realProj

	end
	
	-- May recurse
	function globalContainer.applyUsageRequirements(prj)
		return true
--[[
		if prj.isUsage or prj.hasBakedUsage then
			return true
		end
		prj.hasBakedUsage = true
		
		-- Bake the project's configs if we haven't already
		project.bake(prj)
	
		-- Resolve "uses" for each config, and apply
		for cfg in project.eachconfig(prj) do

			for _,useProjName in ipairs(cfg.uses or {}) do
				local useProj = project.getUsageProject( useProjName, prj.namespaces )
				local cfgFilterTerms = getValues(cfg.usesconfig)
				
				if not useProj then
					-- can't find the project, perhaps we've specified configuration filters also
					local parts = useProjName:split('.|')
					useProj = project.getUsageProject( parts[1], prj.namespaces )
					if not useProj then
						error("Could not find project/usage "..useProjName..' in project '..prj.name)
					end
					cfgFilterTerms = parts
				end
			
				cfg.linkAsStatic = cfg.linkAsStatic or {}
				cfg.linkAsShared = cfg.linkAsShared or {}
				
				-- make sure the usage project is also baked
				globalContainer.bakeUsageProject(useProj)
			
				-- Merge in the usage requirements from the usage project
				--  .getfield may recurse in to globalContainer.bakeUsageProject if the usage project has unbaked uses
				keyedblocks.getfield(useProj, cfgFilterTerms, nil, cfg)

			end -- each use
			
		end  -- each cfg			
]]		
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

	function globalContainer.bakeobjdirs(allProjects)
		
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

