--
-- os.lua
-- Additions to the OS namespace.
-- Copyright (c) 2002-2011 Jason Perkins and the Premake project
--

--
-- Same as os.execute(), but accepts string formatting arguments.
--

	function os.executef(cmd, ...)
		if repoRoot then
			cmd = cmd:replace('$root', repoRoot)
		end
		cmd = string.format(cmd, unpack(arg))
		if( _OPTIONS['dryrun'] ) then	
			print("Execute : " ..cmd)
			return 0 
		else
			return os.execute(cmd)
		end
	end
	
--
-- Override to replace $root with repoRoot
--
	local builtin_isfile = os.isfile
	function os.isfile(s)
		if not s then 
			return false 
		end
		if repoRoot then
			s = s:replace('$root', repoRoot)
		end
		return builtin_isfile(s)
	end

--
-- Scan the well-known system locations for a particular library. 
--  Add to the search path using premake.libsearchpath
--

	function os.findlib(libname)
		local path, formats
		local delimiter = ':'

		-- assemble a search path, depending on the platform
		if os.is("windows") then
			formats = { "%s.dll", "%s" }
			path = os.getenv("PATH")
			delimiter = ';'
		elseif os.is("haiku") then
			formats = { "lib%s.so", "%s.so" }
			path = os.getenv("LIBRARY_PATH")
		else
			if os.is("macosx") then
				formats = { "lib%s.dylib", "%s.dylib" }
				path = os.getenv("DYLD_LIBRARY_PATH")
			else
				formats = { "lib%s.so", "%s.so" }
				path = os.getenv("LD_LIBRARY_PATH") or ""

				io.input("/etc/ld.so.conf")
				if io.input() then
					for line in io.lines() do
						path = path .. ":" .. line
					end
					io.input():close()
				end
			end

			table.insert(formats, "%s")
			path = path or ""
			if os.is64bit() then
				path = path .. ":/lib64:/usr/lib64/:usr/local/lib64"
			end
			path = path .. ":/lib:/usr/lib:/usr/local/lib"
		end
		
		if premake.libSearchPath then
			path = path .. delimiter .. table.concat(premake.libSearchPath, delimiter)
		end

		for _, fmt in ipairs(formats) do
			local name = string.format(fmt, libname)
			local result = os.pathsearch(name, path)
			if result then return result end
		end
	end


--
-- Scan the well-known system locations for a particular binary.
--

	function os.findbin(binname, hintPath)
		local formats = {} 
		local path = os.getenv("PATH") or ""
		
		if os.isfile(binname) then
			return binname
		end
		
		if( hintPath ) then
			path = hintPath..os.getPathDelimiter()..path
		end
				
		local firstArg = string.find(binname, ' ')
		if firstArg then
			binname = string.sub(binname,1,firstArg-1)
		end

		-- assemble a search path, depending on the platform
		if os.is("windows") then
			formats = { "%s.exe", "%s.com", "%.bat", "%.cmd", "%s" }
		elseif os.is("haiku") then
			formats = { "%s" }
		else
			if os.is("macosx") then
				formats = { "%s", "%s.app" }
			else
				formats = { "%s" }
			end
		end

		for _, fmt in ipairs(formats) do
			local name = string.format(fmt, binname)
			local result = os.pathsearch(name, path)
			if result then return result end
		end
	end

--
-- Platform specific path delimiter
--
	function os.getPathDelimiter()
		if _OS == "windows" then 
			return ';'
		else 
			return ':' 
		end
	end

--
-- Retrieve the current operating system ID string.
--

	function os.get()
		return _OPTIONS.os or _OS
	end



--
-- Check the current operating system; may be set with the /os command line flag.
--

	function os.is(id)
		return (os.get():lower() == id:lower())
	end



--
-- Determine if the current system is running a 64-bit architecture
--

	local _64BitHostTypes = {
		"x86_64",
		"ia64",
		"amd64",
		"ppc64",
		"powerpc64",
		"sparc64"
	}
	local hostIs64bit 
	function os.is64bit()
		-- Call the native code implementation. If this returns true then
		-- we're 64-bit, otherwise do more checking locally
		if (os._is64bit()) then
			return true
		end
		
		if( hostIs64bit == nil ) then
			-- Identify the system
			local arch
			if _OS == "windows" then
				arch = os.getenv("PROCESSOR_ARCHITECTURE")
			elseif _OS == "macosx" then
				arch = os.outputof("echo $HOSTTYPE")
			else
				arch = os.outputof("uname -m")
			end
	
			-- Check our known 64-bit identifiers
			arch = arch:lower()
			for _, hosttype in ipairs(_64BitHostTypes) do
				if arch:find(hosttype) then
					hostIs64bit = true
					return true
				end
			end
			hostIs64bit = false
		end
		return hostIs64bit 
	end



--
-- The os.matchdirs() and os.matchfiles() functions
--

	local function domatch(result, mask, wantfiles)
		-- need to remove extraneous path info from the mask to ensure a match
		-- against the paths returned by the OS. Haven't come up with a good
		-- way to do it yet, so will handle cases as they come up
		if mask:startswith("./") then
			mask = mask:sub(3)
		end
		
		-- if mask has double // from concatenating a dir with a trailing slash, remove it
		mask = mask:replace('//','/')

		-- strip off any leading directory information to find out
		-- where the search should take place
		local basedir = mask:replace("**","*")
		basedir = path.getdirectory(basedir)
		if (basedir == ".") then basedir = "" end

		-- recurse into subdirectories?
		local recurse = mask:find("**", nil, true)

		-- convert mask to a Lua pattern
		mask = path.wildcards(mask)

		local function matchwalker(basedir)
			if basedir:endswith("*") then
				local wildcard = basedir
				m = os.matchstart(wildcard)
				while (os.matchnext(m)) do
					if not os.matchisfile(m) then
						local dirname = os.matchname(m)
						matchwalker(path.join(basedir:sub(1,#basedir-1), dirname))
					end
				end
				os.matchdone(m)
				return
			end
			local wildcard = path.join(basedir, "*")

			-- retrieve files from OS and test against mask
			local m = os.matchstart(wildcard)
			while (os.matchnext(m)) do
				local isfile = os.matchisfile(m)
				if ((wantfiles and isfile) or (not wantfiles and not isfile)) then
					local fname = path.join(basedir, os.matchname(m))
					if fname:match(mask) == fname then
						table.insert(result, fname)
					end
				end
			end
			os.matchdone(m)

			-- check subdirectories
			if recurse then
				m = os.matchstart(wildcard)
				while (os.matchnext(m)) do
					if not os.matchisfile(m) then
						local dirname = os.matchname(m)
						matchwalker(path.join(basedir, dirname))
					end
				end
				os.matchdone(m)
			end
		end

		matchwalker(basedir)
	end

	function os.matchdirs(...)
		local result = { }
		for _, mask in ipairs(arg) do
			domatch(result, mask, false)
		end
		return result
	end

	function os.matchfiles(...)
		local result = { }
		for _, mask in ipairs(arg) do
			domatch(result, mask, true)
		end
		return result
	end



--
-- An overload of the os.mkdir() function, which will create any missing
-- subdirectories along the path.
--

	local builtin_mkdir = os.mkdir
	function os.mkdir(p)
		if( _OPTIONS['dryrun'] ) then	
			printf("mkdir : " .. p .. '\n')
			return true
		end
			
		local dir = iif(p:startswith("/"), "/", "")
		for part in p:gmatch("[^/]+") do
			dir = dir .. part

			if (part ~= "" and not path.isabsolute(part) and not os.isdir(dir)) then
				local ok, err = builtin_mkdir(dir)
				if (not ok) then
					return nil, err
				end
			end

			dir = dir .. "/"
		end

		return true
	end


--
-- Run a shell command and return the output.
--

	function os.outputof(cmd)
		local pipe = io.popen(cmd)
		local result = pipe:read('*a')
		pipe:close()
		return result
	end


--
-- Remove a directory, along with any contained files or subdirectories.
--
	local removeList = {}		-- just so we don't print the same command twice

	local builtin_rmdir = os.rmdir
	function os.rmdir(p)
		if repoRoot then
			p = p:replace('$root', repoRoot)
		end
		if( _OPTIONS['dryrun'] ) then
			if (os.isfile(p)	or os.isdir(p)) and (not removeList[p]) then
				print("rm -rf " .. p)
				removeList[p] = true
			end	
			return true
		end
	
		-- recursively remove subdirectories
		local dirs = os.matchdirs(p .. "/*")
		for _, dname in ipairs(dirs) do
			os.rmdir(dname)
		end

		-- remove any files
		local files = os.matchfiles(p .. "/*")
		for _, fname in ipairs(files) do
			os.remove(fname)
		end

		-- remove this directory
		builtin_rmdir(p)
	end

--
-- Remove a directory if it's empty, and any parents if they're empty too
--

	function os.rmdirParentsIfEmpty(p)
		if repoRoot then
			p = p:replace('$root', repoRoot)
		end

		local dirs = os.matchdirs(p .. "/*")
		local files = os.matchfiles(p .. "/*")
		
		if (#dirs == 0) and (#files == 0) then
			
			if( _OPTIONS['dryrun'] ) then
				if not removeList[p] then	
					print("rmdir " .. p )
				end
				removeList[p] = true
			else
				builtin_rmdir(p)
			end
			
			local parent = path.getdirectory(p)
			os.rmdirParentsIfEmpty(parent)
			return true
		end
		return false
	end
