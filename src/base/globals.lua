--
-- globals.lua
-- Global tables and variables, replacements and extensions to Lua's global functions.
-- Copyright (c) 2002-2011 Jason Perkins and the Premake project
--
	
	
-- The list of supported platforms; also update list in cmdline.lua

	premake.platforms = 
	{
		Native = 
		{ 
			cfgsuffix       = "",
		},
		x32 = 
		{ 
			cfgsuffix       = "32",
		},
		x64 = 
		{ 
			cfgsuffix       = "64",
		},
		Universal = 
		{ 
			cfgsuffix       = "univ",
		},
		Universal32 = 
		{ 
			cfgsuffix       = "univ32",
		},
		Universal64 = 
		{ 
			cfgsuffix       = "univ64",
		},
		PS3 = 
		{ 
			cfgsuffix       = "ps3",
			iscrosscompiler = true,
			nosharedlibs    = true,
			namestyle       = "PS3",
		},
		WiiDev =
		{
			cfgsuffix       = "wii",
			iscrosscompiler = true,
			namestyle       = "PS3",
		},
		Xbox360 = 
		{ 
			cfgsuffix       = "xbox360",
			iscrosscompiler = true,
			namestyle       = "windows",
		},
	}

--
-- A replacement for Lua's built-in dofile() function, this one sets the
-- current working directory to the script's location, enabling script-relative
-- referencing of other files and resources.
--

	local builtin_dofile = dofile
	function dofile(fname, enableSpellCheck)
		-- remember the current working directory and file; I'll restore it shortly
		local oldcwd = os.getcwd()
		local oldfile = _SCRIPT

		-- if the file doesn't exist, check the search path
		if (not os.isfile(fname)) then
			local path = os.pathsearch(fname, _OPTIONS["scripts"], os.getenv("PREMAKE_PATH"))
			if (path) then
				fname = path.."/"..fname
			end
		end

		-- use the absolute path to the script file, to avoid any file name
		-- ambiguity if an error should arise
		_SCRIPT = path.getabsolute(fname)
		
		-- switch the working directory to the new script location
		local newcwd = path.getdirectory(_SCRIPT)
		os.chdir(newcwd)
		
		if enableSpellCheck then
			premake.spellCheckEnable(_G)
		end
		
		-- run the chunk. How can I catch variable return values?
		local a, b, c, d, e, f = builtin_dofile(_SCRIPT)

		if enableSpellCheck then
			premake.spellCheckDisable(_G)
		end
		
		-- restore the previous working directory when done
		_SCRIPT = oldfile
		os.chdir(oldcwd)
		return a, b, c, d, e, f
	end



--
-- "Immediate If" - returns one of the two values depending on the value of expr.
--

	function iif(expr, trueval, falseval)
		if (expr) then
			return trueval
		else
			return falseval
		end
	end
	
	
	
--
-- Load and run an external script file, with a bit of extra logic to make 
-- including projects easier. if "path" is a directory, will look for 
-- path/premake4.lua. And each file is tracked, and loaded only once.
--

	io._includedFiles = { }
	
	function include(filename)
		-- if a directory, load the premake script inside it
		if os.isdir(filename) then
			local dir = filename
			filename = path.join(dir, "premake4.lua")
			
			if not os.isfile(filename) then
				local files = os.matchfiles(path.join(dir,'premake*.lua'))
				if #files > 0 then
					filename = files[1]
				end
			end
			
		end
		if not os.isfile(filename) then
			error('Could not find include "'..filename ..'" in file "'.._SCRIPT..'"')
		end
				
		-- but only load each file once
		filename = path.getabsolute(filename)
		if not io._includedFiles[filename] then
			io._includedFiles[filename] = true
			dofile(filename)
		end
	end

--
-- For printing in quiet mode
--
	_G.printAlways = _G.print

--
-- A shortcut for printing formatted output.
--

	function printf(msg, ...)
		print(string.format(msg, unpack(arg)))
	end

	
		
--
-- Premake type. An extension to type() to identify project object types by reading the
-- "__type" field from the metatable.
--

	function ptype(t)
		local mt = getmetatable(t)
		if (mt) then
			if (mt.__type) then
				return mt.__type
			end
		end
		return type(t)
	end
	
	function ptypeSet(t, name)
		local mt = getmetatable(t) or {}
		mt.__type = name
		return setmetatable(t, mt)
	end
	
	
--
-- Count the number of elements in an associative table
--

	function count(t)
		local c = 0
		if t then
			for _,_ in pairs(t) do
				c = c + 1
			end
		end
		return c
	end
	
--
-- Map/Select function. Performs fn(key,value) on each element in a table, returns as a list 
--

	function map(t,fn)
	  rv = {}
	  if t then
		  for key,value in pairs(t) do
		  	table.insert(rv, fn(key,value))
		  end
	  end
	  return rv
	end

--
-- Map/Select function. Performs fn(value) for each numeric keyed element in a table, returns as a list 
--

	function imap(t,fn)
	  rv = {}
	  if( t ) then
		  for _,value in ipairs(t) do
		  	table.insert(rv, fn(value))
		  end
	  end
	  return rv
	end

--
-- Returns the keys in a table. Or the sequence numbers if it's a sequence
--
  
	function getKeys(t)
		rv = {}
		if t then
			for k,_ in pairs(t) do
				table.insert(rv, k)
			end
		end
		return rv
	end
	

--
-- Returns the values in a table or sequence
--
  
	function getValues(t)
		rv = {}
		if t then
			for _,v in pairs(t) do
				table.insert(rv, v)
			end
		end
		return rv
	end
	
--
-- Returns the values for integer keyed entries in a table
--
  
	function getIValues(t)
		rv = {}
		if t then
			for _,v in ipairs(t) do
				table.insert(rv, v)
			end
		end
		return rv
	end
--
-- Returns the names of all the functions in the table
--

	function getFunctionNames(t)
		rv = {}
		if t then
			for k,v in pairs(t) do
				if( type(v) == "function" ) then
					table.insert(rv, k)
				end
			end
		end
		return rv
	end
	
--
-- Returns the names of all the tables in the table
--

	function getSubTableNames(t)
		rv = {}
		if t then
			for k,v in pairs(t) do
				local typeV = type(v)
				if( typeV == "table" ) then
					table.insert(rv, k)
				end
			end
		end
		return rv
	end
	
--
-- Returns true if the object contains a list of strings
--
	function isStringSeq(t)
		local rv = false
		if( #t>0 ) then
			rv = true
			for _,v in ipairs(t) do
				if type(v) ~= 'string' then
					rv = false
					break
				end
			end
		else
			rv = false
		end
		return rv
	end
		
--
-- 'Inherit' functions & members from a base table. Performs a shallow copy of a table.
--
	function inheritFrom(t, derivedClassName)
		rv = {}
		for k,v in pairs(t) do
			rv[k] = v
		end
		if rv.super == nil then
			rv.super = t
		end
		-- Optional, but useful for error messages
		if( derivedClassName ) then
			ptypeSet( rv, derivedClassName )
		end
		return rv
	end

	function prepend(a,b)
		return concat(b,a)
	end
	
	function concat(a,b)
		local atype = type(a)
		local btype = type(b)
		local rv = {}
		
		if a == nil then
			rv = b
		elseif b == nil then
			rv = a
		elseif atype == "table" then
			if btype == "string" then
				-- Concatenate b on to each element of a
				for k,v in pairs(a) do
					if( type(v) == "string" ) then
						rv[k] = v .. b
					end
				end
			elseif btype == "table" then
				-- Concatenate b on to a, ie. Assuming no overwrites, #(a++b) == #a + #b
				for k,v in pairs(a) do
					rv[k] = v
				end
				local offset = #a
				for k,v in pairs(b) do
					if type(k) == 'number' then
						rv[k+offset] = v
					else
						rv[k] = v
					end
				end
			end
		elseif( btype == "table" ) then
			if atype == "string" then
				-- Prepend a on to each element of b
				for k,v in pairs(b) do
					if( type(v) == "string" ) then
						rv[k] = a ..v
					end
				end
			end
		end
		return rv
	end
	
	function mkstring(t, delimiter, seen)
		delimiter = delimiter or ' '
		seen = seen or {}
		if seen[t] then
			return seen[t]
		end
		seen[t] = ''
		
		local rv
		if t == nil then
			rv = ''
		elseif type(t) == 'string' then
			rv = t
		elseif type(t) == 'table' then
			local s = ''
			for k,v in pairs(t) do
				if #s > 0 then s = s .. delimiter end
				if type(k) == 'number' then
					s = s .. mkstring(v, delimiter, seen)
				else
					s = s .. mkstring(k, delimiter, seen) ..'='..mkstring(v, delimiter, seen)
				end
			end
			rv = s
		else
			rv = tostring(t)
		end
		seen[t] = rv
		return rv
	end
	
	function toSet(vs, toLower)
		if not vs then return {} end
		if type(vs) == 'string' then
			-- Convert string to hashset
			local t = {}
			if toLower then vs = vs:lower() end
			t[vs] = vs
			return t
		elseif type(vs) == 'function' then
			-- assume it's an iterator function
			kvs = {}
			for k,v in vs do
				if toLower then v = v:lower() end
				kvs[v] = v
			end
			return kvs
		end
		if #vs > 0 then
			-- Convert sequence to hashset
			kvs = {}
			for _,v in ipairs(vs) do
				if toLower then v = v:lower() end
				kvs[v] = v
			end
			return kvs
		else
			local t = {}
			if toLower then
				for k,v in pairs(vs) do
					if type(k) == 'string' then
						t[k:lower()] = v:lower()
					else
						t[k] = v:lower()
					end
				end
				return t
			else
				return vs
			end
		end
	end
	
	function toList(vs)
		if type(vs) == 'function' then
			-- assume it's an iterator function
			rv = {}
			for k,v in vs do
				table.insert(rv, v)
			end
			return rv
		elseif type(vs) == 'table' then
			return vs
		else
			-- Convert to sequence
			return { vs }
		end		
	end
	
	function printDebug(msg, ...)
		if _OPTIONS['debug'] then
			printf(msg, unpack(arg))
		end
	end
	
	-- Pad msg with spaces
	function padSpaces(msg, length)
		local rv = msg
		if #rv < length then
			for i=#rv,length-1 do
				rv = rv..' '
			end
		end
		return rv
	end