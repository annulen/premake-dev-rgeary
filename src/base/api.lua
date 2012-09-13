
--
-- api.lua
-- Implementation of the solution, project, and configuration APIs.
-- Copyright (c) 2002-2012 Jason Perkins and the Premake project
--

	premake.api = {}
	local api = premake.api

--
-- Here I define all of the getter/setter functions as metadata. The actual
-- functions are built programmatically below.
--
-- Note that these are deprecated in favor of the api.register() calls below,
-- and will be going away as soon as I have a chance to port them.
--

--	kind			Description						Multiple instance behaviour			Comments
------------------------------------------------------------------------------------------------
--  string			A single string value			overwrite
--  string-list		A list of strings				append new elements to the list
--  path			A single path 					overwrite							Paths are converted to absolute
--  path-list		A list of paths					append new elements to the list		Paths are converted to absolute
--  directory-list	A list of paths					append new elements to the list		Can contain wildcards
--  file-list		A list of files					append new elements to the list		Can contain wildcards
--  key-array		A keyed table					overwrite
--  object			A table							overwrite
--  object-list		A list of tables				append new elements to the list

-- Modifiers :
--  overwrite		Multiple instances will overwrite. Used on string-list.
--  uniqueValues	The final list will contain only unique elements 
	
	premake.fields = {}
	premake.defaultfields = nil


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

		for _,n in ipairs(names) do
			if rawget(_G,n) then
				error('name '..n..' in use', 2)
			end
			
			-- add create a setter function for it
			_G[n] = function(value)
				return api.callback(field, value)
			end
			
			-- list values also get a removal function
			if api.islistfield(field) and not api.iskeyedfield(field) then
				_G["remove" .. n] = function(value)
					return api.remove(field, value)
				end
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
			end
			field.aliases = aliases
		end

		-- make sure there is a handler available for this kind of value
		local kind = api.getbasekind(field)
		if not api["set" .. kind] then
			error("invalid kind '" .. kind .. "'", 2)
		end
					
		-- add this new field to my master list
		premake.fields[field.name] = field
		
	end


--
-- Find the right target object for a given scope.
--

	function api.gettarget(scope)
		local target
		if scope == "solution" then
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
		if field.isConfigurationFilter then
			api.callback(premake.fields['usesconfig'], value)
		end
		
		-- A keyed value is a table containing key-value pairs, where the
		-- type of the value is defined by the field. 
		if api.iskeyedfield(field) then
			target[field.name] = target[field.name] or {}
			api.setkeyvalue(target[field.name], field, value)
		
		-- Object lists dealt with separately, don't want to flatten the tables
		elseif field.kind == 'object-list' then
			api.setobjectlist(target, field.name, field, value)
			
		-- Lists is an array containing values of another type
		elseif api.islistfield(field) then
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
		local kind = api.getbasekind(field)
		local remover = api["remove" .. kind] or table.insert

		-- iterate the list of values and add them all to the list
		local function addvalue(value)
			-- recurse into tables
			if type(value) == "table" then
				for _, v in ipairs(value) do
					addvalue(v)
				end
			
			-- insert simple values
			else
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
		
		if aliases then
			if aliases[valueL] then
				valueL = aliases[valueL]:lower()
			end
		end 
			
		-- If allowed it set to nil, allow everything. 
		-- But if allowed is a function and it returns nil, it's a failure
		if allowed then
			if type(allowed) == "function" then
				local allowedValues = allowed(valueL)
				if not allowedValues then return nil end
				
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
			
			local errMsg = "invalid value '" .. value .. "'."
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
		return field.kind:startswith("key-")
	end
	
	function api.islistfield(field)
		return field.kind:endswith("-list")
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
			target[name] = path.getabsolute(value)
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
		
		-- remove the "key-" prefix from the field kind
		local kind = api.getbasekind(field)
		
		if api.islistfield(field) then
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


--
-- Set a new list value. Lists are arrays of values, with new values
-- appended to any previous values.
--

	function api.setlist(target, name, field, value)
		-- start with the existing list, or an empty one
		target[name] = iif(field.overwrite, {}, target[name] or {})
		target = target[name]
		
		-- find the contained data type
		local kind = api.getbasekind(field)
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
	
	function api.setobjectlist(target, name, field, value)
		if name == 'buildrule' then
			-- aliases
			value.commands = value.commands or value.command or value.cmd
			value.outputs = value.outputs or value.output
			local outputStr = Seq:new(value.outputs):select(function(p) return path.getabsolute(p) end):mkstring()
			value.absOutput = outputStr
			for k,v in ipairs(value.dependencies or {}) do
				value.dependencies[k] = path.getabsolute(v)
			end
			for k,v in ipairs(value.commands) do
				value.commands[k] = v:replace('$in','%{cfg.files}'):replace('$out',outputStr)
			end
		end
		target[name] = target[name] or {}
		table.insert( target[name], value )
	end

--
-- Set a new path value on an API field.
--

	function api.setpath(target, name, field, value)
		api.setstring(target, name, field, value)
		target[name] = path.getabsolute(target[name])
	end


--
-- Set a new string value on an API field.
--

	function api.setstring(target, name, field, value)
		if type(value) == "table" then
			error("expected string; got table", 3)
		end

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
			for k,v in ipairs(value) do
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
			target[key] = v2
		else
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
	
	-- Wrap the compile tool with this command. The original compile command & flags will be
	-- appended, or substituted in place of "$CMD" 
	api.register {
		name = "compilerwrapper",
		scope = "config",
		kind = "string",
		expandtokens = true,
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
		kind = "string-list",
		expandtokens = true,
		namealiases = { "buildflags", "cflags" },
		-- 'usagefield = true' means that the field can be a "usage requirement". It will copy this field's values
		--   from the usage secton in to the destination project 
		usagefield = true,							
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
		kind = "object-list",
		expandtokens = true,
	}
	
	-- The compile depends on the specified project
	api.register {
		name = "compiledepends",
		scope = "config",
		kind = "string-list",
		usagefield = true,
	}

	api.register {
		name = "configmap",
		scope = "project",
		kind = "key-array"
	}

	api.register {
		name = "configurations",
		scope = "project",
		kind = "string-list",
		overwrite = true,			-- don't merge multiple configurations sections
	}
	
	-- Flags only passed to the C++ compiler
	api.register {
		name = "cxxflags",
		kind = "string-list",
		scope = "config",
		usagefield = true,
	}
	
	api.register {
		name = "debugargs",
		scope = "config",
		kind = "string-list",
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
		kind = "string-list",
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
		kind = "string-list",
		expandtokens = true,
		usagefield = true,
		namealiases = { "define" },
	}
	
	api.register {
		name = "deploymentoptions",
		scope = "config",
		kind = "string-list",
		expandtokens = true,
		usagefield = true,
	}

	api.register {
		name = "excludes",
		scope = "config",
		kind = "file-list",
		expandtokens = true,
	}

	api.register {
		name = "files",
		scope = "config",
		kind = "file-list",
		expandtokens = true,
	}

	api.register {
		name = "flags",
		scope = "config",
		kind  = "flaglist",
		usagefield = true,
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
			"ThreadingMulti",		-- Multithreaded system libs. Propagated to usage.
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
			"StdlibShared",			-- Use shared standard libraries. Propagated to usage.
			"StdlibStatic",			-- Use static standard libraries. Propagated to usage.
			"Symbols",
			"Unicode",
			"Unsafe",
			Warnings = { 'On', 'Off', 'Extra' },
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
		kind = "string-list",
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
		kind = "directory-list",
		uniqueValues = true,				-- values in includedirs are unique. Duplicates are discarded 
		expandtokens = true,
		usagefield = true,
		namealiases = { "includedir" },
	}
	
	-- includes a solution in the current solution. Use "*" to include all solutions
	api.register {
		name = "includesolution",
		scope = "solution",
		kind = "string-list",
		uniqueValues = true,
	}

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
			"Header",					-- Ouput is a header file, ie. a compile dependency for another project
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
		},
	}

	-- Command line flags passed to both 'ar' and 'link' tools	
	api.register {
		name = "ldflags",
		scope = "config",
		kind = "string-list",
		usagefield = true,
	}

	api.register {
		name = "libdirs",
		scope = "config",
		kind = "directory-list",
		expandtokens = true,
		usagefield = true,
		namealiases = { 'libdir' }
	}

	-- Command line flags passed to the link tool (and not 'ar') 
	api.register {
		name = "linkoptions",
		scope = "config",
		kind = "string-list",
		expandtokens = true,
		usagefield = true,
		namealiases = { "linkflags" }
	}
	
	api.register {
		name = "links",
		scope = "config",
		kind = "string-list",
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
		usagefield = true,
	}
	
	api.register {
		name = "linkAsShared",
		scope = "config",
		kind = "string-list",
		expandtokens = true,
		usagefield = true,
	}
	
	api.register {
		name = "linkAsStatic",
		scope = "config",
		kind = "string-list",
		expandtokens = true,
		usagefield = true,
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
		kind = "string-list",
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
		kind = "string-list",
	}

	api.register {
		name = "postbuildcommands",
		scope = "config",
		kind = "string-list",
		expandtokens = true,
		namealiases = { 'postbuildcommand' },
	}

	api.register {
		name = "prebuildcommands",
		scope = "config",
		kind = "string-list",
		expandtokens = true,
		namealiases = { 'prebuildcommand' },
	}

	api.register {
		name = "prelinkcommands",
		scope = "config",
		kind = "string-list",
		expandtokens = true,
	}

	api.register {
		name = "resdefines",
		scope = "config",
		kind = "string-list",
		expandtokens = true,
		usagefield = true,
	}

	api.register {
		name = "resincludedirs",
		scope = "config",
		kind = "directory-list",
		expandtokens = true,
		usagefield = true,
	}

	api.register {
		name = "resoptions",
		scope = "config",
		kind = "string-list",
		expandtokens = true,
		usagefield = true,
	}
	
	-- Specify a [.so/.dll] search directory to hard-code in to the executable
	api.register {
		name = "rpath",
		scope = "config",
		kind = "path-list",
		expandtokens = true,
		usagefield = true,
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

	for i=1,1 do
		api.register {
			name = "dummy"..tostring(i),
			scope = "config",
			kind = "string-list",
			expandtokens = true,
		}
	end

	api.register {
		name = "toolset",
		scope = "config",
		kind = "string",
		isConfigurationKeyword = true,		-- use this as a keyword for configurations
		-- set allowed to a function so it will be evaluated later when all the toolsets have been loaded
		allowed = function() return getSubTableNames(premake.tools); end 
	}
	
	api.register {
		name = "uses",
		scope = "config",
		kind = "string-list",
		namealiases = { "using" },
		splitOnSpace = true,			-- "apple banana carrot" is equivalent to { "apple", "banana", "carrot" }
	}
	
	-- Add a new keyword to the configuration filter
	--  for any project we use which defines a configuration with this keyword will have that section applied
	-- eg. declare the debug build of the boost libs with configuration "boostdebug"
	--      and add usesconfig "boostdebug" to your project
	--		This keeps the boost configuration name separate from your solution's configuration names
	api.register {
		name = "usesconfig",
		scope = "config",
		kind = "string-list",
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
		kind = "key-path-list",
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
-- Adds values to an array-of-directories field of a solution/project/configuration. 
-- `ctype` specifies the container type (see premake.getobject) for the field. All
-- values are converted to absolute paths before being stored.
--

	local function domatchedarray(obj, fieldname, value, matchfunc)
		local result = { }
		
		function makeabsolute(value, depth)
			if (type(value) == "table") then
				for _, item in ipairs(value) do
					makeabsolute(item, depth + 1)
				end
			elseif type(value) == "string" then
				if value:find("*") then
					makeabsolute(matchfunc(value), depth + 1)
				else
					table.insert(result, path.getabsolute(value))
				end
			else
				error("Invalid value in list: expected string, got " .. type(value), depth)
			end
		end
		
		makeabsolute(value, 3)
		return premake.setarray(obj, fieldname, result)
	end
	
	function premake.setdirarray(obj, fieldname, value)
		function set(value)
			if value:find("*") then
				value = os.matchdirs(value)
			end
			return path.getabsolute(value)
		end
		return premake.setarray(obj, fieldname, value, set)
	end
	
	function premake.setfilearray(obj, fieldname, value)
		function set(value)
			if value:find("*") then
				value = os.matchfiles(value)
			end
			return path.getabsolute(value)
		end
		return premake.setarray(obj, fieldname, value, set)
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
-- The getter/setter implemention.
--

	local function accessor(name, value)
		local field   = premake.fields[name]
		local kind    = field.kind
		local scope   = field.scope
		local allowed = field.allowed
		local aliases = field.aliases
		
		if (kind == "string" or kind == "path") and value then
			if type(value) ~= "string" then
				error("string value expected", 3)
			end
		end

		-- find the container for the value	
		local container, err = premake.getobject(scope)
		if (not container) then
			error(err, 3)
		end
	
		if kind == "string" then
			return premake.setstring(scope, name, value, allowed, aliases)
		elseif kind == "path" then
			if value then value = path.getabsolute(value) end
			return premake.setstring(scope, name, value)
		elseif kind == "list" then
			return premake.setarray(container, name, value, allowed, aliases)
		elseif kind == "dirlist" then
			return premake.setdirarray(container, name, value)
		elseif kind == "filelist" then
			return premake.setfilearray(container, name, value)
		elseif kind == "key-value" or kind == "key-pathlist" then
			return premake.setkeyvalue(scope, name, value)
		elseif kind == "object" then
			return premake.setobject(container, name, value)
		end
	end


--
-- The remover: adds values to be removed to the field "removes" on
-- current configuration. Removes are keyed by the associated field,
-- so the call `removedefines("X")` will add the entry:
--  cfg.removes["defines"] = { "X" }
--

	function premake.remove(fieldname, value)
		local field = premake.fields[fieldname]
		local kind = field.kind
		
		function set(value)
			if kind ~= "list" and not value:startswith("**") then
				return path.getabsolute(value)
			else
				return value
			end
		end
		
		if field.scope == "config" then
			api.configuration(api.scope.configuration.terms)
		end
		
		local cfg = premake.getobject(field.scope)
		cfg.removes = cfg.removes or {}
		cfg.removes[fieldname] = premake.setarray(cfg.removes, fieldname, value, set)
	end

	
--
-- Build all of the getter/setter functions from the metadata above.
--
	
	for name, info in pairs(premake.fields) do
		-- skip my new register() fields
		if not info.name then
			_G[name] = function(value)
				return accessor(name, value)
			end
			
			for _,alias in pairs(info.namealiases or {}) do
				_G[alias] = function(value)
					return accessor(name, value)
				end
			end
			
			-- list value types get a remove() call too
			if info.kind == "list" or 
			   info.kind == "dirlist" or 
			   info.kind == "filelist" 
			then
				_G["remove"..name] = function(value)
					premake.remove(name, value)
				end
			end
		end
	end


--
-- For backward compatibility, excludes() is becoming an alias for removefiles().
--

	function excludes(value)
		removefiles(value)
		-- remove this when switching to "ng" actions
		-- also remove the api.register() call for excludes
		return accessor("excludes", value)
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
		for _, word in ipairs(cfg.terms) do
			table.insert(cfg.keywords, path.wildcards(word):lower())
		end
		
		local isUsageProj = container.isUsage

		-- initialize list-type fields to empty tables
		if not premake.defaultfields then
			premake.defaultfields = {}
			for name, field in pairs(premake.fields) do
				if field.getDefaultValue then
					premake.defaultfields[name] = field
				end
			end
		end
		for name, field in pairs(premake.defaultfields) do
			cfg[name] = field.getDefaultValue()
		end
		
		
		-- this is the new place for storing scoped objects
		api.scope.configuration = cfg
		
		return cfg
	end

	function usage(name)
		if (not name) then
			--Only return usage projects.
			if(ptype(premake.CurrentContainer) ~= "project") then return nil end
			if(not premake.CurrentContainer.isUsage) then return nil end
			return premake.CurrentContainer
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
  		local prj = premake5.project.getUsageProject(name)
  		if not prj then
  			prj = premake5.project.createproject(name, sln, true)
  		end
  		
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
  		local prj = premake5.project.getRealProject(name)
  		if not prj then
  			prj = premake5.project.createproject(name, sln, false)
  		end
  		
  		-- Set the current container
  		premake.CurrentContainer = prj
		api.scope.project = premake.CurrentContainer
		  		
  		-- Add it to the solution 
		sln.projects[name] = prj
		
		-- add an empty, global configuration to the project
		configuration { }
	
		return premake.CurrentContainer
	end

--
--  Global container for configurations, applied to all solutions
--
	function api.global()
		local c = api.solution('_GLOBAL_CONTAINER')
		premake5.globalContainer.solution = c
	end

	function api.solution(name)
		if not name then
			if ptype(premake.CurrentContainer) == "project" then
				return premake.CurrentContainer.solution
			else
				return premake.CurrentContainer
			end
		end
		
		if name == '_GLOBAL_CONTAINER' then	
			premake.CurrentContainer = premake5.globalContainer.solution
		else
			premake.CurrentContainer = premake.solution.get(name)
		end
		
		if (not premake.CurrentContainer) then
			premake.CurrentContainer = premake.solution.new(name)
		end

		-- add an empty, global configuration
		configuration { }
		
		-- this is the new place for storing scoped objects
		api.scope.solution = premake.CurrentContainer
		api.scope.project = nil
		
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
		
