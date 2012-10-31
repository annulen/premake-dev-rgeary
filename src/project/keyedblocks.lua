--
--  New way to read/bake configurations
--

premake.keyedblocks = {}
local keyedblocks = premake.keyedblocks

local globalContainer = premake5.globalContainer
local targets = premake5.targets
local project = premake5.project
local oven = premake5.oven

--
-- Expand any 'a or b' statements, and sort each term within the term set 
function keyedblocks.expandTerms(terms)
	if type(terms) == 'string' then
		terms = { terms }
	end

	-- Return { { input, perm[1] } } if #perms == 1
	--   or { { input, perm[1] }, { input, perm[2] } ... } if #perms > 1 
	function permutations(input, perms)
		local rv = {}
		for _,v in ipairs(input) do
			for _,p in ipairs(perms) do
				
				-- 'not' terms, replace with '-' for sorting
				if p:startswith('not ') then
					p = '-'..p:sub(5)
				end
				p = p:lower()
				
				-- create permutations
				local r = table.shallowcopy(v)
				table.insert(r, p)
				table.insert(rv, r)					
			end
		end
		return rv
	end
	
	local expTerms = { {} }
	for _,unexpTerm in ipairs(terms) do
		local ts = unexpTerm:explode(' or ', true)
		expTerms = permutations(expTerms, ts)
	end
	
	-- have a well defined order for the terms
	for _,terms in ipairs(expTerms) do
		table.sort(terms)
	end
	
	return expTerms
end

-- Generate the keyedblocks from the blocks. obj can be sln, prj or cfg
function keyedblocks.create(obj, parent)
	local kbBase = {}
	
	-- No need to bake twice
	if obj.keyedblocks then
		return obj
	end
	
	if parent == obj then
		parent = nil
	end
	
	local namespaces = obj.namespaces
	
	local tmr = timer.start('keyedblocks.create')
	for _,block in ipairs(obj.blocks or {}) do
		local terms = block.keywords
		
		-- expand ors. { "debug, "a or b" } turns in to { { "debug", "a" }, { "debug", "b" } }
		local expTerms = keyedblocks.expandTerms(terms)

		for _,terms in ipairs(expTerms) do
			-- Iterate over 'and' terms to create a nested block
			local kb = kbBase
			for _,term in ipairs(terms) do
				
				-- case insensitive
				term = term:lower()
				
				if premake.fieldAliases[term] then
					term = premake.fieldAliases[term]
				end
				-- if it's of the form key=value, matchy on the value
				if term:contains('=') then
					term = term:match(".*=(.*)")
				end

				-- 'not' is a separate category
				local kbcfg
				if term:startswith('-') then
					kb.__notconfig = kb.__notconfig or {}
					kbcfg = kb.__notconfig
					term = term:sub(2)
				else
					kb.__config = kb.__config or {}
					kbcfg = kb.__config
				end

				-- TODO : Separate category for wildcard configuration strings

				-- Insert term in to keyedblocks
				kbcfg[term] = kbcfg[term] or {}
				if kb.__name then
					kbcfg[term].__name = term ..':'.. kb.__name
				end

				-- recurse kb
				kb = kbcfg[term]
			end

			-- insert the field values in to the keyed block
			local ignoreField = { terms = 1, keywords = 1, removes = 1 }
			for k,v in pairs(block) do
				if (not ignoreField[k]) and v and (#v>0 or not table.isempty(v)) then
					if premake.fieldAliases[v] then
						v = premake.fieldAliases[v]
					end

					-- Include the key/value
					oven.mergefield(kb, k, v)
				end
			end -- each block

			if block.removes then
				for k,v in pairs(block.removes) do
					if (not ignoreField[k]) and v and (not table.isempty(v)) then
						kb.__removes = kb.__removes or {}
						oven.mergefield(kb.__removes, k, v)
					end
				end
			end -- block.removes

			keyedblocks.resolveUses(kb, obj)

		end -- expTerms

	end

	if parent then
		kbBase.__parent = parent
	end
	kbBase.__name = obj.name

	obj.keyedblocks = kbBase

	timer.stop(tmr)

	return obj
end

function keyedblocks.resolveUses(kb, obj)
	if kb.uses or kb.alwaysuses then
		kb.__uses = kb.__uses or {}

		local uses = kb.uses or kb.alwaysuses
		if kb.alwaysuses and kb.uses then
			uses = {}
			for _,v in Seq:ipairs(kb.uses):iconcat(kb.alwaysuses):each() do
				table.insert(uses, v)
			end
		end

		for _,useProjName in ipairs(uses) do
			
			local usesfeature = {}
			for v in useProjName:gmatch(':([^:]*)') do
				table.insert( usesfeature, v )
			end
			if #usesfeature == 0 then usesfeature = nil end
			useProjName = useProjName:match("[^:]*")
			
			local useProj = kb.__uses[useProjName]

			if type(useProj) ~= 'table' then
				local suggestions
				useProj, suggestions = keyedblocks.getUsage(useProjName, obj.namespaces)
				if not useProj then
					local errMsg = '\nCould not find usage "'..tostring(useProjName)..'" ' ..
					"for project "..tostring(obj.name) ..' at ' .. tostring(obj.basedir)
					if suggestions then
						errMsg = errMsg .. '"\n' .. suggestions
					end
					error(errMsg)
				end
				kb.__uses[useProjName] = { prj = useProj, usesfeature = usesfeature }
			end
		end
	end
end

function keyedblocks.getUsage(name, namespaces)
	local suggestions, suggestionStr

	local usage = project.getUsageProject(name, namespaces)
	if not usage then
		-- check if it's a solution usage
		usage = project.getUsageProject(name..'/'..name)
	end

	if not usage then
		suggestions, suggestionStr = project.getProjectNameSuggestions(name, namespaces)
	end

	return usage, suggestionStr
end

function keyedblocks.bake(usage)
	if not usage.keyedblocks then
		if ptype(usage) == 'project' then
			globalContainer.bakeUsageProject(usage)
		else
			keyedblocks.create(usage)
		end
	end
end

function keyedblocks.merge(dest, src)
	if not src then
		return
	end
	for k,v in ipairs(src) do
		oven.mergefield(dest, k, v)
	end
	
	for k,v in pairs(src) do
		--if k ~= '__values' and k ~= 'uses' then
			dest[k] = dest[k] or {} 
			keyedblocks.merge(dest[k], v)
		--end
	end
end


--
-- Returns a field from the keyedblocks
--   eg. keyedblocks.getfield(cfg, { buildcfg="debug"}, 'kind')
-- May have to create the usage & bake the project if it's not already created 
--
function keyedblocks.getfield(obj, keywords, fieldName, dest)
	dest = dest or {}
	
	local tmr = timer.start('keyedblocks.getfield')
	local tmr2 = timer.start('keyedblocks.getfilter')
	
	local function getKeywordSet(ws)
		local rv = {}
		for k,v in pairs(ws) do

			-- convert flags to hash set, eg. { "Threading=Multi" } -> { Threading = "Multi" }
			if type(k) == 'number' and v and type(v) == 'string' and v ~= '' then
				if v:find('not ') then
					error("keyword 'not' not supported as a filter")
				end
				if v:find(' or ') then
					error("keyword 'or' not supported as a filter")
				end
				
				if v:contains("=") then
					local k = v:match("[^=]*")
					rv[k] = v:match(".*=(.*)"):lower()
				else
					rv[v] = v:lower()
				end
			else
				rv[k] = v:lower()
			end
		end
		return rv
	end
	local filter = getKeywordSet(keywords)
	
	-- repeat until the filter is stable
	local loop = 0
	local loopMax = 10
	local origFilter
	local filterList = {}
	
	repeat
		loop = loop + 1
		
		origFilter = table.shallowcopy(filter)
		table.insert(filterList, origFilter)
		local usesconfig = keyedblocks.getfield2(obj, filter, "usesconfig", {})

		-- usesconfig adds/mutates to the filter
		if usesconfig then
			local filter2 = {}
			for k,v in Seq:new(filter):concat(usesconfig):each() do
				-- .usesconfig & filter is of the form { Debug, "Threading=Multi", }
				-- ie. set the filter on the key, match blocks on the value
				if type(k) == 'number' then
					k = v
					if v:contains("=") then 
						k = v:match("[^=]*")
						v = v:match(".*=(.*)")
					end 
				end
				v = v:lower()
				filter2[k] = v
			end
			filter = filter2
		end
		
		local filterUnchanged = table.equals(filter, origFilter)
		if filterUnchanged then
			break
		end
	until( loop > loopMax )
	if loop >= loopMax then
		print("Maximum recursion reached, configuration filter is oscillating : ")
		for _,f in ipairs(filterList) do
			print(mkstring(f))
		end
		error("Please change your configuration, you've defined an unstable loop")
	end
	timer.stop(tmr2)
	
	-- Now we've got the final filter, get the correct values
	local rv = keyedblocks.getfield2(obj, filter, fieldName, dest)

	timer.stop(tmr)

	return rv
end

function keyedblocks.getfield2(obj, filter, fieldName, dest)
	local rv = dest
	if not obj.keyedblocks then
		return nil
	end
	local kbBase = obj.keyedblocks

	-- Find the values & .removes structures which apply to 'keywords'
	local accessedBlocks = {}
	local foundBlocks = {}

	local function findBlocks(kb)
		
		if not kb or table.isempty(kb) then
			return nil
		elseif accessedBlocks[kb] then
			return nil
		end
		accessedBlocks[kb] = kb

		-- Apply parent before block
		if kb.__parent then
			keyedblocks.bake(kb.__parent)
			findBlocks(kb.__parent.keyedblocks)
		end

		-- New : Apply usages before block, so the block can override them
		-- Old : Apply usages after block
		if kb.__uses then
			for useProjName, p in pairs(kb.__uses) do
				keyedblocks.bake(p.prj)
				local buildFeature = {
					buildcfg = filter.buildcfg,
					platform = filter.platform,
				}

				if p.usesfeature then
					-- Add the build feature to the target project's config list
					local oldFilter = filter
					filter = table.shallowcopy(filter)
					for _,v in ipairs(p.usesfeature) do
						v = v:lower()
						buildFeature[v] = v
						filter[v] = v
					end
					project.addconfig(p.prj, buildFeature)
					
					-- evaluate the usage requirements of the target project, with the feature(s) enabled
					findBlocks(p.prj.keyedblocks)
					
					filter = oldFilter
				else
					findBlocks(p.prj.keyedblocks)
				end
			end
		end

		-- Found some values to add/remove
		table.insert( foundBlocks, kb )

		-- Iterate through the filters and apply any blocks that match
		if kb.__config then
			for _,term in pairs(filter) do
				-- check if this combination of terms has been specified
				if kb.__config[term] then
					findBlocks(kb.__config[term])
				end
			end
		end

		-- check the 'not' terms
		if kb.__notconfig then
			for notTerm,notTermKB in pairs(kb.__notconfig) do
				local match = false
				for _,term in pairs(filter) do
					if term == notTerm then
						match = true
						break
					end
				end
				if not match then
					-- recurse
					findBlocks(notTermKB)
				end
			end
		end

	end -- findBlocks

	local filterStr = getValues(filter)
	table.sort(filterStr)
	filterStr = table.concat(filterStr, ' ')
	
	kbBase.__cache = kbBase.__cache or {}
	if kbBase.__cache[filterStr] then
		foundBlocks = kbBase.__cache[filterStr]
	else
		findBlocks(kbBase)
	end
	kbBase.__cache[filterStr] = foundBlocks

	if not fieldName then
		rv.filter = table.shallowcopy(filter)
	end

	timer.start('applyvalues')
	-- Filter values structures
	local isEmpty = table.isempty(foundBlocks)
	--insertBlockList(rv, foundBlocks)

	local removes = {}
	local ignore = toSet({ '__config', '__name', '__parent', '__uses', '__cache' })
	for _,block in ipairs(foundBlocks) do
		if not fieldName then
			for k,v in pairs(block) do
				if ignore[k] then
					-- do nothing
				elseif k == '__removes' then
					table.insert(removes, v)
				else
					oven.mergefield(rv, k, v)
				end
			end
		else
			oven.mergefield(rv, fieldName, block[fieldName])
			if block.__removes then
				table.insert(removes, block.__removes)
			end
		end
	end

	-- Remove values
	for _,removeBlock in ipairs(removes) do
		if not fieldName then
			for k,v in pairs(removeBlock) do
				oven.removefromfield(rv[k], v)
			end
		elseif removes[fieldName] then
			for k,v in pairs(removeBlock) do
				oven.remove(rv, fieldName, removes[fieldName])
			end
		end
	end
	timer.stop()
	
	if isEmpty then
		return nil
	elseif fieldName then
		return rv[fieldName]
	else
		return rv
	end
end

-- return or create the nested keyedblock for the given term
function keyedblocks.createblock(kb, buildFeatures)
	for k,v in pairs(buildFeatures) do
		v = v:lower()
		if v:find('not ') then
			error("keyword 'not' not supported as a filter")
		end
		if v:find(' or ') then
			error("keyword 'or' not supported as a filter")
		end
		
		kb.__config = kb.__config or {}
		kb.__config[v] = kb.__config[v] or {}
		kb = kb.__config[v]
	end
	
	return kb
end

--
-- Testing
--

function keyedblocks.test()
	
	global()
	usage "testRecursion"
		uses "testBase"
		define "recurse"
	usage "testBase"
		uses "testRecursion"
		define "recurseBase"
		configuration "debug"
			includedir "dir/testBase"
	usage "testUsage"
		uses "testBase"
		configuration "debug"
			includedir "dir/debug"
		configuration "release"
			includedir "dir/release"
		configuration "not debug"
			includedir "dir/notdebug"
		configuration "debug or release"
			includedir "dir/debugorrelease"
			buildoptions "-DEBUGORREL"
	global()
	
	local gc = premake5.globalContainer
	local Print = premake.actions.Print
	local testUsage = keyedblocks.create(targets.allUsage["testUsage"])
	local testRecursion = keyedblocks.create(targets.allUsage["testRecursion"])
	local testBase = keyedblocks.create(targets.allUsage["testBase"])
	local xU = keyedblocks.getfield(testUsage, { 'release', 'debug' }, nil)
	local xB = keyedblocks.getfield(testBase, { 'release', 'debug' }, nil)
	local xR = keyedblocks.getfield(testRecursion, { 'release', 'debug' }, nil)
	
	Print.print('kbU = ', xU)
	Print.print('kbB = ', xB)
	Print.print('kbR = ', xR)
	print('')	
end
