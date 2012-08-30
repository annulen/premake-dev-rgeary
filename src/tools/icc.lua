--
-- Intel Compiler toolset
--
local atool = premake.abstract.buildtool

local icc_cc = newtool {
	toolName = 'cc',
	binaryName = 'icpc',
	fixedFlags = '-xc -c',
	flagMap = {
		AddPhonyHeaderDependency = "-MP",	 -- used by makefiles
		CreateDependencyFile = "-MMD",
		CreateDependencyFileIncludeSystem = "-MD",
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
local icc_cxx = newtool {
	inheritFrom = icc_cc,
	toolName = 'cxx',
	fixedFlags = '-xc++ -c',
	flagMap = table.merge(icc_cc, {
		NoExceptions   = "-fno-exceptions",
		NoRTTI         = "-fno-rtti",
	})
}
local icc_ar = newtool {
	toolName = 'ar',
	binaryName = 'xiar',
	fixedFlags = 'rc',
	redirectStderr = true,
	targetNamePrefix = 'lib',
}
local icc_link = newtool {
	toolName = 'link',
	binaryName = 'icpc',
	fixedFlags = '-Wl,--start-group',
	flagMap = {
		StdlibShared	= '-shared-libgcc -shared-intel',
		StdlibStatic	= '-static-libgcc -static-intel',		-- Might not work, test final binary with ldd. See http://www.trilithium.com/johan/2005/06/static-libstdc/
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
		
		if cfg.kind == premake.CONSOLEAPP then
			local intelLibDir = os.findlib('imf') 		-- Intel default libs
			if not intelLibDir then
				error('Unable to find libimf')
			end
			local rpath = iif( intelLibDir, '-Wl,-rpath='..intelLibDir, '')
			table.insert(cmdflags, rpath)
		end
		

		if cfg.flags.ThreadingMulti then
			if cfg.system ~= premake.WINDOWS then
				table.insert(cmdflags, '-pthread -lrt')
			end
		end

		return table.concat(cmdflags, ' ')
	end	
}
newtoolset {
	toolsetName = 'icc', 
	tools = { icc_cc, icc_cxx, icc_ar, icc_link },
}
newtoolset {
	toolsetName = 'icc12', 
	tools = { 
		newtool {
			inheritfrom = icc_cc,
			binaryName = 'icpc12',
		},
		newtool {
			inheritfrom = icc_cxx,
			binaryName = 'icpc12',
		},
		newtool {
			inheritfrom = icc_ar,
			binaryName = 'xiar12',
		},
		newtool {
			inheritfrom = icc_link,
			binaryName = 'icpc12',
		},
	}
}
newtoolset {
	toolsetName = 'icc11.1', 
	tools = { 
		newtool {
			inheritfrom = icc_cc,
			binaryName = 'icpc11.1',
		},
		newtool {
			inheritfrom = icc_cxx,
			binaryName = 'icpc11.1',
		},
		newtool {
			inheritfrom = icc_ar,
			binaryName = 'xiar11.1',
		},
		newtool {
			inheritfrom = icc_link,
			binaryName = 'icpc11.1',
		},
	}
}
