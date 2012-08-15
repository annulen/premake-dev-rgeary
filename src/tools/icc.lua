--
-- Intel Compiler toolset
--


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
		ThreadingMulti = "-pthread",
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
	
	getsysflags = function(self, cfg)
		local cmdflags = ''
		if cfg.system ~= premake.WINDOWS and cfg.kind == premake.SHAREDLIB then
			cmdflags = '-fPIC'
		end
		return cmdflags
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
local function decorateLibList(list, startPrefix, systemlibPrefix)
	if not list or #list == 0 then
		return ''
	else
		local s = startPrefix
		for _,lib in ipairs(list) do
			if path.containsSlash(lib) then
				s = s..' '..lib
			else
				s = s..' '..systemlibPrefix..lib
			end
		end
		return s
	end
end
local icc_link = newtool {
	toolName = 'link',
	binaryName = 'icpc',
	fixedFlags = '-Wl,--start-group',
	flagMap = {
		ThreadingMulti 	= '-pthread',
		StdlibShared	= '-shared-libgcc -static-intel',
		StdlibStatic	= '-static-libgcc -shared-intel',		-- Might not work, test final binary with ldd. See http://www.trilithium.com/johan/2005/06/static-libstdc/
	},
	prefixes = {
		libdirs 		= '-L',
		output 			= '-o',
	},
	suffixes = {
		input 			= ' -Wl,--end-group',
	},
	decorateFn = {
		linkAsStatic	= function(list) return decorateLibList(list, '-Wl,-Bstatic', '-l'); end,
		linkAsShared	= function(list) return decorateLibList(list, '-Wl,-Bdynamic', '-l'); end,
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
			local rpath = iif( intelLibDir, '-Wl,-rpath='..intelLibDir, '')
			table.insert(cmdflags, rpath)
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
