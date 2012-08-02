--
-- Toolset helper functions
--
--	Toolsets contain tools
--   Tools have a binary (toolset:getBinary)
--   Tools can have flags (toolget:getcmdflags), which can be set via self.sysflags.{arch/system} 
--		or by mapping to configuration flags (eg self.cflags)  
--   Tools can also have defines, includes and directly entered flags {buildoptions / linkoptions}


--   A toolset (eg. gcc) should define the functions :
--   and the table
--	  sysflags, 

	premake.abstract.toolset = {}
	local toolset = premake.abstract.toolset
	
	toolset.tooldir = nil
		
--
-- Get tool binary path
--
	function toolset:getBinary(cfg, toolname)
		if type(cfg) ~= 'table' then
			error("toolset:getBinary : No config specified ")
		end
		if not toolname then
			error("toolset:getBinary : No tool name specified")
		end
		
		-- Get the name of the binary from the toolname
		
		local toolbin = self:getsysflag(cfg, toolname)
		if toolbin == nil or toolbin == ''  then
			
			-- Special default case for linker, use the C / C++ binary instead
			if toolname == 'link' then
				local cc = iif(cfg.projectcfg.project.language == "C", "cc", "cxx")
				return self:getBinary(cfg, cc)
			else
				return nil
			end
			
		else
		 	-- Find the binary
		 	
			local path = os.findbin(toolbin, self.tooldir)
			local fullpath
			if path then
				fullpath = path .. '/' .. toolbin
			else
				fullpath = toolbin
			end
			return fullpath
		end
	end
		
--
-- Select a default toolset for the appropriate platform / source type
--

	function toolset:getdefault(cfg)	
	end
	
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
-- Returns flags to pass to the tool at the the command line
--
	toolset.getflags = {}

	function toolset:getflags(cfg, toolName)
		local toolsysflags = 
		if toolName == 'cpp' then
			-- Add flags from the configuration & flags from sysflags
			local cfgflags = table.translate(cfg.flags, self.cppflags)
			cppflags = table.join(cfgflags, self:getsysflags(cfg, 'cppflags'))

			return cppflags
		elseif toolName == 'cc' then
			local cfgflags = table.translate(cfg.flags, self.cflags)
			cflags = table.join(cfgflagsm, self:getsysflags(cfg, 'cflags'))
	
			return cflags
		else if toolName == 'cxx' then
			local flags = table.translate(cfg.flags, self.cxxflags)
			flags = table.join(flags, self:getsysflags(cfg, 'cxxflags'))
			return flags
		else if toolName == 'link' then
			local flags = table.translate(cfg.flags, self.ldflags)
			flags = table.join(flags, self:getsysflags(cfg, 'ldflags'))
			return flags
		else
			error('Unrecognised tool name ' .. toolName)
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
		local cmdflags = toolset.getcmdflags[toolname](self, cfg)
		
		local parts = { toolCmd, cmdflags, extraFlags, outputs, inputs }
		local cmd = table.concat(parts, ' ')
		return cmd
	end