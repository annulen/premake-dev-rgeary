	function table.shallowcopy(t)
		local dest = {}
		for k,v in pairs(t) do
			dest[k] = v
		end
		return dest
	end

	function string.explode(s, pattern, plain)
		if (pattern == '') then return false end
		local pos = 0
		local arr = { }
		for st,sp in function() return s:find(pattern, pos, plain) end do
			table.insert(arr, s:sub(pos, st-1))
			pos = sp + 1
		end
		table.insert(arr, s:sub(pos))
		return arr
	end
		
		-- expand ors. { "debug, "a or b" } turns in to { { "debug", "a" }, { "debug", "b" } }
		function permutations(input, perms)
			local rv = {}
			for _,v in ipairs(input) do
				for _,p in ipairs(perms) do
					local r = table.shallowcopy(v)
					table.insert(r, p)
					table.insert(rv, r)					
				end
			end
		end
		local expTerms = { {} }
		
		function e(terms)
			for _,unexpTerm in ipairs(terms) do
				local ts = unexpTerm:explode(' or ', true)
				expTerms = permutations(expTerms, ts)
			end
		end
