--
-- gcc.lua
-- Provides GCC-specific configuration strings.
-- Copyright (c) 2002-2012 Jason Perkins and the Premake project
--

--
-- GCC Compiler toolset
--
local atool = premake.abstract.buildtool 

local gcc_cc = newtool {
	toolName = 'cc',
	binaryName = 'gcc',
	fixedFlags = '-c -x c',
	language = "C",

	-- possible inputs in to the compiler
	extensionsForCompiling = { ".c", },
	
	flagMap = {
		AddPhonyHeaderDependency = "-MP",	 -- used by makefiles
		CreateDependencyFile = "-MMD",
		CreateDependencyFileIncludeSystem = "-MD",
		InlineDisabled = "-fno-inline",
		InlineExplicitOnly = "-inline-level=1",
		InlineAnything = "-finline-functions",
		EnableSSE2     = "-msse2",
		EnableSSE3     = "-msse3",
		EnableSSE41    = "-msse4.1",
		EnableSSE42    = "-msse4.2",
		EnableAVX      = "-mavx",
		ExtraWarnings  = "-Wall",
		FatalWarnings  = "-Werror",
		FloatFast      = "-mfast-fp",
		FloatStrict    = "-mfp-exceptions",
		OptimizeOff	   = "-O0",
		Optimize       = "-O2",
		OptimizeSize   = "-Os",
		OptimizeSpeed  = "-O3",
		OptimizeOff    = "-O0",
		Symbols        = "-g",
	},
	prefixes = {
		defines 		= '-D',
		includedirs 	= '-I',
		output			= '-o',
		depfileOutput   = '-MF',
	},
	suffixes = {
		depfileOutput   = '.d',
	},

	-- System specific flags
	getsysflags = function(self, cfg)
		local cmdflags = {}
		if cfg.system ~= premake.WINDOWS and cfg.kind == premake.SHAREDLIB then
			table.insert(cmdflags, '-fPIC')
		end
		
		if cfg.architecture == 'x32' then
			table.insert(cmdflags, '-m32')
		elseif cfg.architecture == 'x64' then
			table.insert(cmdflags, '-m64')
		end
		
		if cfg.flags.ThreadingMulti then
			if cfg.system == premake.LINUX then
				table.insert(cmdflags, '-pthread')
			elseif cfg.system == premake.WINDOWS then 
				table.insert(cmdflags, '-mthreads')
			elseif cfg.system == premake.SOLARIS then 
				table.insert(cmdflags, '-pthreads')
			end
		end
		
		return table.concat(cmdflags, ' ')
	end
}
local gcc_cxx = newtool {
	inheritFrom = gcc_cc,	
	toolName = 'cxx',
	language = "C++",
	binaryName = 'g++',
	fixedFlags = '-c -xc++',
	extensionsForCompiling = { ".cc", ".cpp", ".cxx", ".c" },
	flagMap = table.merge(gcc_cc.flagMap, {
		NoExceptions   = "-fno-exceptions",
		NoRTTI         = "-fno-rtti",
	})
}
local gcc_asm = newtool {
	inheritFrom = gcc_cxx,
	toolName = 'asm',
	language = "assembler",
	fixedFlags = '-c -x assembler-with-cpp',
	extensionsForCompiling = { '.s' },
	
	-- Bug in icc, only writes Makefile style depfiles. Just disable it.
	prefixes = table.exceptKeys(gcc_cxx.prefixes, { 'depfileOutput' }),
	suffixes = table.exceptKeys(gcc_cxx.suffixes, { 'depfileOutput' }),
	flagMap = table.exceptKeys(gcc_cxx.flagMap, { 'CreateDependencyFile', 'CreateDependencyFileIncludeSystem', }),
}
local gcc_ar = newtool {
	toolName = 'ar',
	binaryName = 'ar',
	fixedFlags = 'rc',
	extensionsForLinking = { '.o', '.a', },		-- possible inputs in to the linker
	redirectStderr = true,
	targetNamePrefix = 'lib',
}
local gcc_link = newtool {
	toolName = 'link',
	binaryName = 'g++',
	fixedFlags = '-Wl,--start-group',
	extensionsForLinking = { '.o', '.a', '.so' },		-- possible inputs in to the linker
	flagMap = {
		StdlibShared	= '-shared-libgcc',
		StdlibStatic	= '-static-libgcc -static-libstdc++',		-- Might not work, test final binary with ldd. See http://www.trilithium.com/johan/2005/06/static-libstdc/
	},
	prefixes = {
		libdirs 		= '-L',
		output 			= '-o',
		rpath			= '-Wl,-rpath=',
		linkoptions		= '',
	},
	suffixes = {
		input 			= ' -Wl,--end-group',
	},
	decorateFn = {
		linkAsStatic	= function(list) return atool.decorateLibList(list, '-Wl,-Bstatic', '-l'); end,
		linkAsShared	= function(list) return atool.decorateLibList(list, '-Wl,-Bdynamic', '-l'); end,
	},
	endFlags = '-Wl,-Bdynamic',	-- always put this at the end
	
	getsysflags = function(self, cfg)
		if cfg == nil then
			error('Missing cfg')
		end
		local cmdflags = {}
		
		if cfg.kind == premake.SHAREDLIB then
			if cfg.system == premake.MACOSX then
				table.insert(cmdflags, "-dynamiclib -flat_namespace")
			elseif cfg.system == premake.WINDOWS and not cfg.flags.NoImportLib then
				table.insert(cmdflags, '-shared -Wl,--out-implib="' .. cfg.linktarget.fullpath .. '"')
			else
				table.insert(cmdflags, "-shared")
			end
		end
		
		if cfg.flags.ThreadingMulti then
			if cfg.system == premake.SOLARIS then
				table.insert(cmdflags, '-pthread -lrt')
			elseif cfg.system == 'bsd' then
				table.insert(cmdflags, '-pthread -lrt')
			elseif cfg.system ~= premake.WINDOWS then
				table.insert(cmdflags, '-pthread -lrt')
			end
		end

		return table.concat(cmdflags, ' ')
	end	
}
newtoolset {
	toolsetName = 'gcc', 
	tools = { gcc_cc, gcc_cxx, gcc_ar, gcc_link },
}

--
-------------------------------------------------------------
--  All below can be deprecated
-------------------------------------------------------------
--
--[=[
premake.tools.gcc = {}
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
	NoWarnings     = "-w0",
	Optimize       = "-O2",
	OptimizeSize   = "-Os",
	OptimizeSpeed  = "-O3",
	OptimizeOff    = "-O0",
	Profiling      = "-pg",
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

--
-- Returns a **table** of command line flags to pass to the tool
--
function gcc:getcmdflags(cfg, toolName)
	local cmdflags = self.super.getcmdflags(self, cfg, toolName)
	
	if toolName == 'cc' then
		if cfg.system ~= premake.WINDOWS and cfg.kind == premake.SHAREDLIB then
			table.insert(cmdflags, "-fPIC")
		end
	elseif( toolName == 'link' ) then
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
]=]