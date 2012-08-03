--
-- globals.lua
-- Global tables and variables, replacements and extensions to Lua's global functions.
-- Copyright (c) 2002-2011 Jason Perkins and the Premake project
--
	
--
-- Create a top-level namespace for Premake's own APIs. The premake5 namespace 
-- is a place to do next-gen (4.5) work without breaking the existing code (yet).
-- I think it will eventually go away.
--

	premake = { }
	premake5 = { }
	premake.tools = { }

-- Top level namespace for abstract base class definitions 
	premake.abstract = { }
	
-- Top level namespace for actions
	premake.actions = { }

	
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
	function dofile(fname)
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
		
		-- run the chunk. How can I catch variable return values?
		local a, b, c, d, e, f = builtin_dofile(_SCRIPT)
		
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
			filename = path.join(filename, "premake4.lua")
		end
				
		-- but only load each file once
		filename = path.getabsolute(filename)
		if not io._includedFiles[filename] then
			io._includedFiles[filename] = true
			dofile(filename)
		end
	end



--
-- A shortcut for printing formatted output.
--

	function printf(msg, ...)
		print(string.format(msg, unpack(arg)))
	end

	
		
--
-- An extension to type() to identify project object types by reading the
-- "__type" field from the metatable.
--

	builtin_type = type	
	function type(t)
		local mt = getmetatable(t)
		if (mt) then
			if (mt.__type) then
				return mt.__type
			end
		end
		return builtin_type(t)
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
				local typeV = builtin_type(v)
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
			setmetatable( rv, { __type = derivedClassName } ) 
		end
		return rv
	end

	function prepend(a,b)
		return concat(b,a)
	end
	
	function concat(a,b)
		local atype = builtin_type(a)
		local btype = builtin_type(b)
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
				for k,v in pairs(b) do
					rv[k] = v
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
	
	function mkstring(t, delimiter)
		return table.concat(t, delimiter)
	end
	
	function toSet(vs)
		if type(vs) == 'string' then
			-- Convert string to hashset
			local t = {}
			t[vs] = 1
			return t
		elseif type(vs) == 'function' then
			-- assume it's an iterator function
			kvs = {}
			for k,v in vs do
				kvs.v = 1
			end
			return kvs
		end
		if #vs > 0 then
			-- Convert sequence to hashset
			kvs = {}
			for _,v in ipairs(vs) do
				kvs.v = 1
			end
			return kvs
		else
			return vs
		end
	end
	
	