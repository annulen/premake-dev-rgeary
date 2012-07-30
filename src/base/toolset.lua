--
-- Toolset helper functions
--
--   A toolset (eg. gcc) should define the functions :
--   and the table
--	  sysflags, 

	premake.abstract.tools = {}
	local tools = premake.abstract.tools
	
--
-- Select a default toolset for the appropriate platform / source type
--

	function tools:getdefault(cfg)	
	end
	
--
-- Gets a sysflag as a single string
--
	
	function tools:getsysflag(cfg, field)
		rv = self:getsysflags(cfg, field, true)
		return rv
	end
	
-- 
-- Gets sysflags as a list
--

	function tools:getsysflags(cfg, field, overrideNotMerge)
		local result = {}
		
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

	function tools:getcppflags(cfg)
		local cppflags = self:getsysflags(cfg, 'cppflags')

		-- Add flags from the configuration
		cfgflags = table.translate(cfg.flags, self.cflags)
		cppflags = table.join(cppflags, cfgflags)

		return cppflags
	end
	
--
-- Returns list of C flags for a specific configuration.
--

	function tools:getcflags(cfg)
		local cflags = self:getsysflags(cfg, 'cflags')

		-- Add flags from the configuration
		cfgflags = table.translate(cfg.flags, self.cflags)
		cflags = table.join(cflags, cfgflags)

		return cflags
	end	
	
--
-- Returns list of C++ flags for a specific configuration.
--

	function tools:getcxxflags(cfg)
		local flags = table.translate(cfg.flags, self.cxxflags)
		flags = table.join(flags, self:getsysflags(cfg, 'cxxflags'))
		return flags
	end
	
--
-- Abstract functions
--

	function tools:getdefines(defines)
		error("tools:getdefines not undefined")
	end

	function tools:getincludedirs(defines)
		error("tools:getincludedirs not undefined")
	end
	
	function tools:getldflags(cfg)
		error("tools:getldflags not undefined")
	end
	
	function tools:getlinks(cfg, systemonly)
		error("tools:getlinks not undefined")
	end	