--
--  New way to read/bake configurations
--

premake.keyedblocks = {}
local keyedblocks = premake.keyedblocks
local oven = premake5.oven


function keyedblocks.expandTerms(terms)
	function permutations(input, perms)
		local rv = {}
		for _,v in ipairs(input) do
			for _,p in ipairs(perms) do
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
	return expTerms
end

-- can be sln, prj or cfg
function keyedblocks.bake(obj)
	local kbBase = {}
	
	for _,block in ipairs(obj.blocks or {}) do
		local terms = block.keywords
		
		-- expand ors. { "debug, "a or b" } turns in to { { "debug", "a" }, { "debug", "b" } }
		local expTerms = keyedblocks.expandTerms(terms)

		-- have a well defined order for the terms
		for _,terms in ipairs(expTerms) do
			table.sort(terms)
			
			-- Iterate over 'and' terms to create a nested block
			local kb = kbBase
			for _,term in ipairs(terms) do
				
				-- 'not' is a separate category
				if term:startswith('not ') then
					kb['not'] = kb['not'] or {}
					kb = kb['not']
					term = term:sub(5)
				end
				
				-- Insert term in to keyedblocks
				kb[term] = kb[term] or {}
				
				-- recurse kb
				kb = kb[term]
			end
			
			-- insert the field values in to the keyed block
			kb.values = kb.values or {}
			local ignoreField = { terms = 1, keywords = 1 }
			for k,v in pairs(block) do
				if (not ignoreField[k]) and v and (#v > 0) then
					local field = premake.fields[k] 
					local fieldKind = field.kind
					oven.mergevalue(kb.values, k, fieldKind, v)
				end
			end
		end -- expTerms
		
	end
	obj.keyedblocks = kbBase
	
	return obj
end
