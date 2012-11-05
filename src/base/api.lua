
--
-- api.lua
-- Implementation of the solution, project, and configuration APIs.
-- Copyright (c) 2002-2012 Jason Perkins and the Premake project
--

	premake.api = {}
	local api = premake.api
	local globalContainer = premake5.globalContainer
	local targets = premake5.targets
	local config = premake5.config

--
-- Here I define all of the getter/setter functions as metadata. The actual
-- functions are built programmatically below.
--
-- Note that these are deprecated in favor of the api.register() calls below,
-- and will be going away as soon as I have a chance to port them.
--

-- isList 			true if it's an list of unique objects (unordered)
-- allowDuplicates	(obsolete) Allow duplicate values, order dependent
-- isKeyedTable 	Values are in a keyed table. Multiple tables with the same key will overwrite the value.

--	kind			Description						Comments
---------------------------------------------------------
--  string			A string value		
--  path			A single path 					Paths are converted to absolute
--  directory		A list of paths					Can contain wildcards
--  file			A list of files					Can contain wildcards
--  key-array		A keyed table					
--  object			A table							overwrite on multiple instances

-- Modifiers :
--  uniqueValues			The final list will contain only unique elements
--  splitOnSpace 			If the field value contains a space, treat it as an array of two values. eg "aaa bbb" => { "aaa", "bbb" }
--  isConfigurationKeyword	The value to this field will automatically be added to the filter list when evaluating xxx in 'configuration "xxx"' statements
--  expandtokens			The value can contain tokens, eg. %{cfg.shortname}
--  usagePropagation		Possible values : WhenStaticLib, WhenSharedOrStaticLib, Always, (function) 
--							When project 'B' uses project 'A', anything in project A's usage requirements will be copied to project B
--		WhenStaticLib			This field is propagated automatically from a project 'A' to project A's usage if A has kind="StaticLib". Used for linkAsStatic
--		WhenSharedOrStaticLib	This field is propagated automatically from a project 'A' to project A's usage if A has kind="StaticLib" or kind="SharedLib". Used for linkAsShared  
--		Always			This field will always be propagaged to the usage requirement. Used for implicit compile dependencies
--		(function)		Propagates the return value of function(cfg, value), if not nil 
	
	premake.fields = {}
	premake.propagatedFields = {}
	premake.fieldAliases = {}


--
-- A place to store the current active objects in each project scope.
--

	api.scope = {}


--
-- Register a new API function. See the built-in API definitions below
-- for usage examples.
--

	function api.register(field)
		-- verify the name
		local name = field.name
		if not name then
			error("missing name", 2)
		end

		-- Create the list of aliases
		local names = { field.name }
		if field.namealiases then
			names = table.join(names, field.namealiases)
		end
		
		if field.kind:startswith("key-") then
			field.kind = field.kind:sub(5)
			field.isKeyedTable = true
		end
		if field.kind:endswith("-list") then
			field.kind = field.kind:sub(1, -6)
			field.isList = true
		end

		for _,n in ipairs(names) do
			if rawget(_G,n) then
				error('name '..n..' in use', 2)
			end
			
			-- add create a setter function for it
			_G[n] = function(value)
				return api.callback(field, value)
			end
			
			-- list values also get a removal function
			if field.isList and not field.isKeyedTable then
				_G["remove" .. n] = function(value)
					return api.remove(field, value)
				end
			end
			
			-- all fields get a usage function, which allows you to quickly specify usage requirements
			_G["usage" .. n] = function(value)
				-- Activate a usage project of the same name & configuration as we currently have
				--  then apply the callback 
				local activePrjSln = api.scope.project or api.scope.solution
				local prjName = activePrjSln.name
				local cfgTerms = (api.scope.configuration or {}).terms
				local rv
				
				api.scopepush()
				usage(prjName)
					configuration(cfgTerms)
					rv = api.callback(field, value)
				api.scopepop()
				
				return rv
			end
		end
		
		-- Pre-process the allowed list in to a lower-case set
		if field.allowed then 
			if type(field.allowed) ~= 'function' then
			
				local allowedSet = {}
				if type(field.allowed) == 'string' then
					local v = field.allowed
					allowedSet[v:lower()] = v
				else
					for k,v in pairs(field.allowed) do
						if type(k) == 'number' then
							allowedSet[v:lower()] = v
						else
							if type(v) == 'table' then
								-- specific options
								for _,v2 in ipairs(v) do
									allowedSet[k:lower() ..'='.. v2:lower()] = k ..'='.. v2
								end
							else
								-- no options specified
								allowedSet[k:lower() ..'='.. v:lower()] = k ..'='.. v
							end
						end
					end
				end
				
				field.allowedList = field.allowed
				field.allowed = allowedSet
			end
		end

		-- Pre-process aliases
		if field.aliases then
			local aliases = {}
			for k,v in pairs(field.aliases) do
				-- case insensitive
				k = k:lower()
				v = v:lower()
				aliases[k] = v				
				premake.fieldAliases[k] = v
			end
			field.aliases = aliases
		end

		-- make sure there is a handler available for this kind of value
		if not api["set" .. field.kind] then
			error("invalid kind '" .. kind .. "'", 2)
		end
					
		-- add this new field to my master list
		premake.fields[field.name] = field
		
		if field.usagePropagation then
			premake.propagatedFields[field.name] = field 
		end
	end


--
-- Find the right target object for a given scope.
--

	function api.gettarget(scope)
		local target
		if scope == "global" then
			target = globalContainer.solution
		elseif scope == "solution" then
			target = api.scope.solution
		elseif scope == "project" then
			target = api.scope.project or api.scope.solution
		else
			target = api.scope.configuration
		end
		
		if not target then
			error("no " .. scope .. " in scope", 4)
		end
		
		return target
	end

--
-- Push the current scope on to a stack
--
	api.scopeStack = {}
	function api.scopepush()
		local s = {
			solution 			 = api.scope.solution,
			project 			 = api.scope.project,
			configuration 		 = api.scope.configuration,
			currentContainer 	 = premake.CurrentContainer,
			currentConfiguration = premake.CurrentConfiguration,  			
		}
		table.insert( api.scopeStack, s )
	end

--
-- Pop a scope from the stack
--
	function api.scopepop()
		if #api.scopeStack < 1 then
			error('No scope to pop')
		end
		api.scope = table.remove( api.scopeStack )
		premake.CurrentContainer = api.scope.currentContainer
		premake.CurrentConfiguration = api.scope.currentConfiguration
	end

--
-- Callback for all API functions; everything comes here first, and then
-- parceled out to the individual set...() functions.
--

	function api.callback(field, value)
		-- right now, ignore calls with no value; later might want to
		-- return the current baked value
		if not value then return end
		
		if type(value) == 'table' and count(value)==0 then
			error("Can't set \"" .. field.name .. '\" with value {} - did you forget to add quotes around the value? ')
		end
		
		local target = api.gettarget(field.scope)
		
		-- fields with this property will allow users to customise using "configuration <value>"
		if field.isConfigurationKeyword then
			local useValue
			if type(value) == 'table' then
				-- if you have a keyed table, eg. flags, convert it in to a table in the form key = "key=value"
				useValue = {}
				for k,v in pairs(value) do
					if premake.fieldAliases[v:lower()] then
						v = premake.fieldAliases[v:lower()]
					end
					
					if type(k) == 'number' then
						table.insert(useValue, tostring(v))
					else
						useValue[k:lower()] = k..'='..tostring(v)
					end
				end
			else
				if premake.fieldAliases[value] then
					value = premake.fieldAliases[value]
				end
				useValue = { [field.name] = value }
			end
			
			config.registerkey(field.name, useValue)
			api.callback(premake.fields['usesconfig'], useValue)
		end

		-- Custom field setter		
		if field.setter then
			field.setter(target, field.name, field, value)
			
		-- A keyed value is a table containing key-value pairs, where the
		-- type of the value is defined by the field. 
		elseif field.isKeyedTable then
			target[field.name] = target[field.name] or {}
			api.setkeyvalue(target[field.name], field, value)
		
		-- Lists is an array containing values of another type
		elseif field.isList then
			api.setlist(target, field.name, field, value)
			
		-- Otherwise, it is a "simple" value defined by the field
		else
			local setter = api["set" .. field.kind]
			setter(target, field.name, field, value)
		end
	end


--
-- The remover: adds values to be removed to the "removes" field on
-- current configuration. Removes are keyed by the associated field,
-- so the call `removedefines("X")` will add the entry:
--  cfg.removes["defines"] = { "X" }
--

	function api.remove(field, value)
		-- right now, ignore calls with no value; later might want to
		-- return the current baked value
		if not value then return end
		
		-- hack: start a new configuration block if I can, so that the
		-- remove will be processed in the same context as it appears in
		-- the script. Can be removed when I rewrite the internals to
		-- be truly declarative
		if field.scope == "config" then
			api.configuration(api.scope.configuration.terms)
		end
		
		local target = api.gettarget(field.scope)
		
		-- start a removal list, and make it the target for my values
		target.removes = {}
		target.removes[field.name] = {}
		target = target.removes[field.name]

		-- some field kinds have a removal function to process the value
		local kind = field.kind
		local remover = api["remove" .. kind] or table.insert

		-- iterate the list of values and add them all to the list
		local function addvalue(value)
			-- recurse into tables
			if type(value) == "table" then
				for _, v in ipairs(value) do
					addvalue(v)
				end

			elseif field.splitOnSpace and type(value) == 'string' and value:contains(' ') then
				local v = value:split(' ')
				addvalue(v)
			
			-- insert simple values
			else
				if field.uniqueValues then
					target[value] = nil
				end			
				remover(target, value)
			end
		end
		
		addvalue(value)
	end


--
-- Check to see if a value exists in a list of values, using a 
-- case-insensitive match. If the value does exist, the canonical
-- version contained in the list is returned, so future tests can
-- use case-sensitive comparisions.
--

	function api.checkvalue(value, allowed, aliases)
		local valueL = value:lower()
		local errMsg
		
		if aliases then
			if aliases[valueL] then
				valueL = aliases[valueL]:lower()
			end
		end 
			
		-- If allowed it set to nil, allow everything. 
		-- But if allowed is a function and it returns nil, it's a failure
		if allowed then
			local allowedValues, errMsg
			if type(allowed) == "function" then
				allowedValues,errMsg = allowed(value)
				if not allowedValues then 
					return nil, errMsg
				end
				
				allowedValues = toSet(allowedValues, true)
				if allowedValues[valueL] then
					return allowedValues[valueL]
				else
					for _,v in ipairs(allowedValues) do
						if valueL == v:lower() then
							return v
						end
					end
				end
			else
				if allowed[valueL] then
					return allowed[valueL]
				end
			end
			
			errMsg = "invalid value '" .. value .. "'."
			if allowedValues and type(allowedValues)=='table' then
				errMsg = errMsg..' Allowed values are {'..table.concat(allowedValues, ' ')..'}'
			end
			return nil, errMsg

		else
			return value
		end
	end


--
-- Retrieve the base data kind of a field, by removing any key- prefix
-- or -list suffix and returning what's left.
--

	function api.getbasekind(field)
		local kind = field.kind
		if kind:startswith("key-") then
			kind = kind:sub(5)
		end
		if kind:endswith("-list") then
			kind = kind:sub(1, -6)
		end
		return kind
	end


--
-- Check the collection properties of a field.
--

	function api.iskeyedfield(field)
		--return field.kind:endswith("key-")
		return field.isKeyedTable
	end
	
	function api.islistfield(field)
		--return field.kind:endswith("-list")
		return field.isList
	end


--
-- Set a new array value. Arrays are lists of values stored by "value",
-- in that new values overwrite old ones, rather than merging like lists.
--

	function api.setarray(target, name, field, value)
		-- put simple values in an array
		if type(value) ~= "table" then
			value = { value }
		end
		
		-- store it, overwriting any existing value
		target[name] = value
	end


--
-- Set a new file value on an API field. Unlike paths, file value can
-- use wildcards (and so must always be a list).
--

	function api.setfile(target, name, field, value)
		if value:find("*") then
			local values = os.matchfiles(value)
			for _, value in ipairs(values) do
				api.setfile(target, name, field, value)
				name = name + 1
			end
		-- Check if we need to split the string
		elseif (not os.isfile(value)) and value:contains(' ') then
			for _,v in ipairs(value:split(' ')) do
				api.setfile(target, name, field, v)
			end
		elseif field.expandtokens and value:startswith('%') then
			-- expand to absolute later, as we don't know now if we have an absolute path or not 
			target[name] = value
		else
			local filename = path.getabsolute(value)
			local dir = path.getdirectory(value)
			if not os.isfile(filename) and not filename:match("%.pb%..*") then
				if not os.isdir(dir) then
					print("Warning : \""..dir.."\" is not a directory, can't find "..filename)
				else
					print("Warning : \""..filename.."\" is not a file")
				
					local allFiles = os.matchfiles(dir..'/*')
					local spell = premake.spelling.new(allFiles)
					local suggestions,str = spell:getSuggestions(value)
					print(str)
				end
			end
			target[name] = filename
		end
	end

	function api.setdirectory(target, name, field, value)
		if value:find("*") then
			local values = os.matchdirs(value)
			for _, value in ipairs(values) do
				api.setdirectory(target, name, field, value)
				name = name + 1
			end
		else
			-- make absolute later if it starts with %
			value = iif( value:startswith('%'), value, path.getabsolute(value))
			value = path.asRoot(value)
			
			target[name] = value
		end
	end
	
	function api.removefile(target, value)
		table.insert(target, path.getabsolute(value))
	end
	
	api.removedirectory = api.removefile


--
-- Update a keyed value. Iterate over the keys in the new value, and use
-- the corresponding values to update the target object.
--

	function api.setkeyvalue(target, field, values)
		if type(values) ~= "table" then
			error("value must be a table of key-value pairs", 4)
		end
		
		local kind = field.kind
		
		if field.isList then
			for key, value in pairs(values) do
				api.setlist(target, key, field, value)
			end
		else
			local setter = api["set" .. kind]
			for key, value in pairs(values) do
				setter(target, key, field, value)
			end
		end
	end
	
	function api.setusesconfig(target, name, field, values)
		target[name] = target[name] or {}
		target = target[name]
		
		if type(values) == 'string' then
			values = { values }
		end
		
		for k,v in pairs(values) do
			if type(k) == 'number' then
				table.insert(target, v)
			else
				target[k] = v
			end
		end
	end


--
-- Set a new list value. Lists are arrays of values, with new values
-- appended to any previous values.
--

	function api.setlist(target, name, field, value)
		-- start with the existing list, or an empty one
		target[name] = target[name] or {}
		target = target[name]
		
		-- find the contained data type
		local kind = field.kind
		local setter = api["set" .. kind]
		
		-- function to add values
		local function addvalue(value, depth)
			-- recurse into tables
			if type(value) == "table" then
				for _, v in ipairs(value) do
					addvalue(v, depth + 1)
				end
			
			-- insert simple values
			elseif field.splitOnSpace and type(value) == 'string' and value:contains(' ') then
				local v = value:split(' ')
				addvalue(v, depth + 1)
			else
				if field.uniqueValues then
					if target[value] then
						return
					end
					target[value] = true
				end			
				setter(target, #target + 1, field, value)
			end
		end
		
		addvalue(value, 3)
	end


--
-- Set a new object value on an API field.
--

	function api.setobject(target, name, field, value)
		target[name] = value
	end

--
-- Set a new path value on an API field.
--

	function api.setpath(target, name, field, value)
		api.setstring(target, name, field, value)
		
		-- don't convert in to absolute if it's tokenised
		if not target[name]:startswith('%') then
			target[name] = path.getabsolute(target[name])
			target[name] = path.asRoot(target[name])
		end 
	end


--
-- Set a new string value on an API field.
--

	function api.setstring(target, name, field, value)
		if type(value) == "table" then
			error("expected string; got table", 3)
		end

		local err
		value, err = api.checkvalue(value, field.allowed, field.aliases)
		if not value then
			error(err, 3)
		end

		target[name] = value
	end

--
-- Flags can contain an = in the string
--
	function api.setflaglist(target, name, field, value)
		if type(value) == 'table' then
			for k,v in pairs(value) do
				if type(k) == 'string' then v = k..'='..v end
				api.setflaglist(target, name, field, v)
			end
			return
		end
	
		local value, err = api.checkvalue(value, field.allowed, field.aliases)
		
		if err then
			error(err, 3)
		end

		-- Split in to key=value
		local key, v2 = value:match('([^=]*)=([^ ]*)')
		target[name] = target[name] or {}
		target = target[name]
		
		if key and v2 then
			-- eg. flags.Optimize=On
			target[key] = v2
		else
			-- eg flags.Symbols = "Symbols"
			target[value] = value
		end		
	end
--
-- Register the core API functions.
--

	api.register {
		name = "architecture",
		scope = "config",
		kind = "string",
		allowed = {
			"universal",
			"x32",
			"x64",
		},
	}

	api.register {
		name = "basedir",
		scope = "project",
		kind = "path"
	}
	
	api.register {
		name = "buildaction",
		scope = "config",
		kind = "string",
		allowed = {		
			"Compile",				-- Treat the file as source code; compile and link it
			"Copy",					-- Copy the file to the target directory
			"Embed",				-- Embed the file into the target binary as a resource
			"ImplicitDependency",	-- Implicit dependency - Not part of the build, but rebuild the project if this file changes
			"None"					-- do nothing with the file
		},
	}

	api.register {
		name = "buildoptions",
		scope = "config",
		kind = "string",
		isList = true,
		expandtokens = true,
		namealiases = { "buildflags", "cflags" },
	}

	-- buildrule takes a table parameter with the keys :  
	--	command[s] 		Command or commands to execute
	--  description		Short description of the command, displayed during ninja build
	--  outputs			(optional) Output files
	--  language		(optional) Specify a shell language to execute the command in. eg. bash, python, etc.
	--  stage			(default) 'postbuild' runs on the project target, 'link' runs on the compile output, 'compile' runs on the compile inputs
	--  dependencies	(optional) additional files which the tool depends on, but does not take as an input
	   
	--   Use tokens to specify the input filename, eg. %{file.relpath}/%{file.name}
	--	  also "$in" is equivalent to "%{cfg.files}", $out => %{cfg.targetdir.abspath}
	api.register {
		name = "buildrule",
		scope = "config",
		kind = "object",
		isList = true,
		expandtokens = true,
		setter = function(target, name, field, value)
			-- aliases
			value.commands = value.commands or value.command or value.cmd
			if type(value.commands) == 'string' then
				value.commands = { value.commands }
			end
			value.outputs = value.outputs or value.output
			local outputStr = Seq:new(value.outputs):select(function(p) 
				if not p:startswith('%') then
					return path.getabsolute(p)
				else
					return p
				end
			end):mkstring()
			value.absOutput = outputStr
			for k,v in ipairs(value.dependencies or {}) do
				value.dependencies[k] = path.getabsolute(v)
			end
			for k,v in ipairs(value.commands) do
				value.commands[k] = v:replace('$in','%{cfg.files}'):replace('$out',outputStr)
			end
			
			target[name] = target[name] or {}
			table.insert( target[name], value )
		end
	}

	-- buildwhen specifies when Premake should output the project in this configuration. Default is "always"
	-- always 		Always output the project in this configuration and build it by default
	-- used			Only output the project in this configuration when it is used by another project
	-- explicit		Always output the project in this configuration, but only build it when explicitly specified
	api.register {
		name = "buildwhen",
		scope = "config",
		kind = "string",
		
		allowed = { "always", "explicit", "used", },
	}
	
	-- The compile implicitly depends on the specified project
	api.register {
		name = "compiledepends",
		scope = "config",
		kind = "string",
		isList = true,
		usagePropagation = "Always",
	}
	
	-- Wrap the compile tool with this command. The original compile command & flags will be
	-- appended, or substituted in place of "$CMD" 
	api.register {
		name = "compilerwrapper",
		scope = "config",
		kind = "string",
		expandtokens = true,
	}

	api.register {
		name = "configmap",
		scope = "project",
		kind = "array",
		isKeyedTable = true,
	}

	api.register {
		name = "configurations",
		scope = "project",
		kind = "string",
		isList = true,
		setter = function(target, name, field, value)
			config.registerkey("buildcfg", value, true)
			-- always overwrite
			if type(value) == 'string' then value = { value } end
			target[name] = value
		end
	}
	
	-- Flags only passed to the C++ compiler
	api.register {
		name = "cxxflags",
		kind = "string",
		isList = true,
		scope = "config",
	}
	
	api.register {
		name = "debugargs",
		scope = "config",
		kind = "string",
		isList = true,
		expandtokens = true,
	}

	api.register {
		name = "debugcommand",
		scope = "config",
		kind = "path",
		expandtokens = true,
	}

	api.register {
		name = "debugdir",
		scope = "config",
		kind = "path",
		expandtokens = true,
	}
	
	api.register {
		name = "debugenvs",
		scope = "config",
		kind = "string",
		isList = true,
		expandtokens = true,
	}

	api.register {
		name = "debugformat",
		scope = "config",
		kind = "string",
		allowed = {
			"c7",
		},
	}
	
	api.register {
		name = "defaultconfiguration",
		scope = "project",
		kind = "string",
	}
	
	api.register {
		name = "defines",
		scope = "config",
		kind = "string",
		isList = true,
		expandtokens = true,
		splitOnSpace = true,
		namealiases = { "define" },
	}
	
	api.register {
		name = "deploymentoptions",
		scope = "config",
		kind = "string",
		isList = true,
		expandtokens = true,
	}

	api.register {
		name = "files",
		scope = "config",
		kind = "file",
		isList = true,
		expandtokens = true,
	}

	api.register {
		name = "flags",
		scope = "config",
		kind  = "flaglist",
		isConfigurationKeyword = true,
		usagePropagation = function(cfg, flags)
			local rv = {}
			-- Propagate these flags from a project to a project's usage requirements 
			rv.Threading = flags.Threading
			rv.Stdlib = flags.Stdlib
			return rv
		end,
		allowed = {
			"AddPhonyHeaderDependency",		 -- for Makefiles, requires CreateDependencyFile
			"CreateDependencyFile",
			"CreateDependencyFileIncludeSystem",	-- include system headers in the .d file
			"DebugEnvsDontMerge",
			"DebugEnvsInherit",
			"EnableSSE",
			"EnableSSE2",
			"EnableSSE3",
			"EnableSSE41",
			"EnableSSE42",
			"EnableAVX",
			"FatalWarnings",
			Float = { "Fast", "Strict", },
			Inline = { "Disabled", "ExplicitOnly", "Anything", },
			"Managed",
			"MFC",
			Threading = {
				"Multi",		-- Multithreaded system libs. Always propagated to usage.
				"Single",		-- Single threaded system libs. Always propagated to usage.
			},
			"NativeWChar",
			"No64BitChecks",
			"NoEditAndContinue",
			"NoExceptions",
			"NoFramePointer",
			"NoImportLib",
			"NoIncrementalLink",
			"NoManifest",
			"NoMinimalRebuild",
			"NoNativeWChar",
			"NoPCH",
			"NoRTTI",
			Optimize = { 'On', 'Off', 'Size', 'Speed' },
			"Profiling",			-- Enable profiling compiler flag
			"SEH",
			"StaticRuntime",
			Stdlib = { "Static", "Shared" },			-- Use static/shared standard libraries. Propagated to usage.
			"Symbols",
			"Unicode",
			"Unsafe",
			Warnings = { 'On', 'Off', 'Extra' },
			"WholeArchive",
			"WinMain",
		},
		aliases = {
			Optimize = 'Optimize=On',
			OptimizeSize = 'Optimize=Size',
			OptimizeSpeed = 'Optimize=Speed',
			OptimizeOff = 'Optimize=Off',
			Optimise = 'Optimize=On',
			OptimiseSize = 'Optimize=Size',
			OptimiseSpeed = 'Optimize=Speed',
			OptimiseOff = 'Optimize=Off',
			NoWarnings = 'Warnings=Off', 
			ExtraWarnings = 'Warnings=Extra',
		},
	}

	api.register {
		name = "framework",
		scope = "project",
		kind = "string",
		allowed = {
			"1.0",
			"1.1",
			"2.0",
			"3.0",
			"3.5",
			"4.0"
		},
	}

	api.register {
		name = "imageoptions",
		scope = "config",
		kind = "string",
		isList = true,
		expandtokens = true,		
	}
	
	api.register {
		name = "imagepath",
		scope = "config",
		kind = "path",
		expandtokens = true,		
	}	

	api.register {
		name = "implibdir",
		scope = "config",
		kind = "path",
		expandtokens = true,
	}			

	api.register {
		name = "implibextension",
		scope = "config",
		kind = "string",
		expandtokens = true,
	}

	api.register {
		name = "implibname",
		scope = "config",
		kind = "string",
		expandtokens = true,
	}

	api.register {
		name = "implibprefix",
		scope = "config",
		kind = "string",
		expandtokens = true,
	}

	api.register {
		name = "implibsuffix",
		scope = "config",
		kind = "string",
		expandtokens = true,
	}

	api.register {
		name = "includedirs",
		scope = "config",
		kind = "directory",
		isList = true,
		uniqueValues = true,				-- values in includedirs are unique. Duplicates are discarded 
		expandtokens = true,
		namealiases = { "includedir" },
	}
	
	-- includes a solution in the current solution. Use "*" to include all solutions
	api.register {
		name = "includesolution",
		scope = "solution",
		kind = "string",
		isList = true,
		uniqueValues = true,
	}

	-- Specifies the kind of project to output
	api.register {
		name = "kind",
		scope = "config",
		kind = "string",
		isConfigurationKeyword = true,		-- use this as a keyword for configurations
		allowed = {
			"ConsoleApp",
			"WindowedApp",
			"StaticLib",
			"SharedLib",
			
			-- Ouput is a header or source file, usually a compile dependency for another project
			--  This only gets built once for one configuration, as the output files are in the source tree
			--"SourceGen",
			
			-- Input files are script files to be executed
			"Command",
		},
		aliases = {
			Executable = 'ConsoleApp',
			Exe = 'ConsoleApp',
		}
	}

	api.register {
		name = "language",
		scope = "project",
		kind = "string",
		allowed = {
			"C",
			"C++",
			"C#",
			"assembler",
			"protobuf",
		},
	}

	-- Command line flags passed to both 'ar' and 'link' tools	
	api.register {
		name = "ldflags",
		scope = "config",
		kind = "string",
		isList = true,
	}

	api.register {
		name = "libdirs",
		scope = "config",
		kind = "directory",
		isList = true,
		expandtokens = true,
		usagePropagation = "WhenSharedOrStaticLib",		-- Propagate to usage requirement if kind="StaticLib" or kind="SharedLib"
		namealiases = { 'libdir' }
	}

	-- Command line flags passed to the link tool (and not 'ar') 
	api.register {
		name = "linkoptions",
		scope = "config",
		kind = "string",
		isList = true,
		expandtokens = true,
		namealiases = { "linkflags" }
	}
	
	-- if the value is a static lib project, link it as a static lib & propagate if the current project is StaticLib
	-- if the value is a shared lib project, link it as a shared lib & propagate if the current project is StaticLib or SharedLib
	-- if the value is neither, link it as a shared system lib & propagate if the current project is StaticLib or SharedLib
	api.register {
		name = "links",
		scope = "config",
		kind = "string",
		isList = true,
		allowed = function(value)
			-- if library name contains a '/' then treat it as a path to a local file
			if value:find('/', nil, true) then
				local absPath = path.getabsolute(value)
				if os.isfile(absPath) then
					value = absPath
				end
			end
			return value
		end,
		expandtokens = true,
		-- usage propagation is dealt with by converting it to linkAsShared / linkAsStatic once it's resolved
	}
	
	-- Link to the shared lib version of a system library
	--  If the same library is also defined with linkAsStatic, then linkAsShared will override it
	api.register {
		name = "linkAsShared",
		scope = "config",
		kind = "string",
		isList = true,
		expandtokens = true,
		usagePropagation = "WhenSharedOrStaticLib",
	}
	
	-- Link to the static lib version of a system library
	--  If the same library is also defined with linkAsShared, then linkAsShared will override this  
	api.register {
		name = "linkAsStatic",
		scope = "config",
		kind = "string",
		isList = true,
		expandtokens = true,
		usagePropagation = "WhenStaticLib"
	}
	
	-- Wrap the linker tool with this command. The original compile command & flags will be
	-- appended, or substituted in place of "$CMD" 
	api.register {
		name = "linkerwrapper",
		scope = "config",
		kind = "string",
		expandtokens = true,
	}
	
	api.register {
		name = "location",
		scope = "project",
		kind = "path",
		expandtokens = true,
	}

	api.register {
		name = "makesettings",
		scope = "config",
		kind = "string",
		isList = true,
		expandtokens = true,
	}

	-- Path to put the ninja build log
	api.register {
		name = "ninjaBuildDir",
		scope = "solution",
		kind = "string",
		expandtokens = true,
		nameAliases = { 'ninjabuilddir' }
	}

	api.register {
		name = "objdir",
		scope = "config",
		kind = "path",
		expandtokens = true,
	}

	api.register {
		name = "pchheader",
		scope = "config",
		kind = "string",
		expandtokens = true,
	}

	api.register {
		name = "pchsource",
		scope = "config",
		kind = "path",
		expandtokens = true,
	}		

	api.register {
		name = "platforms",
		scope = "project",
		kind = "string",
		isList = true,
		setter = function(target, name, field, value)
			config.registerkey("platform", value, true)
			-- always overwrite
			target[name] = {}
			table.insertflat(target[name], value)
		end
	}

	api.register {
		name = "postbuildcommands",
		scope = "config",
		kind = "string",
		isList = true,
		expandtokens = true,
		namealiases = { 'postbuildcommand' },
	}

	api.register {
		name = "prebuildcommands",
		scope = "config",
		kind = "string",
		isList = true,
		expandtokens = true,
		namealiases = { 'prebuildcommand' },
	}

	api.register {
		name = "prelinkcommands",
		scope = "config",
		kind = "string",
		isList = true,
		expandtokens = true,
	}
	
	-- Project full-names consist of namespace/shortname, where namespace can contain further / characters
	-- Projects created after this statement will have their name prefixed by this value.
	-- When using a project, you can refer to it by its shortname if you are in the same solution
	-- The default prefix is the solution name
	-- If the project name is equal to the prefix, the prefix is ignored.
	--  eg :
	--   solution "MySoln"
	--   project "prjA"				-- this is equivalent to project "MySoln/prjA"
	--	 projectprefix "base"
	--	 project "prjA" ...			-- this is equivalent to project "base/prjA"
	--   project "B/prjB" ...		-- this is equivalent to project "base/B/prjB"
	--	 projectprefix "MySoln/client"
	--	 project "prjA" ...			-- this is equivalent to project "MySoln/client/prjA"
	--   project "MySoln/client"	-- special case, this is equivalent to project "MySoln/client"
	api.register {
		name = "projectprefix",
		scope = "solution",
		kind = "string",
		allowed = function(value)
			if not value:endswith("/") then
				return nil, "projectprefix must end with / : "..value..' in '..path.getrelative(repoRoot or '',_SCRIPT)
			end
			return value
		end,
		namealiases = { "projectPrefix", }
	}
	
	-- 
	-- CPP = Directory which a protobuf project outputs C++ files to (optional) 
	-- Directory which a protobuf project outputs Java files to (optional)
	api.register {
		name = "protobufout",
		scope = "config",
		kind = "path",
		isKeyedTable = true,
		expandtokens = true,
	}
	
	-- Sets the directory to put the release files/symlinks in
	-- Relative paths are relative to --releaseDir, which defaults to repoRoot/release
	--  Example : releasedir { bin = '.', scripts = './scripts', installbin='/usr/bin/ }
	--
	api.register {
		name = "releasedir",
		scope = "global",
		kind = "string",			-- string not path, to keep the paths as relative
		isKeyedTable = true,
		expandtokens = true,
	}

	api.register {
		name = "resdefines",
		scope = "config",
		kind = "string",
		isList = true,
		expandtokens = true,
	}

	api.register {
		name = "resincludedirs",
		scope = "config",
		kind = "directory",
		isList = true,
		expandtokens = true,
	}

	api.register {
		name = "resoptions",
		scope = "config",
		kind = "string",
		isList = true,
		expandtokens = true,
	}
	
	-- Specify a [.so/.dll] search directory to hard-code in to the executable
	api.register {
		name = "rpath",
		scope = "config",
		kind = "path",
		isList = true,
		expandtokens = true,
		usagePropagation = "WhenSharedOrStaticLib",
	}
	
	-- list of all features supported by the project
	-- This is set by the api.feature command 
	api.register {
		name = "supportedfeatures",
		scope = "project",
		kind = "string",
		isList = true,
		usagePropagation = "Always",
	}

	api.register {
		name = "system",
		scope = "config",
		kind = "string",
		allowed = function(value)
			value = value:lower()
			if premake.systems[value] then
				return value
			else
				return nil, "unknown system"
			end
		end,
	}

	api.register {
		name = "targetdir",
		scope = "config",
		kind = "path",
		expandtokens = true,
	}		

	api.register {
		name = "targetextension",
		scope = "config",
		kind = "string",
		expandtokens = true,
	}

	api.register {
		name = "targetname",
		scope = "config",
		kind = "string",
		expandtokens = true,
	}

	api.register {
		name = "targetprefix",
		scope = "config",
		kind = "string",
		expandtokens = true,
	}

	api.register {
		name = "targetsuffix",
		scope = "config",
		kind = "string",
		expandtokens = true,
	}

	api.register {
		name = "toolset",
		scope = "config",
		kind = "string",
		isConfigurationKeyword = true,		-- use this as a keyword for configurations
		-- set allowed to a function so it will be evaluated later when all the toolsets have been loaded
		allowed = function() return getSubTableNames(premake.tools); end 
	}
	
	-- Enable a feature declared with "buildfeature" 
	api.register {
		name = "usefeature",
		scope = "config",
		kind = "string",
		isList = true,
	}
	
	-- Specifies a project/usage that this project configuration depends upon
	api.register {
		name = "uses",
		scope = "config",
		kind = "string",
		isList = true,
		namealiases = { "using", "use" },
		splitOnSpace = true,			-- "apple banana carrot" is equivalent to { "apple", "banana", "carrot" }
	}

	-- Like "uses", but is always propagated to all dependent projects, not just the first level real projects
	api.register {
		name = "alwaysuses",
		scope = "config",
		kind = "string",
		isList = true,
		namealiases = { "alwaysuse" },
		splitOnSpace = true,			-- "apple banana carrot" is equivalent to { "apple", "banana", "carrot" }
		usagePropagation = "Always",
	}
	
	
	-- Add a new keyword to the configuration filter
	--  for any project we use which defines a configuration with this keyword will have that section applied
	-- eg. declare the debug build of the boost libs with configuration "boostdebug"
	--      and add usesconfig "boostdebug" to your project
	--		This keeps the boost configuration name separate from your solution's configuration names
	api.register {
		name = "usesconfig",
		scope = "config",
		kind = "usesconfig",
		namealiases = { "useconfig" },
	}

	api.register {
		name = "uuid",
		scope = "project",
		kind = "string",
		allowed = function(value)
			local ok = true
			if (#value ~= 36) then ok = false end
			for i=1,36 do
				local ch = value:sub(i,i)
				if (not ch:find("[ABCDEFabcdef0123456789-]")) then ok = false end
			end
			if (value:sub(9,9) ~= "-")   then ok = false end
			if (value:sub(14,14) ~= "-") then ok = false end
			if (value:sub(19,19) ~= "-") then ok = false end
			if (value:sub(24,24) ~= "-") then ok = false end
			if (not ok) then
				return nil, "invalid UUID"
			end
			return value:upper()
		end
	}

	api.register {
		name = "vpaths",
		scope = "project",
		kind = "path",
		isKeyedTable = true,
		isList = true,
	}



-----------------------------------------------------------------------------
-- Everything below this point is a candidate for deprecation
-----------------------------------------------------------------------------


--
-- Retrieve the current object of a particular type from the session. The
-- type may be "solution", "container" (the last activated solution or
-- project), or "config" (the last activated configuration). Returns the
-- requested container, or nil and an error message.
--

	function premake.getobject(t)
		local container
		
		if (t == "container" or t == "solution") then
			container = premake.CurrentContainer
		else
			container = premake.CurrentConfiguration
		end
		
		if t == "solution" then
			if ptype(container) == "project" then
				container = container.solution
			end
			if ptype(container) ~= "solution" then
				container = nil
			end
		end
		
		local msg
		if (not container) then
			if (t == "container") then
				msg = "no active solution or project"
			elseif (t == "solution") then
				msg = "no active solution"
			else
				msg = "no active solution, project, or configuration"
			end
		end
		
		return container, msg
	end


--
-- Sets the value of an object field on the provided container.
--
-- @param obj
--    The object containing the field to be set.
-- @param fieldname
--    The name of the object field to be set.
-- @param value
--    The new object value for the field.
-- @return
--    The new value of the field.
--

	function premake.setobject(obj, fieldname, value)
		obj[fieldname] = value
		return value
	end

	
--
-- Adds values to an array field.
--
-- @param obj
--    The object containing the field.
-- @param fieldname
--    The name of the array field to which to add.
-- @param values
--    The value(s) to add. May be a simple value or an array
--    of values.
-- @param allowed
--    An optional list of allowed values for this field.
-- @return
--    The value of the target field, with the new value(s) added.
--

	function premake.setarray(obj, fieldname, value, allowed, aliases)
		obj[fieldname] = obj[fieldname] or {}

		local function add(value, depth)
			if type(value) == "table" then
				for _,v in ipairs(value) do
					add(v, depth + 1)
				end
			else
				value, err = api.checkvalue(value, allowed, aliases)
				if not value then
					error(err, depth)
				end
				obj[fieldname] = table.join(obj[fieldname], value)
			end
		end

		if value then
			add(value, 5)
		end
		
		return obj[fieldname]
	end
	
--
-- Adds values to a key-value field of a solution/project/configuration. `ctype`
-- specifies the container type (see premake.getobject) for the field.
--

	function premake.setkeyvalue(ctype, fieldname, values)
		local container, err = premake.getobject(ctype)
		if not container then
			error(err, 4)
		end
		
		if type(values) ~= "table" then
			error("invalid value; table expected", 4)
		end
		
		container[fieldname] = container[fieldname] or {}
		local field = container[fieldname] or {}
		
		for key,value in pairs(values) do
			field[key] = field[key] or {}
			table.insertflat(field[key], value)
		end

		return field
	end


--
-- Set a new value for a string field of a solution/project/configuration. `ctype`
-- specifies the container type (see premake.getobject) for the field.
--

	function premake.setstring(ctype, fieldname, value, allowed, aliases)
		-- find the container for this value
		local container, err = premake.getobject(ctype)
		if (not container) then
			error(err, 4)
		end
	
		-- if a value was provided, set it
		if (value) then
			value, err = api.checkvalue(value, allowed, aliases)
			if (not value) then 
				error(err, 4)
			end
			
			container[fieldname] = value
		end
		
		return container[fieldname]	
	end
	
--
-- For backward compatibility, excludes() is becoming an alias for removefiles().
--

	function excludes(value)
		removefiles(value)
	end
	

--
-- Project object constructors.
--
	 
	function api.configuration(terms)
		if not terms then
			return premake.CurrentConfiguration
		end
		
		local container, err = premake.getobject("container")
		if (not container) then
			error(err, 2)
		end
		
		local cfg = { }
		cfg.terms = table.flatten({terms})
		
		table.insert(container.blocks, cfg)
		premake.CurrentConfiguration = cfg
		
		-- create a keyword list using just the indexed keyword items. This is a little
		-- confusing: "terms" are what the user specifies in the script, "keywords" are
		-- the Lua patterns that result. I'll refactor to better names.
		cfg.keywords = { }
		local aliases = premake.fields['flags']
		for i, word in ipairs(cfg.terms) do
			
			-- check if the word is an alias for something else
			if aliases[word] then
				word = aliases[word]
				cfg.terms[i] = word
			end
			
			table.insert(cfg.keywords, path.wildcards(word):lower())
		end
		
		local isUsageProj = container.isUsage
		
		-- this is the new place for storing scoped objects
		api.scope.configuration = cfg
		
		return cfg
	end

	-- Starts a usage project section
	--  If a real project of the same name already exists, this section defines the usage requirements for the project
	--  If a real project of the same name does not exist, this is a pure "usage project", a set of fields to copy to anything that uses it
	function api.usage(name)
		if (not name) then
			--Only return usage projects.
			if(ptype(premake.CurrentContainer) ~= "project") then return nil end
			if(premake.CurrentContainer.isUsage) then 
				return premake.CurrentContainer
			else
				return api.usage(premake.CurrentContainer.name)
			end
		elseif type(name) ~= 'string' then
			error('Invalid parameter for usage, must be a string')
		elseif name == '_GLOBAL_CONTAINER' then
			return api.solution(name)
		end
		
		-- identify the parent solution
		local sln
		if (ptype(premake.CurrentContainer) == "project") then
			sln = premake.CurrentContainer.solution
		else
			sln = premake.CurrentContainer
		end
					
		if (ptype(sln) ~= "solution" and ptype(sln) ~= 'globalcontainer') then
			error("no active solution or globalcontainer", 2)
		end

  		-- if this is a new project, or the project in that slot doesn't have a usage, create it
		local prj = premake5.project.createproject(name, sln, true)
  		
  		-- Set the current container
  		premake.CurrentContainer = prj
		api.scope.project = premake.CurrentContainer
  		
  		-- add an empty, global configuration to the project
  		configuration { }
  	
  		return premake.CurrentContainer
  	end
  
  	function api.project(name)
  		if (not name) then
  			--Only return non-usage projects
  			if(ptype(premake.CurrentContainer) ~= "project") then return nil end
  			if(premake.CurrentContainer.isUsage) then return nil end
  			return premake.CurrentContainer
		end
		
  		-- identify the parent solution
  		local sln
  		if (ptype(premake.CurrentContainer) == "project") then
  			sln = premake.CurrentContainer.solution
  		else
  			sln = premake.CurrentContainer
  		end			
  		if (ptype(sln) ~= "solution") then
  			error("no active solution", 2)
  		end

  		-- if this is a new project, create it
  		local prj = premake5.project.createproject(name, sln, false)
  		
  		-- Set the current container
  		premake.CurrentContainer = prj
		api.scope.project = premake.CurrentContainer
		  		
		-- add an empty, global configuration to the project
		configuration { }
	
		return premake.CurrentContainer
	end

--
--  Global container for configurations, applied to all solutions
--
	function api.global()
		local c = api.solution('_GLOBAL_CONTAINER')
		globalContainer.solution = c
	end

	function api.solution(name)
		if not name then
			if ptype(premake.CurrentContainer) == "project" then
				return premake.CurrentContainer.solution
			else
				return premake.CurrentContainer
			end
		end
		
		local sln
		if name == '_GLOBAL_CONTAINER' then	
			sln = globalContainer.solution
		else
			sln = premake.solution.get(name)
		end
		
		if (not sln) then
			sln = premake.solution.new(name)
		end

		premake.CurrentContainer = sln
		
		-- add an empty, global configuration
		configuration { }
		
		-- this is the new place for storing scoped objects
		api.scope.solution = sln
		api.scope.project = nil
		
		-- set the default project prefix
		if name ~= '_GLOBAL_CONTAINER' then	
			sln.projectprefix = sln.projectprefix or (name..'/')
		end
		
		return premake.CurrentContainer
	end


--
-- Creates a reference to an external, non-Premake generated project.
--

	function external(name)
		-- define it like a regular project
		local prj = api.project(name)
		
		-- then mark it as external
		prj.external = true;
		prj.externalname = prj.name
		
		return prj
	end


--
-- Define a new action.
--
-- @param a
--    The new action object.
--

	function newaction(a)
		premake.action.add(a)
	end


--
-- Define a new option.
--
-- @param opt
--    The new option object.
--

	function newoption(opt)
		premake.option.add(opt)
	end

--
-- Define a new tool
--
	function newtool(t)
		return premake.tools.newtool(t)
	end
	
--
-- Defines a new toolset. 
--  eg. newtoolset { toolsetName = 'mytoolset', tools = { mytool_cc, mytool_cxx, mytool_link, mytool_ar }, }
--
	function newtoolset(t)
		return premake.tools.newtoolset(t)
	end
		
--
-- Google protocol buffers
--  Example usage in a project section : protobuf { cppRoot = "..", javaRoot = ".." }
--  as per protoc, cppRoot/javaRoot/pythonRoot are relative to the solution root path
--  protoPath defaults to repoRoot
--
	function api.protobuf(t)
	
		local protoPath = path.getabsolute( api.scope.solution.basedir )
		
		-- Some alternative quick inputs. eg. protobuf "*.protobuf" or protobuf "cpp"
		if type(t) == 'string' then
			local parts = toSet(t:split(" "))
			t = {}
			
			for v,_ in pairs(parts) do
				if v:contains('.proto') then
					t.files = t.files or {}
					table.insert( t.files, v )
				end
			end
			if parts["cpp"] then 		t.cppRoot = protoPath end
			if parts["java"] then 		t.javaRoot = protoPath end
			if parts["python"] then 	t.pythonRoot = protoPath end
			if table.isempty(t) then
				error("unknown protobuf argument in \""..mkstring(getKeys(parts), " ").."\"")
			end
		end
		t.protoPath = t.protoPath or protoPath

		if not protoPath then
			error("protoPath is nil")
		end

		local inputFilePattern = toList(t.files or '*.proto')
		local outputs = {}

		-- Create a new project, append /protobuf on to the active project name or directory name
		local prj = api.scope.project
		if not prj then
			error("Must use protobuf statement within a project")
		end
		local prjName = prj.name or path.getbasename(os.getcwd())
		prjName = prjName..'/protobuf'
		
		-- ** protoc's cpp/java/python_out is relative to the specified --proto_path **
		  
		outputs.protoPath = protoPath
		if t.cppRoot then outputs.cppRoot = t.cppRoot end
		if t.javaRoot then outputs.javaRoot = t.javaRoot end
		if t.pythonRoot then outputs.pythonRoot = t.pythonRoot end
		-- default to cpp output in the current directory
		if (not outputs.cppRoot) and (not outputs.javaRoot) and (not outputs.pythonRoot) then
			outputs.cppRoot = protoPath
		end

		local protoFiles = {}
		api.setlist(protoFiles, 'files', premake.fields['files'], inputFilePattern)
		local protoCPPFiles = Seq:new(protoFiles.files):select(function(v) return v:gsub('%.proto$','%.pb%.cc') end):toTable()
		
		if #protoCPPFiles == 0 then
			error("Could not find any *.proto files in "..os.getcwd().."/"..mkstring(inputFilePattern))
		end
		
		-- Create a protobuf project to convert the .proto files in to .pb.cc
		api.scopepush()
		project(prjName)
			configurations("All")			-- Only output one configuration, the special "All" configuration
			language("protobuf")
			toolset("protobuf")
			files(inputFilePattern)
			protobufout(outputs)
			compiledepends(prjName)  -- if you use this protobuf project, it should be propagated as a compile dependency
			alwaysuse("system/protobuf")	-- any derived project should always include the protobuf includes
			
			-- add the protobuf project to the usage requirements for the active solution
		solution(api.scope.solution.name)
			uses(prjName)
			
		api.scopepop()
		-- add C files to active outer project
		files(protoCPPFiles)
	end

	-- "export" explicitly lists which projects are included in a solution, and gives it an alias
	function api.export(aliasName, fullProjectName)
		fullProjectName = fullProjectName or aliasName 

		local sln = api.scope.solution
		if not sln then
			error("Can't export, no active solution to export to")
		end
		if type(aliasName) ~= 'string' then
			error("export expected string parameter, found "..type(aliasName))
		end
		
		if not aliasName:startswith(sln.name..'/') then
			aliasName = sln.name .. '/' ..aliasName
		end
		if not fullProjectName:startswith(sln.name..'/') then
			fullProjectName = sln.name .. '/' ..fullProjectName
		end
		
		-- set up alias
		if fullProjectName ~= aliasName then
			targets.aliases[aliasName] = fullProjectName
		end
		
		sln.exports = sln.exports or {}
		sln.exports[aliasName] = fullProjectName
		
		-- solution's usage requirements include exported projects
		api.scopepush()
			usage(sln.name..'/'..sln.name)
			uses(aliasName)
		api.scopepop()
	end

	function api.explicitproject(prjName)
		api.project(prjName)
		api.explicit(prjName)
	end
	
	function api.explicit(prjName)
		local prj = premake5.project.getRealProject(prjName)
		if prj then
			prj.isExplicit = true
		end
	end

--*************************************************************************************
-- Releases
--
-- Example usage :
--  releasedir { name = "bin", path = "/usr/bin", perms = "755" }
--  release {
--   name = "MyRelease",
--   bin = "file-to-put-in-bin-dir.ext someProject",
--   rootBin = { "putInUsrBin", perms = 755 },
--   conf = "someConf.conf"
--  }
-- or
--  release("MyRelease", "projA projB")	 -- default output to bin
-- or
--  release( { name = "prjA-scripts", bin = { "$root/prjA/scripts/dump.pl", rootdir='$root/prjA' } } ) 
--*************************************************************************************

function release(t, t2)
	local sln = api.scope.solution
	if not sln then
		error("No active solution")
	end
	
	-- alias for quick one-line entry method
	if t2 then
		if type(t) ~= 'string' then
			error("Unexpected syntax for release command, expected release(<table>) or release(<name>, <bin release files>)")
		end
		t = { 
			name = t,
			bin = t2
		}
		t2 = nil
	end
	
	if not t.name then
		error("release nas no name field")
	end
	local name = t.name
	
	local releases = targets.releases
	releases[name] = releases[name] or {}
	
	local rel = releases[name]
	rel.name = name
	rel.prefix = sln.projectprefix
	rel.path = os.getcwd()
	
	rel.destinations = rel.destinations or {}
	for destName,v in pairs(t) do
		if type(destName) == 'number' then
			destName = 'bin'
		end
		if destName ~= 'name' then
			local src = { destName = destName, sources = {} }
			
			if type(v) == 'string' then src.sources = v:split(' ') 
			elseif type(v) == 'table' then
				for k,v in pairs(v) do
					if type(k) == 'number' then
						table.insert( src.sources, v )
					else
						src[k] = v
					end
				end
			end
			table.insert( rel.destinations, src ) 
		end
	end
end

--*************************************************************************************
-- Features
--  Features are build configurations which are enabled by a dependent project 
--  This command defines a new feature configuration. You can define a feature
--  in your common project, and enable that feature if you use it in a 
--  derived project with "usefeature"
--*************************************************************************************

function api.buildfeature(featureName)
	if not featureName or featureName == '' then
		-- exit the feature block
		configuration {} 
		return
	end
	if type(featureName) ~= 'string' then
		error("Expected feature <featureName>")
	end
	
	local featureNameL = featureName:lower()
	if premake.fields[featureNameL] or premake.fieldAliases[featureNameL] then
		error("Invalid feature name : \""..featureName.."\", this is a keyword")
	end
	
	-- Register this configuration keyword as a propagated feature
	config.registerkey(featureName, featureName, true)
	
	-- Keeping track of a project's supported features is necessary in order to decide if 
	-- we need to add a separate build configuration for a requested feature.
	--   supportedfeatures is always propagated to the usage requirements 
	supportedfeatures(featureName)
	
	-- Start a new configuration block for this feature
	configuration(featureName)
end