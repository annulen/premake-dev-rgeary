--
-- Intel Compiler toolset
--

	premake.tools.icc = inheritFrom(premake.abstract.toolset, 'icc')
	local tools = premake.tools
	local icc = premake.tools.icc
	local config = premake5.config
	local project = premake5.project
	local gcc = premake.tools.gcc

	icc.tooldir = nil
	
	icc.sysflags = {
		default = {
			cc = "icpc -xc",
			cxx = "icpc -xc++",
			link = "icpc",
			ar = "xiar",
			cppflags = "-MMD"
		},
	}

	icc.cppflags = {
		AddPhonyHeaderDependency = "-MP",	 -- used by makefiles
		CreateDependencyFile = "-MMD",
		CreateDependencyFileIncludeSystem = "-MD",
	}
	icc.cflags = {
		InlineDisabled = "-inline-level=0",
		InlineExplicitOnly = "-inline-level=1",
		InlineAnything = "-inline-level=2",
		EnableSSE2     = "-msse2",
		EnableSSE3     = "-msse3",
		EnableSSE41    = "-msse4.1",
		EnableSSE42    = "-msse4.2",
		EnableAVX      = "-mavx",
		ExtraWarnings  = "-Wall",
		FatalWarnings  = "-Werror",
		FloatFast      = "-fp-model fast=2",
		FloatStrict    = "-fp-model strict",
		OptimizeOff	   = "-O0",
		Optimize       = "-O2",
		OptimizeSize   = "-Os",
		OptimizeSpeed  = "-O3",
		OptimizeOff    = "-O0",
		Symbols        = "-g",
		ThreadingMulti = "-pthreads",
	}
	icc.cxxflags = {
		NoExceptions   = "-fno-exceptions",
		NoRTTI         = "-fno-rtti",
	}

	-- Same as gcc		
	icc.getdefines = gcc.getdefines
	icc.getincludedirs = gcc.getincludedirs
	icc.getcppflags = gcc.getcppflags
	icc.getcflags = gcc.getcflags
	icc.getcxxflags = gcc.getcxxflags
	icc.getresourcedirs = gcc.getresourcedirs
	icc.getlinks = gcc.getlinks
	
	function icc:getldflags(cfg)
		local flags = {}
		
		-- Scan the list of linked libraries. If any are referenced with
		-- paths, add those to the list of library search paths
		for _, dir in ipairs(config.getlinks(cfg, "all", "directory")) do
			table.insert(flags, '-L' .. dir)
		end
		
		if cfg.system ~= 'linux' then
			print('icc with ' .. cfg.system .. ' is untested')
		end
		
		if cfg.kind == premake.SHAREDLIB then
			if cfg.system == premake.MACOSX then
				flags = table.join(flags, { "-dynamiclib", "-flat_namespace" })
			else
				table.insert(flags, "-shared")
			end

			if cfg.system == "windows" and not cfg.flags.NoImportLib then
				table.insert(flags, '-Wl,--out-implib="' .. cfg.linktarget.fullpath .. '"')
			end
		end
	
		local sysflags = icc:getsysflags(cfg, 'ldflags')
		flags = table.join(flags, sysflags)
		
		return flags
		
	end
	
	function icc:getlinks(cfg, systemonly)
		local result = {}
		
		local links
		if not systemonly then
			links = config.getlinks(cfg, "siblings", "object")
			for _, link in ipairs(links) do
				-- skip external project references, since I have no way
				-- to know the actual output target path
				if not link.project.externalname then
					if link.kind == premake.STATICLIB then
						-- Don't use "-l" flag when linking static libraries; instead use 
						-- path/libname.a to avoid linking a shared library of the same
						-- name if one is present
						table.insert(result, project.getrelative(cfg.project, link.linktarget.abspath))
					else
						table.insert(result, "-l" .. link.linktarget.basename)
					end
				end
			end
		end
				
		-- The "-l" flag is fine for system libraries
		links = config.getlinks(cfg, "system", "basename")
		for _, link in ipairs(links) do
			if path.isframework(link) then
				table.insert(result, "-framework " .. path.getbasename(link))
			elseif path.isobjectfile(link) then
				table.insert(result, link)
			else
				table.insert(result, "-l" .. link)
			end
		end
		
		return result
	end
	
	