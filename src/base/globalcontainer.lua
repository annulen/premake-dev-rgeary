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
	
		-- Bake all real projects
		local result = {}
		for i,prj in ipairs(globalContainer.allReal) do
			local bakedPrj = project.bake(prj)
			result[i] = bakedPrj
			result[bakedPrj.name] = bakedPrj
		end
		globalContainer.allReal = result
		
		-- Bake all usage projects
		result = {}
		for i,prj in ipairs(globalContainer.allUsage) do
			local bakedPrj = keyedblocks.bake(prj)
			result[i] = bakedPrj
			result[bakedPrj.name] = bakedPrj
		end
		globalContainer.allUsage = result
		
		-- Assign unique object directories to every project configurations
		globalContainer.bakeobjdirs(globalContainer.allReal)
		
 		-- Apply usage requirements
 		globalContainer.bakeUsageRequirements(globalContainer.allReal)
		
		-- expand all tokens (must come after baking objdirs)
		for i,prj in Seq:ipairs(globalContainer.allReal):iconcat(globalContainer.allUsage):each() do
			oven.expandtokens(prj, "project")
			for cfg in project.eachconfig(prj) do
				oven.expandtokens(cfg, "config")
			end
		end
		
		-- Bake all solutions
		solution.bakeall()
	end

--
-- Read the "uses" field and bake in any requirements from those projects
--
	function globalContainer.bakeUsageRequirements(projects)
		
		local prjHasBakedUsageDefaults = {}
		
		-- Look recursively at the uses statements in each project and add usage project defaults for them  
		function bakeUsageDefaults(prj)
			if prjHasBakedUsageDefaults[prj] then
				return true
			end
			prjHasBakedUsageDefaults[prj] = true
			
			-- For usage project, first ensure that the real project's usages are baked, and then copy in any defaults
			local realProj = project.getRealProject(prj.name)
			if prj.isUsage and realProj then
				local usageProj = prj
			
				-- Bake the real project first
				bakeUsageDefaults(realProj)
			
				-- Set up the usage target defaults
				for cfgName,useCfg in pairs(realProj.configs) do
					local realCfg = realProj.configs[cfgName]
				
					-- usage kind = real proj kind
					useCfg.kind = useCfg.kind or realCfg.kind

					-- Copy in default build target from the real proj
					if realCfg.buildtarget and realCfg.buildtarget.abspath then
						local realTarget = realCfg.buildtarget.abspath
						if realCfg.kind == 'SharedLib' then
							-- link to the target as a shared library
							oven.mergefield(useCfg, "linkAsShared", { realTarget })
						elseif realCfg.kind == 'StaticLib' then
							-- link to the target as a static library
							oven.mergefield(useCfg, "linkAsStatic", { realTarget })
						end
					end
					
					-- Copy across some flags
					local function mergeflag(destFlags, srcFlags, flagName)
						if srcFlags and srcFlags[flagName] and (not destFlags[flagName]) then
							destFlags[flagName] = flagName
							table.insert(destFlags, flagName)
						end
					end
					mergeflag(useCfg.flags, realCfg.flags, 'ThreadingMulti')
					mergeflag(useCfg.flags, realCfg.flags, 'StdlibShared')
					mergeflag(useCfg.flags, realCfg.flags, 'StdlibStatic')
				
					-- Resolve the links in to linkAsStatic, linkAsShared
					if useCfg.kind == 'SharedLib' then
						-- If you link to a shared library, you also need to link to any shared libraries that it uses
						oven.mergefield(useCfg, "linkAsShared", realCfg.linkAsShared )
					elseif realCfg.kind == 'StaticLib' then
						-- If you link to a static library, you also need to link to any libraries that it uses
						oven.mergefield(useCfg, "linkAsStatic", realCfg.linkAsStatic )
						oven.mergefield(useCfg, "linkAsShared", realCfg.linkAsShared )
					end					
				end
			end -- isUsage
				
			-- Resolve "uses" for each config
			for cfg in project.eachconfig(prj) do
				--local uses = concat(cfg.uses or {}, cfg.links or {})
				for _,useProjName in ipairs(cfg.uses or {}) do
					local useProj = project.getUsageProject( useProjName )
					if not useProj then
						error("Could not find project/usage "..useProjName..' in project '..prj.name)
					end
					local useCfg
									
					-- Check the string also specifies a configuration
					if not useProj then
						local useProjName2,useBuildCfg, usePlatform = string.match(useProjName,'([^.]+)[.]+(.*)')
						useProj = project.getUsageProject(useProjName2)
						if not useProj then
							error('Could not find project '.. useProjName)
						end								
						useCfg = project.getconfig(useProj, useBuildCfg, usePlatform)
						if useCfg == nil then
							error('Could not find usage '.. useProjName)
						end
					else
						useCfg = project.getconfig(useProj, cfg.buildcfg, cfg.platform)
						
						-- try without platform, then without config
						if not useCfg then
							useCfg = project.getconfig(useProj, cfg.buildcfg, '')
						end
						if not useCfg then
							useCfg = project.getconfig(useProj, '*', '')
						end
					end
				
					cfg.linkAsStatic = cfg.linkAsStatic or {}
					cfg.linkAsShared = cfg.linkAsShared or {}
					
					if useProj and useCfg then 
						-- make sure the usage project also has its defaults baked
						bakeUsageDefaults(useProj)
					
						-- Merge in the usage requirements from the usage project
						local usageFields = Seq:new(premake.fields):where(function(v) return v.usagefield; end)
						local usageRequirements = {}
	
						for _,filterField in usageFields:each() do
							oven.merge(cfg, useCfg, filterField.name)
						end
					
					else
						print("Error : Can't find usage project "..useProjName..' for configuration '..cfg.buildcfg..'.'..cfg.platform)
						-- Can't find the usage project, assume the string is a file
--						local linkName = useProjName
--						if string.find(linkName, '.so',1,true) then
--							table.insert( cfg.linkAsShared, linkName )
--						else
--							table.insert( cfg.linkAsStatic, linkName )
--						end				
					end -- if valid useProj
							
				end -- each use
			end  -- each cfg
			
		end -- function bakeUsageDefaults
		
		-- bake each project
		local tmr = timer.start('Bake usage requirements')
		for i,prj in ipairs(projects) do
			bakeUsageDefaults(prj)
		end
		timer.stop(tmr)

	end


--
-- Assigns a unique objects directory to every configuration of every project
-- taking any objdir settings into account, to ensure builds
-- from different configurations won't step on each others' object files. 
-- The path is built from these choices, in order:
--
--   [1] -> the objects directory as set in the config
--   [2] -> [1] + the platform name
--   [3] -> [2] + the build configuration name
--   [4] -> [3] + the project name
--

	function globalContainer.bakeobjdirs(allProjects)
		-- function to compute the four options for a specific configuration
		local function getobjdirs(cfg)
			local dirs = {}
			
			local dir = path.getabsolute(path.join(project.getlocation(cfg.project), cfg.objdir or "obj"))
			table.insert(dirs, dir)
			
			if cfg.platform and cfg.platform ~= '' then
				dir = path.join(dir, cfg.platform)
				table.insert(dirs, dir)
			end
			
			dir = path.join(dir, cfg.buildcfg)
			table.insert(dirs, dir)

			dir = path.join(dir, cfg.project.name)
			table.insert(dirs, dir)
			
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

