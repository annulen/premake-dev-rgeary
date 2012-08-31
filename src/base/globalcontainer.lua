--
-- Container for all projects, and global-level solution configurations
--

	premake5.globalContainer = premake5.globalContainer or {}
	local globalContainer = premake5.globalContainer
	local project 	= premake5.project
	local oven 		= premake5.oven
	local solution	= premake.solution  
	local keyedblocks = premake.keyedblocks  

	-- List of all real & all usage projects
	globalContainer.allUsage = {}
	globalContainer.allReal = {}

--
-- Bake all the projects
--
	function globalContainer.bakeall()
	
		local cfgNameList = Seq:new(solution.list):select('configurations'):flatten():unique()
		if cfgNameList:count() == 1 then
			print("Building configuration "..cfgNameList:first().." ...")
		else
			print("Building configurations : "..cfgNameList:mkstring(', ').." ...")
		end
		
		-- Bake all real projects, but don't resolve usages		
		local tmr = timer.start('Bake projects')
		for i,prj in ipairs(globalContainer.allReal) do
			project.bake(prj)
		end
		timer.stop(tmr)
		
		-- Assign unique object directories to every project configurations
		-- Note : objdir & targetdir can't be inherited from a usage for ordering reasons 
		globalContainer.bakeobjdirs(globalContainer.allReal)
		
		-- Apply the usage requirements now we have resolved the objdirs
		--  This function may recurse
		for _,prj in ipairs(globalContainer.allReal) do
			globalContainer.applyUsageRequirements(prj)
		end		
				
		-- expand all tokens (must come after baking objdirs)
		for i,prj in ipairs(globalContainer.allReal) do
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
		
		keyedblocks.create(usageProj)

		local realProj = project.getRealProject(usageProj.name)
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
				usageKB.values = usageKB.values or {}

				-- Copy in default build target from the real proj
				if realCfg.buildtarget and realCfg.buildtarget.abspath then
					local realTargetPath = realCfg.buildtarget.abspath
					if realCfg.kind == 'SharedLib' then
						-- link to the target as a shared library
						oven.mergefield(usageKB.values, "linkAsShared", { realTargetPath })
					elseif realCfg.kind == 'StaticLib' then
						-- link to the target as a static library
						oven.mergefield(usageKB.values, "linkAsStatic", { realTargetPath })
					elseif not realCfg.kind then
						error("Can't use target, missing cfg.kind")
					end
				end
							
				-- Copy across some flags
				local function mergeflag(destFlags, srcFlags, flagName)
					if srcFlags and srcFlags[flagName] and (not destFlags[flagName]) then
						destFlags[flagName] = flagName
						table.insert(destFlags, flagName)
					end
				end
				usageKB.values.flags = usageKB.values.flags or {}
				mergeflag(usageKB.values.flags, realCfg.flags, 'ThreadingMulti')
				mergeflag(usageKB.values.flags, realCfg.flags, 'StdlibShared')
				mergeflag(usageKB.values.flags, realCfg.flags, 'StdlibStatic')
			
				-- Resolve the links in to linkAsStatic, linkAsShared
				if realCfg.kind == 'SharedLib' then
					-- If you link to a shared library, you also need to link to any shared libraries that it uses
					oven.mergefield(usageKB.values, "linkAsShared", realCfg.linkAsShared )
				elseif realCfg.kind == 'StaticLib' then
					-- If you link to a static library, you also need to link to any libraries that it uses
					oven.mergefield(usageKB.values, "linkAsStatic", realCfg.linkAsStatic )
					oven.mergefield(usageKB.values, "linkAsShared", realCfg.linkAsShared )
				end
						
			end
		end -- realProj

	end
	
	-- May recurse
	function globalContainer.applyUsageRequirements(prj)
	
		if prj.isUsage or prj.hasBakedUsage then
			return true
		end
		prj.hasBakedUsage = true
		
		-- Bake the project's configs if we haven't already
		project.bake(prj)
	
		-- Resolve "uses" for each config, and apply
		for cfg in project.eachconfig(prj) do

			for _,useProjName in ipairs(cfg.uses or {}) do
				local useProj = project.getUsageProject( useProjName )
				local cfgFilterTerms = getValues(cfg.usekeywords)
				
				if not useProj then
					-- can't find the project, perhaps we've specified configuration filters also
					local parts = useProjName:split('.|')
					useProj = project.getUsageProject( parts[1] )
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
				--  .getfield may recurse in to globalContainer.bakeUsageProject if the usage project has unbaked "uses"
				keyedblocks.getfield(useProj, cfgFilterTerms, nil, cfg)
			end -- each use
			
			-- Move any links in to linkAsStatic or linkAsShared
			if cfg.links then
				if cfg.kind == premake.STATICLIB then
					oven.mergefield(cfg, 'linkAsStatic', cfg.links)
				else
					oven.mergefield(cfg, 'linkAsShared', cfg.links)
				end
				cfg.links = nil
			end
		end  -- each cfg			
		
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
		
		for _,prj in ipairs(allProjects) do
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

