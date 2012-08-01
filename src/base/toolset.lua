--
-- Toolset helper functions
--
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
		if not toolname then
			error("No tool name specified, can't find binary")
		end
		
		-- Get the name of the binary from the toolname
		
		local toolbin = self:getsysflag(cfg, toolname)
		if toolbin == nil or toolbin == ''  then
			
			-- Special default case for linker, use the C / C++ binary instead
			if toolname == 'link' then
				local cc = iif(cfg.project.language == "C", "cc", "cxx")
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
-- Returns list of CPPFLAGS (C PreProcessor flags) for a specific configuration.
--

	function toolset:getcppflags(cfg)
		local cppflags = self:getsysflags(cfg, 'cppflags')

		-- Add flags from the configuration
		local cfgflags = table.translate(cfg.flags, self.cppflags)
		cppflags = table.join(cppflags, cfgflags)

		return cppflags
	end
	
--
-- Returns list of C flags for a specific configuration.
--

	function toolset:getcflags(cfg)
		local cflags = self:getsysflags(cfg, 'cflags')

		-- Add flags from the configuration
		local cfgflags = table.translate(cfg.flags, self.cflags)
		cflags = table.join(cflags, cfgflags)

		return cflags
	end	
	
--
-- Returns list of C++ flags for a specific configuration.
--

	function toolset:getcxxflags(cfg)
		local flags = table.translate(cfg.flags, self.cxxflags)
		flags = table.join(flags, self:getsysflags(cfg, 'cxxflags'))
		return flags
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

	function toolset:getldflags(cfg)
		local flags = table.translate(cfg.flags, self.ldflags)
		return flags
	end
	
	function toolset:getlinks(cfg, systemonly)
		error("toolset:getlinks not defined for " .. type(self))
	end	