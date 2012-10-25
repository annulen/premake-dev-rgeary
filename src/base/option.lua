--
-- option.lua
-- Work with the list of registered options.
-- Copyright (c) 2002-2009 Jason Perkins and the Premake project
--

	premake.option = { }


--
-- The list of registered options.
--

	premake.option.list = { }
	premake.option.aliases = { }
	

--
-- Register a new option.
--
-- @param opt
--    The new option object.
-- 

	function premake.option.add(opt)
		-- some sanity checking
		local missing
		for _, field in ipairs({ "description", "trigger" }) do
			if (not opt[field]) then
				missing = field
			end
		end
		
		if (missing) then
			error("option needs a " .. missing, 3)
		end
		
		-- add it to the master list
		premake.option.list[opt.trigger] = opt
		premake.option.list[opt.trigger:lower()] = opt

		-- one letter aliases
		if opt.aliases then		
			for _,a in ipairs(opt.aliases) do
				premake.option.aliases[a] = opt
			end
		end
	end


--
-- Retrieve an option by name.
--
-- @param name
--    The name of the option to retrieve.
-- @returns
--    The requested option, or nil if the option does not exist.
--

	function premake.option.get(name)
		return premake.option.list[name] or premake.option.aliases[name]
	end


--
-- Iterator for the list of options.
--

	function premake.option.each()
		-- sort the list by trigger
		local keys = { }
		for _, option in pairs(premake.option.list) do
			table.insert(keys, option.trigger)
		end
		table.sort(keys)
		
		local i = 0
		return function()
			i = i + 1
			return premake.option.list[keys[i]]
		end
	end


--
-- Validate a list of user supplied key/value pairs against the list of registered options.
--
-- @returns
---   True if the list of pairs are valid, false and an error message otherwise.
--

	function premake.option.validate()
		local newOptions = {}
		local opts = _OPTIONS

		for key, value in pairs(_OPTIONS) do
			-- does this option exist
			local opt = premake.option.get(key)
			if (not opt) then
				return false, "invalid option '" .. key .. "'"
			end
			-- also register lower case trigger
			newOptions[key] = _OPTIONS[key]
			newOptions[key:lower()] = newOptions[key]
			-- reregister .trigger in the table in case the option is an alias
			newOptions[opt.trigger] = _OPTIONS[opt.trigger] or _OPTIONS[key]
		end
		_OPTIONS = newOptions
		
		for key, value in pairs(_OPTIONS) do
			local opt = premake.option.get(key)
			-- does it need a value?
			if (opt.value and string.sub(opt.value,1,1) ~= '[' and value == "") then
				return false, "no value specified for option '" .. key .. "'"
			end
			
			-- is the value allowed?
			if (opt.allowed) then
				for _, match in ipairs(opt.allowed) do
					if (match[1] == value) then return true end
				end
				return false, "invalid value '" .. value .. "' for option '" .. key .. "'"
			end
		end
		return true
	end
