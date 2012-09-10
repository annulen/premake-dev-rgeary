--
-- string.lua
-- Additions to Lua's built-in string functions.
-- Copyright (c) 2002-2008 Jason Perkins and the Premake project
--


--
-- Returns an array of strings, each of which is a substring of s
-- formed by splitting on boundaries formed by `pattern`.
-- 

	function string.explode(s, pattern, plain, ignoreRepeatedDelimiters)
		if (pattern == '') then return false end
		local pos = 0
		local arr = { }
		for st,sp in function() return s:find(pattern, pos, plain) end do
			if ignoreRepeatedDelimiters then
				if sp ~= pos then 
					table.insert(arr, s:sub(pos, st-1))
				end
			else
				table.insert(arr, s:sub(pos, st-1))
			end
			pos = sp + 1
		end
		table.insert(arr, s:sub(pos))
		return arr
	end

--
-- Split is similar to explode, but with a better name & default delimiters
--
	function string.split(s, delimiters, ignoreRepeatedDelimiters)
		local pattern = (delimiters or ", \t\n|") 
		return string.explode(s, '['..pattern..']', false, ignoreRepeatedDelimiters)
	end	


--
-- Find the last instance of a pattern in a string.
--

	function string.findlast(s, pattern, plain)
		local curr = 0
		repeat
			local next = s:find(pattern, curr + 1, plain)
			if (next) then curr = next end
		until (not next)
		if (curr > 0) then
			return curr
		end	
	end



--
-- Returns true if `haystack` starts with the sequence `needle`.
--

	function string.startswith(haystack, needle)
		return (haystack:find(needle, 1, true) == 1)
	end
	
--
-- Returns true if the string has a match for the plain specified pattern
--
	function string.contains(str, match)
		return string.find(str, match, 1, true) ~= nil 
	end

--
-- string.gsub without pattern matching
--

	function string.replace(str, searchStr, replaceStr)
		local i = 1
		if not str then
			return ''
		end 
		if #searchStr == 0 then
			return str
		end
		while( i < #str ) do
			local findIdx = string.find(str, searchStr, i, true)
			if findIdx then
				str = str:sub(1,findIdx-1) .. replaceStr .. str:sub(findIdx + #searchStr)
				i = findIdx + #replaceStr
			else
				break
			end
		end
		return str
	end
	
--
-- Remove repeated whitespace
--
	function string.trimWhitespace(str)
		local rv = {}
		for v in str:gmatch('[^\t ]+') do
			table.insert(rv, v)
		end
		return table.concat(rv, ' ') 
	end
	