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
		
		if cfg.flags.Threading == 'Multi' then
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
	fixedFlags = 'rsc',
	extensionsForLinking = { '.o', '.a', },		-- possible inputs in to the linker
	redirectStderr = true,
	targetNamePrefix = 'lib',
	flagMap = {
		WholeArchive = "-Wl,--whole-archive",
	},
}
local gcc_link = newtool {
	toolName = 'link',
	binaryName = 'g++',
	fixedFlags = '-Wl,--start-group',
	extensionsForLinking = { '.o', '.a', '.so' },		-- possible inputs in to the linker
	flagMap = {
		Stdlib = {
			Shared		= '-shared-libgcc',
			Static		= '-static-libgcc -static-libstdc++',		-- Might not work, test final binary with ldd. See http://www.trilithium.com/johan/2005/06/static-libstdc/
		},
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
		
		if cfg.flags.Threading == 'Multi' then
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
