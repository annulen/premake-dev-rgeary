--
-- Embed the Lua scripts into src/host/scripts.c as static data buffers.
-- I embed the actual scripts, rather than Lua bytecodes, because the 
-- bytecodes are not portable to different architectures, which causes 
-- issues in Mac OS X Universal builds.
--

	local function stripfile(fname)
		local f = io.open(fname)
		--local s = assert(f:read("*a"))
		--f:close()
		
		local s = ""
		-- replace error(msg, [level]) with error(fileLine, msg, [level])
		local lineNo = 0
		for line in f:lines() do
			lineNo = lineNo + 1
			local fileLine = fname..':'..tostring(lineNo)
			line = line:gsub("error[ ]*[(]", 'error("'..fileLine..' ",')
			s = s .. line .. '\n'
		end

		-- strip tabs
		s = s:gsub("[\t]", "")
		
		-- strip any CRs
		s = s:gsub("[\r]", "")
				
		-- strip out block comments
		s = s:gsub("[^\"']%-%-%[%[.-%]%]", "")
		s = s:gsub("[^\"']%-%-%[=%[.-%]=%]", "")
		s = s:gsub("[^\"']%-%-%[==%[.-%]==%]", "")

		-- strip out inline comments
		s = s:gsub("\n%-%-[^\n]*", "")
		
		-- escape backslashes
		s = s:gsub("\\", "\\\\")

		-- strip duplicate line feeds
		s = s:gsub("\n+", "\n")

		-- strip out leading comments
		s = s:gsub("^%-%-\n", "")

		-- escape line feeds
		s = s:gsub("\n", "\\n")
		
		-- escape double quote marks
		s = s:gsub("\"", "\\\"")
		
		return s
	end


	local function writeline(out, s, continues)
		out:write("\t\"")
		out:write(s)
		out:write(iif(continues, "\"\n", "\",\n"))
	end
	
	
	local function writefile(out, fname, contents)
		local max = 1024

		out:write("\t/* " .. fname .. " */\n")
		
		-- break up large strings to fit in Visual Studio's string length limit		
		local start = 1
		local len = contents:len()
		while start <= len do
			local n = len - start
			if n > max then n = max end
			local finish = start + n

			-- make sure I don't cut an escape sequence
			while contents:sub(finish, finish) == "\\" do
				finish = finish - 1
			end			

			writeline(out, contents:sub(start, finish), finish < len)
			start = finish + 1
		end		

		out:write("\n")
	end


	function doembed()
		-- load the manifest of script files
		scripts = dofile("src/_manifest.lua")
		
		-- main script always goes at the end
		table.insert(scripts, "_premake_main.lua")
		
		-- open scripts.c and write the file header
		local out = io.tmpfile()
		out:write("/* Premake's Lua scripts, as static data buffers for release mode builds */\n")
		out:write("/* DO NOT EDIT - this file is autogenerated - see BUILD.txt */\n")
		out:write("/* To regenerate this file, run: premake4 embed */ \n\n")
		out:write("const char* builtin_scripts[] = {\n")
		
		-- Write error wrapper
		out:write("/* Error handler */\n")
		out:write("\t\"local builtin_error = error\\nfunction error(fileLine, msg, level) builtin_error((fileLine or '')..msg, level or 0) end\\n\",\n\n")
		
		for i,fn in ipairs(scripts) do
			--print(fn)
			local s = stripfile("src/" .. fn)
			writefile(out, fn, s)
		end
		
		out:write("\t0\n};\n");		
		
		-- Test if the file has changed before writing it
		out:seek("set", 0)
		local newText = out:read("*a")
		out:close()

		local scriptsFile = io.open("src/host/scripts.c", "r")
		local oldText
		if scriptsFile then
			oldText = scriptsFile:read("*a")
			scriptsFile:close()
		end
		if newText ~= oldText then
			print("Writing scripts.c")
			scriptsFile = io.open("src/host/scripts.c", "w+b")
			scriptsFile:write(newText)
			scriptsFile:close()
		end
		
	end
