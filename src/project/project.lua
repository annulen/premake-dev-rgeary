--
-- src/project/project.lua
-- Premake project object API
-- Copyright (c) 2011-2012 Jason Perkins and the Premake project
--

	local project = premake5.project
	local oven = premake5.oven
	local targets = premake5.targets
	local keyedblocks = premake.keyedblocks
	local config = premake5.config
		
--
-- Flatten out a project and all of its configurations, merging all of the
-- values contained in the script-supplied configuration blocks.
--   project.bake must be recursive, as if A depends on B, we need to bake B first. 

	function project.bake(prj)
		-- make sure I've got the actual project, and not the root configurations
		prj = prj.project or prj
		local sln = prj.solution
		
		keyedblocks.create(prj, sln)
		
		if prj.isbaked then
			return prj
		end
		local tmr = timer.start('project.bake')
		
		-- bake the project's "root" configuration, which are all of the
		-- values that aren't part of a more specific configuration
		prj.solution = sln
		prj.platforms = prj.platforms or {}
		prj.isbaked = true
		
		-- prevent any default system setting from influencing configurations
		prj.system = nil
		
		-- apply any mappings to the project's configuration set
		prj.buildFeaturesList = {}

		local cfglist = project.bakeconfigmap(prj)
		for _,cfgpair in ipairs(cfglist) do
			local buildFeatures = {
				buildcfg = cfgpair[1],
				platform = cfgpair[2],				
			}
			project.addconfig(prj, buildFeatures)
		end
				
		timer.stop(tmr)
		return prj
	end
	
--
-- Add a baked configuration to the project.
--  buildFeatures is a keyed table of keywords (buildcfg, platform, <featureName> = <featureName>) 
--   describing the config
-- 
	local inProgress = {}
	function project.addconfig(prj, buildFeatures)
		if not prj or ptype(prj) == 'solution' then return end
		if prj.isUsage then
			prj = project.getRealProject(prj.name, prj.namespaces)
		end		
		if not prj then return end
		
		if not prj.isbaked then
			project.bake(prj)
		end
		
		prj.configs = prj.configs or {}
		prj.buildFeaturesList = prj.buildFeaturesList or {}
		
		local cfgName = config.getBuildName(buildFeatures)
		if prj.configs[cfgName] then
			return prj.configs[cfgName]
		end
		
if inProgress[prj] then
	error("Recursive dependency with "..prj.name.." : "..table.concat(inProgress, (' ')))
end 
inProgress[prj] = prj
table.insert(inProgress, prj.name)
		
		-- Add null configuration to avoid re-adding if there is a circular dependency
		prj.configs[cfgName] = {}
		
		local cfg = project.bakeconfig(prj, buildFeatures)
				
		-- make sure this config is supported by the action; skip if not
		if cfg and premake.action.supportsconfig(cfg) then
			prj.configs[cfgName] = cfg
		end
		
		table.insert( prj.buildFeaturesList, buildFeatures )
		
		-- Add usage requirements for the new configuration
		local uProj = project.getUsageProject(prj.name)
		config.addUsageConfig(prj, uProj, buildFeatures)
		
inProgress[prj] = nil
table.remove(inProgress, table.indexof(inProgress, prj.name))
		return cfg
	end
	
--
-- Flattens out the build settings for a particular build configuration and
-- platform pairing, and returns the result.
--

	function project.bakeconfig(prj, buildFeatures)
		local system
		local architecture
local tmr1 = timer.start('bakeconfig1')
		local buildcfg = buildFeatures.buildcfg
		local platform = buildFeatures.platform

		-- for backward compatibility with the old platforms API, use platform
		-- as the default system or architecture if it would be a valid value.
		if platform then
			system = premake.api.checkvalue(platform, premake.fields.system.allowed)
			architecture = premake.api.checkvalue(platform, premake.fields.architecture.allowed)
		end
		if architecture == nil and os.is64bit() then
			architecture = 'x86_64'
		end

		-- figure out the target operating environment for this configuration
		local filter, cfg
		
		system = system or premake.action.current().os or os.get()
		filter = { 
			buildcfg = buildcfg,
			action = _ACTION, 
			system = system, 
			architecture = architecture,
		}
		
		-- Insert platform & features in to filter
		for k,v in pairs(buildFeatures) do
			filter[k] = v
		end		
		
		cfg = keyedblocks.getfield(prj, filter)
		cfg.system = cfg.system or system
	
		cfg.buildcfg = buildcfg
		cfg.platform = platform
		cfg.buildFeatures = table.shallowcopy(buildFeatures)
		cfg.action = _ACTION
		cfg.solution = prj.solution
		cfg.project = prj
		cfg.system = cfg.system
		cfg.architecture = cfg.architecture or architecture
		cfg.isUsage = prj.isUsage
		cfg.platform = cfg.platform or ''		-- should supply '' as you could ask for %{cfg.platform} in a token
		cfg.flags = cfg.flags or {}
				
		-- Move any links in to linkAsStatic or linkAsShared
		if cfg.links then
			for _,linkName in ipairs(cfg.links) do
				local linkPrj = project.getRealProject(linkName)
				local linkKind 
				
				if linkPrj then 
					linkKind = linkPrj.kind
				else 
					-- must be a system lib
					linkKind = cfg.kind
				end
				
				if linkKind == premake.STATICLIB then
					oven.mergefield(cfg, 'linkAsStatic', linkName)
				else
					oven.mergefield(cfg, 'linkAsShared', linkName)
				end
			end
			cfg.links = nil
		end
		
		-- Remove any libraries in linkAsStatic that have also been defined in linkAsShared
		oven.removefromfield(cfg.linkAsStatic, cfg.linkAsShared) 
					
		ptypeSet( cfg, 'configprj' )
timer.stop(tmr1)
local tmr3 = timer.start('bakeconfig3')
		-- fill in any calculated values
		config.bake(cfg)
timer.stop(tmr3)
		return cfg
	end

--
-- Builds a list of build configuration/platform pairs for a project,
-- along with a mapping between the solution and project configurations.
-- @param prj
--    The project to query.
-- @return
--    Two values: 
--      - an array of the project's build configuration/platform
--        pairs, based on the result of the mapping
--      - a key-value table that maps solution build configuration/
--        platform pairs to project configurations.
--

	function project.bakeconfigmap(prj)
		-- Apply any mapping tables to the project's initial configuration set,
		-- which includes configurations inherited from the solution. These rules
		-- may cause configurations to be added ore removed from the project.
		local sln = prj.solution
		local configs = table.fold(sln.configurations or {}, sln.platforms or {})
		for i, cfg in ipairs(configs) do
			configs[i] = project.mapconfig(prj, cfg[1], cfg[2])
		end
		
		-- walk through the result and remove duplicates
		local buildcfgs = {}
		local platforms = {}
		
		for _, pairing in ipairs(configs) do
			local buildcfg = pairing[1]
			local platform = pairing[2]
			
			if not table.contains(buildcfgs, buildcfg) then
				table.insert(buildcfgs, buildcfg)
			end
			
			if platform and not table.contains(platforms, platform) then
				table.insert(platforms, platform)
			end
		end

		-- merge these canonical lists back into pairs for the final result
		configs = table.fold(buildcfgs, platforms)	
		return configs
	end


--
-- Returns an iterator function for the configuration objects contained by
-- the project. Each configuration corresponds to a build configuration/
-- platform pair (i.e. "Debug|x32") as specified in the solution.
--
-- @param prj
--    The project object to query.
-- @return
--    An iterator function returning configuration objects.
--

	function project.eachconfig(prj)
		-- to make testing a little easier, allow this function to
		-- accept an unbaked project, and fix it on the fly
		if not prj.isbaked then
			error('Project "'..prj.name..'" is not baked')
			--prj = project.bake(prj)
		end

		local buildFeaturesList = prj.buildFeaturesList
		local count = #buildFeaturesList
		
		local i = 0
		return function ()
			i = i + 1
			if i <= count then
				return project.getconfig2(prj, buildFeaturesList[i])
			end
		end
	end

	function project.getConfigs(prj)
		return Seq:new(project.eachconfig(prj))
	end
-- 
-- Locate a project by name; case insensitive.
--
-- @param name
--    The name of the project for which to search.
-- @return
--    The corresponding project, or nil if no matching project could be found.
--

	local function getProject(allProjects, name, namespaces)
		local prj = allProjects[name]

		-- check aliases		
		if not prj then
			local tryName = name
			local i = 0
			while targets.aliases[tryName] do
				tryName = targets.aliases[tryName]
				i = i + 1
				if i > 100 then
					error("Recursive project alias : "..tryName)
				end
			end
		
			prj = allProjects[tryName]
		end
	
		-- check supplied implicit namespaces
		if not prj and namespaces then
			local possibles = {}
			for _,namespace in ipairs(namespaces) do
				-- Try prepending the namespace
				local tryName = namespace..name
				local i = 0
				while targets.aliases[tryName] do
					tryName = targets.aliases[tryName]
					i = i + 1
					if i > 100 then
						error("Recursive project alias : "..tryName)
					end
				end
				prj = allProjects[tryName]
				if prj then possibles[prj.fullname] = prj end
			end
			if table.size(possibles) > 1 then
				error("Ambiguous project name \""..name.."\", do you mean "..table.concat(getKeys(possibles), ', ')..'?')
			else
				local k,v = next(possibles)
				prj = v
			end
			
		end
		
		return prj
	end

-- Get a real project. Namespaces is an optional list of prefixes to try to prepend to "name"
	function project.getRealProject(name, namespaces)
		return getProject(targets.allReal, name, namespaces)
	end
	
-- Get a usage project. Namespaces is an optional list of prefixes to try to prepend to "name"
	function project.getUsageProject(name, namespaces)
		return getProject(targets.allUsage, name, namespaces)
	end

-- If a project isn't found, this returns some alternatives
	function project.getProjectNameSuggestions(name, namespaces)
		local suggestions = {}
		local suggestionStr
		
		-- Find hints
		local namespaces,shortname,fullname = project.getNameParts(name, namespaces)

		-- Check for wrong namespace
		for prjName,prj in Seq:new(targets.aliases):concat(targets.allUsage):each() do
			if prj.shortname == shortname then
				table.insert(suggestions, prj.name)
			end
		end
		local usage = project.getUsageProject(name, namespaces)
		if #suggestions == 0 then
			-- check for misspellings
			local allUsageNames = Seq:new(targets.aliases):concat(targets.allUsage):getKeys():toTable()
			local spell = premake.spelling.new(allUsageNames)

			suggestions = spell:getSuggestions(name)
			if #suggestions == 0 then
				suggestions = spell:getSuggestions(fullname)
			end
		end

		if #suggestions > 0 then
			suggestionStr = Seq:new(suggestions):take(20):mkstring(', ')
			if #suggestions > 20 then
				suggestionStr = suggestionStr .. '...'
			end
			suggestionStr = ' Did you mean ' .. suggestionStr .. '?'
		end

		return suggestions, suggestionStr
	end
	
-- Iterate over all real projects
	function project.eachproject()
		local iter,t,k,v = ipairs(targets.allReal)
		return function()
			k,v = iter(t,k)
			return v
		end
	end
	
	-- helper function
	function project.getNameParts(name, prefix)
		local namespaces = {}
		
		if prefix then
			if type(prefix) == 'table' then
				for _,p in ipairs(prefix) do
					table.insert(namespaces, p)
				end
				prefix = namespaces[#namespaces]
			end
			
			if not prefix:endswith('/') then
				error("projectprefix must end with /")
			end 
			
			-- special case, avoids a/b/b when you mean just a/b
			if name:startswith(prefix) then
				prefix = nil
			else
				name = prefix .. name
			end
		end		
		
		-- get the namespace from the name if it contains one
		local prevNS = ''
		for n in name:gmatch("[^/]+/") do
			n = prevNS .. n
			table.insert(namespaces, n)
			prevNS = n
		end
		local fullNamespace = namespaces[#namespaces] or '' 
		
		local shortname = name:replace(fullNamespace, '')
		local fullname = fullNamespace .. shortname
		return namespaces,shortname,fullname
	end
		
-- Create a project
	function project.createproject(name, sln, isUsage)
	
		-- Project full name is MySolution/MyProject, shortname is MyProject
		local namespaces,shortname,fullname = project.getNameParts(name, sln.projectprefix)
				
		-- Now we have the fullname, check if this is already a project
		if isUsage then
			-- If it's not an existing project, assume name is the fullname & don't prepend the solution prefix
			if not targets.allReal[fullname] then
				fullname = name
			end
		
			local existing = targets.allUsage[fullname]
			if existing then return existing end
			
		else
			local existing = targets.allReal[fullname]
			if existing then return existing end
		end
					
		local prj = {}
		
		-- attach a type
		ptypeSet(prj, 'project')
		
		-- add to global list keyed by name
		if isUsage then
			targets.allUsage[fullname] = prj
		else
			targets.allReal[fullname] = prj
		end
		
		-- add to solution list keyed by both name and index
		if not sln.projects[name] then
			table.insert(sln.projects, prj)
			sln.projects[name] = prj
		end
		
		prj.solution       = sln
		prj.namespaces     = namespaces
		prj.name           = fullname
		prj.fullname       = fullname
		prj.shortname      = shortname
		prj.basedir        = os.getcwd()
		prj.script         = _SCRIPT
		prj.uuid           = os.uuid()
		prj.blocks         = { }
		prj.isUsage		   = isUsage;
		
		if isUsage then
			prj.getRealProject = function(self) 
				local realProj = project.getRealProject(self.name, self.namespaces)
				self.getRealProject = function(s) return realProj end
				return realProj 
			end
			prj.getUsageProject = function(self) return self end
		else
			prj.getRealProject = function(self) return self end 
			prj.getUsageProject = function(self) 
				local uProj = project.getUsageProject(self.name, self.namespaces)
				self.getUsageProject = function(s) return uProj end
				return uProj 
			end
		end
		
		-- Create a default usage project if there isn't one
		if (not isUsage) and (not project.getUsageProject(prj.name, namespaces)) then
			if not name:startswith(sln.projectprefix) then
				name = sln.projectprefix..name
			end
			project.createproject(name, sln, true)
		end
		
		return prj;
	end
	

--
-- Retrieve the project's configuration information for a particular build 
-- configuration/platform pair.
--
-- @param prj
--    The project object to query.
-- @param buildcfg
--    The name of the build configuration on which to filter.
-- @param platform
--    Optional; the name of the platform on which to filter.
-- @return
--    A configuration object.
--
	
	function project.getconfig(prj, buildcfg, platform)
		if type(buildcfg) == 'table' then
			-- alias
			local buildFeatures = buildcfg
			return project.getconfig2(prj, buildFeatures)
		end
		return project.getconfig(prj, { buildcfg = buildcfg, platform = platform })
	end
	
	function project.getconfig2(prj, buildFeatures)
		-- to make testing a little easier, allow this function to
		-- accept an unbaked project, and fix it on the fly
		if not prj.isbaked then
			prj = project.bake(prj)
		end
	
		-- if no build configuration is specified, return the "root" project
		-- configurations, which includes all configuration values that
		-- weren't set with a specific configuration filter
		if not buildFeatures.buildcfg then
			return prj
		end
		
		-- apply any configuration mappings. TODO : Improve to support features
		local pairing = project.mapconfig(prj, buildFeatures.buildcfg, buildFeatures.platform)
		buildFeatures.buildcfg = pairing[1]
		buildFeatures.platform = pairing[2]

		-- look up and return the associated config		
		--local key = (buildcfg or "*") .. (platform or "")
		local key = config.getBuildName(buildFeatures)
		return prj.configs[key]
	end


--
-- Returns a list of sibling projects on which the specified project depends. 
-- This is used to list dependencies within a solution or workspace. Must 
-- consider all configurations because Visual Studio does not support per-config
-- project dependencies.
--
-- @param prj
--    The project to query.
-- @return
--    A list of dependent projects, as an array of project objects.
--

	function project.getdependencies(prj)
		local result = {}

		for cfg in project.eachconfig(prj) do
			for _, link in ipairs(cfg.links or {}) do
				local dep = premake.solution.findproject(cfg.solution, link)
				if dep and not table.contains(result, dep) then
					table.insert(result, dep)
				end
			end
		end

		return result
	end


--
-- Builds a file configuration for a specific file from a project.
--
-- @param prj
--    The project to query.
-- @param filename
--    The absolute path of the file to query.
-- @return
--    A corresponding file configuration object.
--

	function project.getfileconfig(prj, filename)
		local fcfg = {}

		fcfg.abspath = filename
		fcfg.relpath = project.getrelative(prj, filename)

		local vpath = project.getvpath(prj, filename)
		if vpath ~= filename then
			fcfg.vpath = vpath
		else
			fcfg.vpath = fcfg.relpath
		end

		fcfg.name = path.getname(filename)
		fcfg.basename = path.getbasename(filename)
		fcfg.path = fcfg.relpath
		
		return fcfg
	end


--
-- Returns a unique object file name for a project source code file.
--
-- @param prj
--    The project object to query.
-- @param filename
--    The name of the file being compiled to the object file.
--

	function project.getfileobject(prj, filename)
		-- make sure I have the project, and not it's root configuration
		prj = prj.project or prj
		
		-- create a list of objects if necessary
		prj.fileobjects = prj.fileobjects or {}

		-- look for the corresponding object file		
		local basename = path.getbasename(filename)
		local uniqued = basename
		local i = 0
		
		while prj.fileobjects[uniqued] do
			-- found a match?
			if prj.fileobjects[uniqued] == filename then
				return uniqued
			end
			
			-- check a different name
			i = i + 1
			uniqued = basename .. i
		end
		
		-- no match, create a new one
		prj.fileobjects[uniqued] = filename
		return uniqued
	end


--
-- Retrieve the project's file name.
--
-- @param prj
--    The project object to query.
-- @return
--    The project's file name. This will usually match the project's
--    name, or the external name for externally created projects.
--

	function project.getfilename(prj)
		return prj.externalname or prj.name
	end


--
-- Return the first configuration of a project, which is used in some
-- actions to generate project-wide defaults.
--
-- @param prj
--    The project object to query.
-- @return
--    The first configuration in a project, as would be returned by
--    eachconfig().
--

	function project.getfirstconfig(prj)
		local iter = project.eachconfig(prj)
		local first = iter()
		return first
	end


--
-- Retrieve the project's file system location.
--
-- @param prj
--    The project object to query.
-- @param relativeto
--    Optional; if supplied, the project location will be made relative
--    to this path.
-- @return
--    The path to the project's file system location.
--

	function project.getlocation(prj, relativeto)
		local location = prj.location or prj.solution.location or prj.basedir
		if relativeto then
			location = path.getrelative(relativeto, location)
		end
		return location
	end


--
-- Return the relative path from the project to the specified file.
--
-- @param prj
--    The project object to query.
-- @param filename
--    The file path, or an array of file paths, to convert.
-- @return
--    The relative path, or array of paths, from the project to the file.
--

	function project.getrelative(prj, filename)
		if type(filename) == "table" then
			local result = {}
			for i, name in ipairs(filename) do
				result[i] = project.getrelative(prj, name)
			end
			return result
		else
			if filename then
				return path.getrelative(project.getlocation(prj), filename)
			end
		end
	end


--
-- Create a tree from a project's list of source files.
--
-- @param prj
--    The project to query.
-- @return
--    A tree object containing the source file hierarchy. Leaf nodes
--    representing the individual files contain the fields:
--      abspath  - the absolute path of the file
--      relpath  - the relative path from the project to the file
--      vpath    - the file's virtual path
--    All nodes contain the fields:
--      path     - the node's path within the tree
--      realpath - the node's file system path (nil for virtual paths)
--      name     - the directory or file name represented by the node
--

	function project.getsourcetree(prj)
		-- make sure I have the project, and not it's root configuration
		prj = prj.project or prj
		
		-- check for a previously cached tree
		if prj.sourcetree then
			return prj.sourcetree
		end

		-- find *all* files referenced by the project, regardless of configuration
		local files = {}
		for cfg in project.eachconfig(prj) do
			for _, file in ipairs(cfg.files or {}) do
				if not path.isabsolute(file) then
					file = path.join( prj.basedir, file )
				end
				files[file] = file
			end
		end

		-- create a tree from the file list
		local tr = premake.tree.new(prj.name)
		
		for file in pairs(files) do
			local fcfg = project.getfileconfig(prj, file)

			-- The tree represents the logical source code tree to be displayed
			-- in the IDE, not the physical organization of the file system. So
			-- virtual paths are used when adding nodes.
			local node = premake.tree.add(tr, fcfg.vpath, function(node)
				-- ...but when a real file system path is used, store it so that
				-- an association can be made in the IDE 
				if fcfg.vpath == fcfg.relpath then
					node.realpath = node.path
				end
			end)

			-- Store full file configuration in file (leaf) nodes
			for key, value in pairs(fcfg) do
				node[key] = value
			end
		end

		premake.tree.trimroot(tr)
		premake.tree.sort(tr)
		
		-- cache result and return
		prj.sourcetree = tr
		return tr
	end


--
-- Given a source file path, return a corresponding virtual path based on
-- the vpath entries in the project. If no matching vpath entry is found,
-- the original path is returned.
--

	function project.getvpath(prj, filename)
		-- if there is no match, return the input filename
		local vpath = filename
		
		for replacement,patterns in pairs(prj.vpaths or {}) do
			for _,pattern in ipairs(patterns) do

				-- does the filename match this vpath pattern?
				local i = filename:find(path.wildcards(pattern))
				if i == 1 then				

					-- yes; trim the leading portion of the path
					i = pattern:find("*", 1, true) or (pattern:len() + 1)
					local leaf = filename:sub(i)
					if leaf:startswith("/") then
						leaf = leaf:sub(2)
					end
					
					-- check for (and remove) stars in the replacement pattern.
					-- If there are none, then trim all path info from the leaf
					-- and use just the filename in the replacement (stars should
					-- really only appear at the end; I'm cheating here)
					local stem = ""
					if replacement:len() > 0 then
						stem, stars = replacement:gsub("%*", "")
						if stars == 0 then
							leaf = path.getname(leaf)
						end
					end
					
					vpath = path.join(stem, leaf)

				end
			end
		end
		
		return vpath
	end


--
-- Determines if a project contains a particular build configuration/platform pair.
--

	function project.hasconfig(prj, buildcfg, platform)
		if buildcfg and not prj.configurations[buildcfg] then
			return false
		end
		if platform and not prj.platforms[platform] then
			return false
		end
		return true
	end


--
-- Given a build config/platform pairing, applies any project configuration maps
-- and returns a new (or the same) pairing.
--

	function project.mapconfig(prj, buildcfg, platform)
		local pairing = { buildcfg, platform }
		
		local testpattern = function(pattern, pairing, i)
			local j = 1
			while i <= #pairing and j <= #pattern do
				if pairing[i] ~= pattern[j] then
					return false
				end
				i = i + 1
				j = j + 1
			end
			return true
		end
		
		for pattern, replacements in pairs(prj.configmap or {}) do
			if type(pattern) ~= "table" then
				pattern = { pattern }
			end
			
			-- does this pattern match any part of the pair? If so,
			-- replace it with the corresponding values
			for i = 1, #pairing do
				if testpattern(pattern, pairing, i) then
					if #pattern == 1 and #replacements == 1 then
						pairing[i] = replacements[1]
					else
						pairing = { replacements[1], replacements[2] }
					end
				end
			end
		end
				
		return pairing
	end


--
-- Returns true if the project use the C language.
--

	function project.iscproject(prj)
		local language = prj.language or prj.solution.language
		return language == "C"
	end


--
-- Returns true if the project uses a C/C++ language.
--

	function project.iscppproject(prj)
		local language = prj.language or prj.solution.language
		return language == "C" or language == "C++"
	end



--
-- Returns true if the project uses a .NET language.
--

	function project.isdotnetproject(prj)
		local language = prj.language or prj.solution.language
		return language == "C#"
	end
