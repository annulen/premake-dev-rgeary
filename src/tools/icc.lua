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
	
	getsysflags = function(cfg)
		cmdflags = ''
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
	binaryName = 'xiar rc',  -- put rc in the binary name as it must come first
	redirectStderr = true,
}
local icc_link = newtool {
	toolName = 'link',
	binaryName = 'icpc',
	flagMap = {
		ThreadingMulti 	= '-pthread',
		StdlibShared	= '-shared-libgcc -static-intel',
		StdlibStatic	= '-static-libgcc -shared-intel',		-- Might not work, test final binary with ldd. See http://www.trilithium.com/johan/2005/06/static-libstdc/
	},
	prefixes = {
		systemlibs 		= '-l',
		libdirs 		= '-L',
		linkAsStatic 	= '-Wl,-Bstatic',
		linkAsShared 	= '-Wl,-Bdynamic',
		output 			= '-o',
	},
	decorateFn = {
		input = function(inputList) return '-Wl,--start-group ' .. table.concat(inputList, ' ') .. ' -Wl,--end-group'; end
	},
	
	getsysflags = function(cfg)
		cmdflags = ''
		if cfg.kind == premake.SHAREDLIB then
			if cfg.system == premake.MACOSX then
				cmdflags = "-dynamiclib -flat_namespace"
			elseif cfg.system == premake.WINDOWS and not cfg.flags.NoImportLib then
				cmdflags ='-shared -Wl,--out-implib="' .. cfg.linktarget.fullpath .. '"'
			else
				cmdflags = "-shared"
			end
		end
		return cmdflags
	end	
}
newtoolset {
	toolsetName = 'icc', 
	tools = { icc_cc, icc_cxx, icc_ar, icc_link },
}

--[[
premake.tools.icc = inheritFrom(premake.abstract.toolset, 'icc')
local tools = premake.tools
local icc = premake.tools.icc
local config = premake5.config
local project = premake5.project
local gcc = premake.tools.gcc

icc.tooldir = nil

icc.sysflags = {
	default = {
		cc = "icpc -xc -c",
		cxx = "icpc -xc++ -c",
		link = "icpc",
		ar = "xiar rc",
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
	ThreadingMulti = "-pthread",
}
icc.cxxflags = {
	NoExceptions   = "-fno-exceptions",
	NoRTTI         = "-fno-rtti",
}
icc.ldflags = {
	ThreadingMulti = '-pthread',
	StdlibShared   = '-shared-libgcc',
	StdlibStatic   = '-static-libgcc',		-- Might not work, test final binary with ldd. See http://www.trilithium.com/johan/2005/06/static-libstdc/
}

-- Same as gcc		
icc.getdefines = gcc.getdefines					-- convert define list in to compiler command line flags
icc.getincludedirs = gcc.getincludedirs			-- convert include list in to compiler command line flags
icc.getresourcedirs = gcc.getresourcedirs		-- convert resource dir list in to compiler command line flags
icc.getlinks = gcc.getlinks						-- convert library list in to linker command line flags

--
-- Returns a **table** of command line flags to pass to the tool
--
function icc:getcmdflags(cfg, toolName)
	local cmdflags = self.super.getcmdflags(self, cfg, toolName)
	
	if toolName == 'cc' then
		if cfg.system ~= premake.WINDOWS and cfg.kind == premake.SHAREDLIB then
			table.insert(cmdflags, "-fPIC")
		end
	elseif( toolName == 'link' ) then
		-- Scan the list of linked libraries. If any are referenced with
		-- paths, add those to the list of library search paths
		for _, dir in ipairs(config.getlinks(cfg, "all", "directory")) do
			table.insert(cmdflags, '-L' .. dir)
		end
		
		if cfg.system ~= 'linux' then
			print('icc with ' .. cfg.system .. ' is untested')
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
	end
	
	return cmdflags
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

--
-- Bring it all together in to a command line
--  eg. from make, call this with (cfg, 'cc', '$INCLUDES $DEFINES', '$@', '$<')
--  The toolset should override this if it wants to specify outputs & inputs differently on the command line
--   eg. for gcc, output is specified with "-o". For csc, it is "/out:"
--
	function icc:getCommandLine(cfg, toolName, extraFlags, outputs, inputs)
		local toolCmd = self:getBinary(cfg, toolName)
		local cmdflags = table.concat( self:getcmdflags(cfg, toolName), ' ')
		local parts
		
		if toolName ~= 'ar' then
			parts = { toolCmd, cmdflags, extraFlags, '-o '..outputs, inputs }
		else
			parts = { toolCmd, cmdflags, extraFlags, outputs, inputs }
		end
		
		local cmd = table.concat(parts, ' ')
		return cmd
	end

]]