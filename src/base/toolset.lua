--
-- Toolset helper functions
--
--	Toolsets contain tools
--   Tools have a binary (toolset:getBinary)
--   Tools can have flags (toolget:getcmdflags), which can be set via self.sysflags.{arch/system} 
--		or by mapping to configuration flags (eg self.cflags)  
--   Tools can also have defines, includes and directly entered flags {buildoptions / linkoptions}

--  Toolsets do assume an abstract C++ style of compilation :
--	  There is an (optional) compile stage which converts each 'source file' in to an 'object file'
--	  There is an (optional) link stage which converts all "object files" in to a single "target file"
--	  No assumptions are made about "object file" or "target file", so this can be adapted to many uses
--
--  There is only one toolset per configuration
--	 If you have custom files which need a custom tool (eg. compiling .proto files), and you can't split
--	  in to two projects, then add it to the toolset

	premake.abstract.toolset = {}
	local toolset = premake.abstract.toolset
	premake.tools[''] = toolset		-- default
	
	-- Default is for C++ source, override this for other toolset types
	toolset.sourceFileExtensions = { ".cc", ".cpp", ".cxx", ".c", ".s", ".m", ".mm" }
	toolset.objectFileExtension = '.o'

--
-- Select a default toolset for the appropriate platform / source type
--

	function toolset:getdefault(cfg)	
	end
	
--
-- Construct toolInputs 
--
	function toolset:getToolInputs(cfg)
		local t = {}
		t.defines 		= cfg.defines
		t.includedirs 	= cfg.includedirs
		t.libdirs 		= cfg.libdirs
		t.systemlibs	= cfg.systemlibs
		t.buildoptions	= cfg.buildoptions
		t.default		= '$in'
		
		return t
	end

--
-- Toolset only provides "compile" and "link" features, but this allows 
--  for different tool names for different configurations
--	
	function toolset:getCompileTool(cfg)
	    if cfg.project.language == "C" then
		    return self.tools['cc']
		else
			return self.tools['cxx']
		end	    	
	end
	
	function toolset:getLinkTool(cfg)
	    if cfg.kind == premake.STATICLIB then
	    	return self.tools['ar']
	    else
	    	return self.tools['link']
	    end
	end
	
--
-- Get the object filename given the source filename. Returns null if it's not a recognised source file
--
	function toolset:getObjectFile(cfg, fileName, uniqueSet)
		-- .cpp -> .o
		if path.hasextension(fileName, self.sourceFileExtensions ) then
			local baseName = path.getbasename(fileName)
			local objName = baseName .. self.objectFileExtension
			
			-- Make sure the object file name is unique to avoid name collisions if two source files
			--  in different paths have the same filename
			
			if uniqueSet then
				for i=2,99999 do
					if not uniqueSet[objName] then break end
					objName = baseName .. tostring(i) .. self.objectFileExtension
				end
				uniqueSet[objName] = 1
			end
			return objName
		else
			return nil		-- don't process
		end		
	end

--
-- Returns true if this is an object file for the toolset
--
	function toolset:isObjectFile(cfg, fileName)
		return path.hasextension(fileName, { self.objectFileExtension })
	end
		
--[[	
--
-- Gets a sysflag as a single string
--
	
	function toolset:getsysflag(cfg, field)
		local rv = self:getsysflags(cfg, field, true)
		return rv
	end
	
-- 
-- Gets sysflags as a list
--

	function toolset:getsysflags(cfg, field, overrideNotMerge)
		local result = iif(overrideNotMerge, '', {})
		
		if( field == nil ) then
			error('field == nil, did you call getsysflags with . instead of :?')
		end
		
		if( self.sysflags == nil ) then
			error("toolset " .. type(self) .. " is missing sysflags table")
		end 
		
		-- merge/set default flags, then system-level flags, then architecture flags
		local layers = { (self.sysflags["default"]), (self.sysflags[cfg.system]), (self.sysflags[cfg.architecture]) }
		
		for _,flags in ipairs(layers) do
			-- merge in flags
			if flags then
				if( overrideNotMerge ) then
					if( flags[field] ) then 
						result = flags[field] 
					end
				else
					result = table.join(result, flags[field])
				end
			end
		end
		
		return result
	end

--
-- Returns a **table** of command line flags to pass to the tool
--
	function toolset:getcmdflags(cfg, toolName)
		if toolName == 'cpp' then
			-- Add flags from the configuration & flags from sysflags
			local flags = table.translate(cfg.flags, self.cppflags)
			flags = table.join(flags, self:getsysflags(cfg, 'cppflags'))
			return flags
		elseif toolName == 'cc' then
			local flags = table.translate(cfg.flags, self.cflags)
			flags = table.join(flags, self:getsysflags(cfg, 'cflags'))
			flags = table.join(flags, self:getcmdflags(cfg, 'cpp'))
			return flags
		elseif toolName == 'cxx' then
			local flags = table.translate(cfg.flags, self.cxxflags)
			flags = table.join(flags, self:getsysflags(cfg, 'cxxflags'))
			flags = table.join(flags, self:getcmdflags(cfg, 'cc'))
			return flags
		elseif toolName == 'link' then
			local flags = table.translate(cfg.flags, self.ldflags)
			flags = table.join(flags, self:getsysflags(cfg, 'ldflags'))
			return flags
		elseif toolName == 'ar' then
			local flags = table.translate(cfg.flags, self.ldflags)
			flags = table.join(flags, self:getsysflags(cfg, 'ldflags'))
			return flags
		else
			error('Unrecognised tool name ' .. tostring(toolName))
		end
	end
	
--
-- Returns a concat of all the compiler flags for the config
--
	function toolset:getcompilerflags(cfg)
		local flags = table.join(self:getcppflags(cfg), self:getcflags(cfg), self:getcxxflags(cfg))
		flags = table.join(flags, self:getdefines(cfg.defines), self:getincludedirs(cfg), cfg.buildoptions)
		return table.concat(flags, ' ')
	end
	
--
-- Abstract functions
--

	function toolset:getdefines(defines)
		error("toolset:getdefines not defined for " .. type(self))
	end

	function toolset:getincludedirs(cfg)
		error("toolset:getincludedirs not defined for " .. type(self))
	end
	
	function toolset:getresourcedirs(cfg)
		error("toolset:getresourcedirs not defined for " .. type(self))
	end

	function toolset:getlinks(cfg, systemonly)
		error("toolset:getlinks not defined for " .. type(self))
	end
	
--
-- Bring it all together in to a command line
--  eg. from make, call this with (cfg, 'cc', '$INCLUDES $DEFINES', '$@', '$<')
--  The toolset should override this if it wants to specify outputs & inputs differently on the command line
--   eg. for gcc, output is specified with "-o". For csc, it is "/out:"
--
	function toolset:getCommandLine(cfg, toolName, extraFlags, outputs, inputs)
		local toolCmd = self:getBinary(cfg, toolName)
		local cmdflags = table.concat( self:getcmdflags(cfg, toolName), ' ')
		
		local parts = { toolCmd, cmdflags, extraFlags, outputs, inputs }
		local cmd = table.concat(parts, ' ')
		return cmd
	end
	
--
-- Get the object filename given the source filename. Returns null if it's not a recognised source file
--
	function toolset:getObjectFile(cfg, sourceFileName)
		error('Not Implemented')
	end
	
--
-- Returns true if this is an object file for the toolset
--
	function toolset:isObjectFile(cfg, fileName)
		error('Not Implemented')
	end
]]
		