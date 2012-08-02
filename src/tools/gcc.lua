--
-- gcc.lua
-- Provides GCC-specific configuration strings.
-- Copyright (c) 2002-2012 Jason Perkins and the Premake project
--

premake.tools.gcc = inheritFrom(premake.abstract.toolset, 'gcc')
local gcc = premake.tools.gcc
local project = premake5.project
local config = premake5.config

--
-- GCC flags for specific systems and architectures.
--

gcc.sysflags = {
	default = {
		cc = "g++",
		cxx = "g++",
		ar = "ar",
		cppflags = "-MMD",
	},

	haiku = {
	},

	x32 = {
		cflags  = "-m32",
		ldflags = { "-m32", "-L/usr/lib32" }
	},

	x64 = {
		cflags = "-m64",
		ldflags = { "-m64", "-L/usr/lib64" }
	},

	ps3 = {
		cc = "ppu-lv2-g++",
		cxx = "ppu-lv2-g++",
		ar = "ppu-lv2-ar",
	},

	universal = {
	},

	wii = {
		cppflags = "-I$(LIBOGC_INC) $(MACHDEP)",
		ldflags	= "-L$(LIBOGC_LIB) $(MACHDEP)",
		cfgsettings = [[
		ifeq ($(strip $(DEVKITPPC)),)
		$(error "DEVKITPPC environment variable is not set")'
		endif
		include $(DEVKITPPC)/wii_rules']],
	},
}

--
-- C PreProcessor Flag mappings
--
gcc.cppflags = {
	AddPhonyHeaderDependency = "-MP",	 -- used by makefiles
	CreateDependencyFile = "-MMD",
	CreateDependencyFileIncludeSystem = "-MD",
}

--
-- C flag mappings
--

gcc.cflags = {
	EnableSSE      = "-msse",
	EnableSSE2     = "-msse2",
	ExtraWarnings  = "-Wall -Wextra",
	FatalWarnings  = "-Werror",
	FloatFast      = "-ffast-math",
	FloatStrict    = "-ffloat-store",
	NoFramePointer = "-fomit-frame-pointer",
	Optimize       = "-O2",
	OptimizeSize   = "-Os",
	OptimizeSpeed  = "-O3",
	OptimizeOff    = "-O0",
	Symbols        = "-g",
	ThreadingMulti = "-pthread",
}

--
-- CXX (C++) Flag mappings
--

gcc.cxxflags = {
	NoExceptions   = "-fno-exceptions",
	NoRTTI         = "-fno-rtti",
}

-- Linker flag mappings
gcc.ldflags = {
	ThreadingMulti = '-pthread',
	StdlibShared   = '-shared-libgcc',
	StdlibStatic   = '-static-libgcc -static-stdlibc++',
}

--
-- Decorate defines for the GCC command line.
--

function gcc:getdefines(defines)
	local result = {}
	for _, define in ipairs(defines) do
		table.insert(result, '-D' .. define)
	end
	return result
end

--
-- Decorate include file search paths for the GCC command line.
--

function gcc:getincludedirs(cfg)
	local result = {}
	local dirs = cfg.includedirs or {}
	for _, dir in ipairs(dirs) do
		table.insert(result, "-I" .. project.getrelative(cfg.project, dir))
	end
	
	return result
end

--
-- Decorate resource file search paths for the GCC command line.
--
function gcc:getresourcedirs(cfg)
	local result = {}
	local dirs = cfg.resourcedirs or {}
	for _, dir in ipairs(dirs) do
		table.insert(result, "-I" .. project.getrelative(cfg.project, dir))
	end
	return result
end

function gcc:getcmdflags(cfg, toolName)
	local cmdflags = self.super.getcmdflags(cfg, toolName)
	
	if toolName == 'cc' then
		if cfg.system ~= premake.WINDOWS and cfg.kind == premake.SHAREDLIB then
			table.insert(cmdflags, "-fPIC")
		end
	else if( toolName == 'link' ) then
		-- Return a list of LDFLAGS for a specific configuration.
	
		-- Scan the list of linked libraries. If any are referenced with
		-- paths, add those to the list of library search paths
		for _, dir in ipairs(config.getlinks(cfg, "all", "directory")) do
			table.insert(cmdflags, '-L' .. dir)
		end
	
		if not cfg.flags.Symbols then
			-- OS X has a bug, see http://lists.apple.com/archives/Darwin-dev/2006/Sep/msg00084.html
			if cfg.system == premake.MACOSX then
				table.insert(cmdflags, "-Wl,-x")
			else
				table.insert(cmdflags, "-s")
			end
		end
	
		if cfg.kind == premake.SHAREDLIB then
			if cfg.system == premake.MACOSX then
				cmdflags = table.join(cmdflags, { "-dynamiclib", "-flat_namespace" })
			else
				table.insert(cmdflags, "-shared")
			end
	
			if cfg.system == "windows" and not cfg.flags.NoImportLib then
				table.insert(cmdflags, '-Wl,--out-implib="' .. cfg.linktarget.fullpath .. '"')
			end
		end
	
		if cfg.kind == premake.WINDOWEDAPP and cfg.system == premake.WINDOWS then
			table.insert(cmdflags, "-mwindows")
		end
	end
	
	return cmdflags
end


--
-- Return the list of libraries to link, decorated with flags as needed.
--

function gcc:getlinks(cfg, systemonly)
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
				 	-- Don't use path when linking shared libraries, otherwise loader will always expect the same
				 	-- folder structure
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

