--
-- solution.lua
-- Work with the list of solutions loaded from the script.
-- Copyright (c) 2002-2012 Jason Perkins and the Premake project
--

	premake.solution = { }
	local solution = premake.solution
	local oven = premake5.oven
	local project = premake5.project


-- The list of defined solutions (which contain projects, etc.)

	premake.solution.list = { }


--
-- Create a new solution and add it to the session.
--
-- @param name
--    The new solution's name.
--

	function solution.new(name)
		local sln = { }

		-- add to master list keyed by both name and index
		if name == '_GLOBAL_SOLUTION' then
			ptypeSet( sln, "globalcontainer" )
		else
			table.insert(premake.solution.list, sln)
			premake.solution.list[name] = sln
			ptypeSet( sln, "solution" )
		end
			
		sln.name           = name
		sln.basedir        = os.getcwd()			
		sln.projects       = { }

		-- merge in global configuration
		local global = premake.globalContainer 
		if global then
			sln.configurations 	= oven.merge({}, global.configurations)
			sln.blocks 			= oven.merge({}, global.blocks)
			sln.platforms		= oven.merge({}, global.platforms or {})
			sln.language		= global.language
		else
			sln.configurations = { }
			sln.blocks         = { }
		end
		
		return sln
	end



--
-- Iterates through all of the current solutions, bakes down their contents,
-- and then replaces the original solution object with this baked result.
-- This is the entry point to the whole baking process, which happens after
-- the scripts have run, but before the project files are generated.
--

	function solution.bakeall()
		local result = {}
		for i, sln in ipairs(solution.list) do
			result[i] = solution.bake(sln)
			result[sln.name] = result[i]
		end
		solution.list = result
	end


--
-- Prepare the contents of a solution for the next stage. Flattens out
-- all configurations, computes composite values (i.e. build targets,
-- objects directories), and expands tokens.
-- @return
--    The baked version of the solution.
--

	function solution.bake(sln)
		-- start by copying all field values into the baked result
		local result = oven.merge({}, sln)
		result.baked = true
		local slnNoBlocks = oven.merge({}, sln)
		slnNoBlocks.baked = true
		
		-- keep a reference to the original configuration blocks, in
		-- case additional filtering (i.e. for files) is needed later
		result.blocks = sln.blocks
		
		-- bake all of the projects in the list, and store that result
		local projects = {}
		for i, prj in ipairs(sln.projects) do
			local bakedPrj = project.bake(prj, iif(prj.isUsage, slnNoBlocks, result))
			local prjName = prj.name
			projects[i] = bakedPrj

			if (not projects[prjName]) then
				projects[prjName] = bakedPrj
			elseif bakedPrj.isUsage then
				projects[prjName].usageProj = bakedPrj
				bakedPrj.realProj = projects[prjName]
			elseif projects[prjName].isUsage then
				bakedPrj.usageProj = projects[prjName]
				bakedPrj.usageProj.realbakedPrj = bakedPrj
				projects[prjName] = bakedPrj
			else
				error('Duplicate project ' .. prjName)
			end
		end
		result.projects = projects
		
		-- assign unique object directories to every project configurations
 		solution.bakeobjdirs(result)
 		
 		-- Apply usage requirements
 		solution.bakeUsageRequirements(result.projects)
		
		-- expand all tokens contained by the solution
		for prj in solution.eachproject_ng(result) do
			oven.expandtokens(prj, "project")
			for cfg in project.eachconfig(prj) do
				oven.expandtokens(cfg, "config")
			end
		end
		oven.expandtokens(result, "project")

		-- build a master list of solution-level configuration/platform pairs
		result.configs = solution.bakeconfigs(result)
		
		return result
	end

--
-- Create a list of solution-level build configuration/platform pairs.
--

	function solution.bakeconfigs(sln)
		local buildcfgs = sln.configurations or {}
		local platforms = sln.platforms or {}
		
		local configs = {}
		for _, buildcfg in ipairs(buildcfgs) do
			if #platforms > 0 then
				for _, platform in ipairs(platforms) do
					table.insert(configs, { ["buildcfg"] = buildcfg, ["platform"] = platform })
				end
			else
				table.insert(configs, { ["buildcfg"] = buildcfg })
			end
		end

		-- fill in any calculated values
		for _, cfg in ipairs(configs) do
			premake5.config.bake(cfg)
			ptypeSet( cfg, 'configsln' )
		end
		
		return configs
	end

uid = 1
--
-- Read the "uses" field and bake in any requirements from those projects
--
	function solution.bakeUsageRequirements(projects)
		
		local prjHasBakedUsageDefaults = {}
		
		-- Look recursively at the uses statements in each project and add usage project defaults for them  
		function bakeUsageDefaults(prj)
			if prjHasBakedUsageDefaults[prj] then
				return true
			end
			prjHasBakedUsageDefaults[prj] = true
			
			-- For usage project, first ensure that the real project's usages are baked, and then copy in any defaults
			if prj.isUsage and prj.realProj then
				local realProj = prj.realProj
				local usageProj = prj
			
				-- Bake the real project first
				bakeUsageDefaults(realProj)
			
				-- Copy in default build target from the real proj
				for cfgName,useCfg in pairs(usageProj.configs) do
					local realCfg = realProj.configs[cfgName]
				
					-- usage kind = real proj kind
					useCfg.kind = useCfg.kind or realCfg.kind

					local realTarget = realCfg.buildtarget.abspath
					if realTarget then
						if realCfg.kind == 'SharedLib' then
							-- link to the target as a shared library
							oven.mergefield(useCfg, "linkAsShared", { realTarget })
						elseif realCfg.kind == 'StaticLib' then
							-- link to the target as a static library
							oven.mergefield(useCfg, "linkAsStatic", { realTarget })
						end
					end
				
					-- Finally, resolve the links in to linkAsStatic, linkAsShared
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
				
			-- Resolve "uses" & "links" for each config
			for cfg in project.eachconfig(prj) do
				local uses = concat(cfg.uses or {}, cfg.links or {})
				for _,useProjName in ipairs(uses) do
					local p = projects[useProjName] or premake.globalContainer.projects[useProjName]
					local useProj = iif( p.isUsage, p, p.usageProj )
					local realProj = iif( p.isUsage, p.realProj, p )
					local useCfg
									
					-- Check the string also specifies a configuration
					if not useProj then
						local useProjName2,useBuildCfg, usePlatform = string.match(useProjName,'([^.]+)[.]+(.*)')
						useProj = projects[useProjName2] or premake.globalContainer.projects[useProjName2]
						if not useProj then
							error('Could not find project '.. useProjName)
						end								
						useCfg = project.getconfig(useProj, useBuildCfg, usePlatform)
						if useCfg == nil then
							error('Could not find usage '.. useProjName)
						end
					else
						useCfg = project.getconfig(useProj, cfg.buildcfg, cfg.platform)
					end
				
					if useProj and useCfg then 
						-- make sure the usage project also has its defaults baked
						bakeUsageDefaults(useProj)
					
						-- Separate links in to linkAsStatic, linkAsShared
						cfg.linkAsStatic = cfg.linkAsStatic or {}
						cfg.linkAsShared = cfg.linkAsShared or {}
											
						-- Merge in the usage requirements from the usage project
						local usageFields = Seq:new(premake.fields):where(function(v) return v.usagefield; end)
						local usageRequirements = {}
						for _,filterField in usageFields:each() do
							oven.merge(cfg, useCfg, filterField.name)
						end						
					
					else
						-- Can't find the usage project, assume the string is a file
						local linkName = useProjName
						if string.find(linkName, '.so',1,true) then
							table.insert( cfg.linkAsShared, linkName )
						else
							table.insert( cfg.linkAsStatic, linkName )
						end				
					end -- if valid useProj
							
				end -- each use
			end  -- each cfg
			
		end -- function bakeUsageDefaults
		
		-- bake each project
		for _,prj in ipairs(projects) do
			bakeUsageDefaults(prj)
		end

	end

--
-- Assigns a unique objects directory to every configuration of every project
-- in the solution, taking any objdir settings into account, to ensure builds
-- from different configurations won't step on each others' object files. 
-- The path is built from these choices, in order:
--
--   [1] -> the objects directory as set in the config
--   [2] -> [1] + the platform name
--   [3] -> [2] + the build configuration name
--   [4] -> [3] + the project name
--

	function solution.bakeobjdirs(sln)
		-- function to compute the four options for a specific configuration
		local function getobjdirs(cfg)
			local dirs = {}
			
			local dir = path.getabsolute(path.join(project.getlocation(cfg.project), cfg.objdir or "obj"))
			table.insert(dirs, dir)
			
			if cfg.platform then
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
		
		for prj in premake.solution.eachproject_ng(sln) do
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


--
-- Iterate over the collection of solutions in a session.
--
-- @returns
--    An iterator function.
--

	function solution.each()
		local i = 0
		return function ()
			i = i + 1
			if i <= #premake.solution.list then
				return premake.solution.list[i]
			end
		end
	end


--
-- Iterate over the configurations of a solution.
--
-- @param sln
--    The solution to query.
-- @return
--    A configuration iteration function.
--

	function solution.eachconfig(sln)
		-- to make testing a little easier, allow this function to
		-- accept an unbaked solution, and fix it on the fly
		if not sln.baked then
			sln = solution.bake(sln)
		end

		local i = 0
		return function()
			i = i + 1
			if i > #sln.configs
			 then
				return nil
			else
				return sln.configs[i]
			end
		end
	end
	
	function solution.getConfigs(sln)
		-- to make testing a little easier, allow this function to
		-- accept an unbaked solution, and fix it on the fly
		if not sln.baked then
			sln = solution.bake(sln)
		end

		return Seq:new(sln.configs)	
	end


--
-- Iterate over the projects of a solution.
--
-- @param sln
--    The solution.
-- @returns
--    An iterator function.
--

	function solution.eachproject(sln)
		local i = 0
		return function ()
			i = i + 1
			if i <= #sln.projects then
				return premake.solution.getproject(sln, i)
			end
		end
	end


--
-- Iterate over the projects of a solution (next-gen).
--
-- @param sln
--    The solution.
-- @return
--    An iterator function, returning project configurations.
--

	function solution.eachproject_ng(sln)
		local i = 0
		return function ()
			i = i + 1
			if i <= #sln.projects then
				return premake.solution.getproject_ng(sln, i)
			end
		end
	end


--
-- Locate a project by name, case insensitive.
--
-- @param sln
--    The solution to query.
-- @param name
--    The name of the projec to find.
-- @return
--    The project object, or nil if a matching project could not be found.
--

	function solution.findproject(sln, name)
		name = name:lower()
		for _, prj in ipairs(sln.projects) do
			if name == prj.name:lower() then
				return prj
			end
		end
		for _, prj in ipairs(premake.globalContainer.projects) do
			if name == prj.name:lower() then
				return prj
			end
		end
		return nil
	end

--
--  Find a usage configuration
--
	function solution.findusage(sln, useProjName)
		name = name:lower()
		for _, prj in ipairs(sln.projects) do
			if useProjName == prj.name:lower() then
				return iif( prj.usageProj, prj.usageProj, prj )
			end
		end
		for _, prj in ipairs(premake.globalContainer.projects) do
			if useProjName == prj.name:lower() then
				return iif( prj.usageProj, prj.usageProj, prj )
			end
		end
		return nil
	end


--
-- Retrieve a solution by name or index.
--
-- @param key
--    The solution key, either a string name or integer index.
-- @returns
--    The solution with the provided key.
--

	function solution.get(key)
		return premake.solution.list[key]
	end


--
-- Retrieve the solution's file system location.
--
-- @param sln
--    The solution object to query.
-- @return
--    The path to the solutions's file system location.
--

	function solution.getlocation(sln)
		return sln.location or sln.basedir
	end


--
-- Retrieve the project at a particular index.
--
-- @param sln
--    The solution.
-- @param idx
--    An index into the array of projects.
-- @returns
--    The project at the given index.
--

	function solution.getproject(sln, idx)
		-- retrieve the root configuration of the project, with all of
		-- the global (not configuration specific) settings collapsed
		local prj = sln.projects[idx]
		local cfg = premake.getconfig(prj)
		
		-- root configuration doesn't have a name; use the project's
		cfg.name = prj.name
		return cfg
	end


--
-- Retrieve the project configuration at a particular index.
--
-- @param sln
--    The solution.
-- @param idx
--    An index into the array of projects.
-- @return
--    The project configuration at the given index.
--

	function solution.getproject_ng(sln, idx)
		-- to make testing a little easier, allow this function to
		-- accept an unbaked solution, and fix it on the fly
		if not sln.baked then
			sln = solution.bake(sln)
		end
		return sln.projects[idx]
	end
