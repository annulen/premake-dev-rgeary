--
-- Abstract tool
--  Defines a command line given a tool name and how to process inputs & flags
--  Override any part of this to define your own tool
--
--  Inputs are lists of strings, split in to categories, eg :
--	  Default input filenames : toolInputs['default']			(eg. source files for cc, obj files for linker)
--	  defines :					toolInputs['defines']
--	  includedirs :				toolInputs.includedirs
--	  libdirs :					toolInputs.libdirs
--	  staticlibs  				toolInputs.staticlibs
--	  sharedlibs  				toolInputs.sharedlibs
--	  frameworklibs				toolInputs.frameworklibs
--  Decorating these toolInputs is done via tool.prefixes[inputCategory] and suffixes[inputCategory]
--  eg. tool.prefixes.defines = '-D'
--  Alternatively, you can specify function tool.decorateFn.includedirs(cfg) to override this behaviour

premake.abstract.buildtool = {}
local tool = premake.abstract.buildtool
local config = premake5.config

-- Tool name as it appears to premake. There can be several tools with the same tool name (eg. 'cc'), 
--  but they must be unique within the same toolset
tool.toolName = 'unnamed-tool'

-- If specified, inherit values & function definitions from this table, unless overridden 
tool.inheritFrom = nil

-- path to the tool binary. nil = search for it
tool.binaryDir = nil

-- Name of the binary to execute
tool.binaryName = nil

-- Cached result of getBinary
tool.binaryFullpath = nil

-- Fixed flags which always appear first in the command line. Two ways to override this.
tool.fixedFlags = nil
function tool:getFixedFlags()
	return self.fixedFlags
end

-- Order of arguments in the command line. Arguments not specified in this list are appended (optional)
tool.argumentOrder = { 'fixedFlags', 'output', 'sysflags', 'cfgflags' }

-- Mapping from Premake 'flags' to compiler flags
tool.flagMap = {}

-- Prefix to decorate defines, include paths & include libs
tool.prefixes = {
	-- defines = '-D',
	-- depfileOutput = '-MF'
}
tool.suffixes = {
	-- depfileOutput = '.d'
}
tool.decorateFn = {
	-- input = function(inputList) return '-Wl,--start-group'..table.concat(inputList, ' ')..'-Wl,--end-group'; end
}

-- Default is for C++ source, override this for other tool types
--tool.extensionsForLinking = { '.o', '.a', '.so' }		-- possible inputs in to the linker
tool.objectFileExtension = '.o'		-- output file extension for the compiler

-- Extra cmdflags depending on the config & system
function tool:getsysflags(cfg)
	return ''
end

--
-- Construct a command line given the flags & input/output args. 
--	toolCmd = tool:getBinary
--  cmdArgs = tool:decorateInputs
--
function tool:getCommandLine(toolCmd, cmdArgs)
	local fixedFlags = self:getFixedFlags() or ''
	
	if #cmdArgs == 0 then
		error('#toolInputs == 0, did you forget to flatten it?')
	end
	
	-- Allow the tool to silence stderr. eg. The Intel ar tool outputs unwanted status information   
	local redirectStderr = "" 
    if(self.redirectStderr) then
      local hostIsWindows = os.is("windows")
      if( hostIsWindows ) then
        redirectStderr = '2> nul'
      else
        redirectStderr = '2> /dev/null'
      end
	  table.insert(cmdArgs, redirectStderr)
    
    --[[elseif self.filterStderr then
    	if not os.is("windows") then
    		local grepFilter = "2>&1 | grep -v -e "
    		for _,v in ipairs(self.filterStderr) do
    			grepFilter = grepFilter .. "\'"..v.."\' "
    		end
    		table.insert(cmdArgs, grepFilter)
    	end]]
    end
	
	local cmdParts = table.join(toolCmd, fixedFlags, cmdArgs, self.endFlags)

	local cmd = table.concat(cmdParts, ' ')
	return cmd
end

----------------------------------------------
-- Functions which you shouldn't need to override
----------------------------------------------

--
-- Decorates the tool inputs for the command line
-- Returns a table containing a sequence of command line arguments, and a hashtable of variable definitions 
--
--  outputVar and inputVar are what you want to appear on the command line in the build file, eg. $out and $in
--	(optional) previousResult is the results of a previous run. If specified, only the changed inputs will be decorated & returned. 
--
function tool:decorateInputs(cfg, outputVar, inputVar, previousResult)
	local rv = {}
	local tmr = timer.start('tool:decorateInputs')
	
	-- Construct the argument list from the inputs
	for _,category in ipairs(self.decorateArgs) do
		local inputList
		if category == 'output' then inputList = outputVar
		elseif category == 'input' then inputList = inputVar 
		elseif category == 'sysflags' then inputList = self:getsysflags(cfg)
		elseif category == 'cfgflags' then inputList = table.translateV2(cfg.flags, self.flagMap)
		elseif category == 'depfileOutput' then
			if config.hasDependencyFileOutput(cfg) then
				inputList = outputVar
			end
		else 
			inputList = cfg[category]
		end
		if inputList then
			local d = self:decorateInput(category, inputList, true)
			rv[category] = d
		end
	end
	
	if self.getDescription then
		rv.description = self:getDescription(cfg)
	end
	
	timer.stop(tmr)
	return rv
end

-- Returns true if the config requested a dependency file output and the tool supports it
function tool:hasDependencyFileOutput(cfg)
	return config.hasDependencyFileOutput(cfg) and (self.flagMap['CreateDependencyFile'])
end

function tool:decorateInput(category, input, alwaysReturnString)
	local str = ''
	local inputList = toList(input)

	--[[if self.cache[input] then
		timer.start('cache.hit')
		timer.stop('cache.hit')
		return self.cache[input]
	end]]
	--timer.start('decorateInput')
	
	-- consistent sort order to prevent ninja rebuilding needlessly
	table.sort(inputList)
	
	if self.decorateFn[category] then
	
		-- Override prefix/suffix behaviour
		str = self.decorateFn[category](inputList)
		
	elseif self.prefixes[category] or self.suffixes[category] then
		-- Decorate each entry with prefix/suffix
		local prefix = self.prefixes[category] or ''
		local suffix = self.suffixes[category]
		
		for _,v in ipairs(inputList) do
			if prefix then
				v = prefix .. v
			end
			if suffix then
				v = v .. suffix
			end
			str = str .. v .. ' '
		end
	elseif alwaysReturnString then
		str = table.concat(inputList, ' ')
	else
		str = nil
	end
	
	--self.cache[input] = str
	--timer.stop('decorateInput')
	
	return str
end

-- Return the full path of the binary
function tool:getBinary(cfg)
	if self.binaryFullpath then
		return self.binaryFullpath
	end
	
	if not self.binaryName then
		error('binaryName is not specified for tool ' .. self.toolName)
	end

 	-- Find the binary
	local path = os.findbin(self.binaryName, self.binaryDir)
	local fullpath = ''
	if path then
		fullpath = path .. '/' .. self.binaryName
	else
		-- Just assume it's there
		if self.binaryDir then
			fullpath = self.binaryDir .. '/'
		end
		fullpath = fullpath .. self.binaryName
	end
	self.binaryDir = path
	
	-- Wrap the command in another command. Original command will be appended, or inserted if binaryLauncher contains $CMD
	if self.isCompiler and cfg.compilerwrapper then
		-- Insert or append original command
		local compilerwrapper = cfg.compilerwrapper
		
		if not compilerwrapper:contains('$CMD') then
			compilerwrapper = compilerwrapper..' $CMD'
		end
		
		-- Find the launcher
		local launcherPath = os.findbin(compilerwrapper, self.binaryDir)
		if launcherPath then
			compilerwrapper = path.join( launcherPath, compilerwrapper )
		end
		
		fullpath = compilerwrapper:replace('$CMD', fullpath)
	end
	self.binaryFullpath = fullpath
	
	return fullpath
end


--
-- Get the build tool & output filename given the source filename. Returns null if it's not a recognised source file
-- eg. .cpp -> .o
--
function tool:getCompileOutput(cfg, fileName, uniqueSet)
	local outputFilename
	local fileExt = path.getextension(fileName):lower()
	
	if (self.extensionsForCompiling and self.extensionsForCompiling[fileExt]) then
	
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
function tool:isLinkInput(cfg, fileExt)
	return (not self.extensionsForLinking) or (self.extensionsForLinking[fileExt] ~= nil)
end

-- Get library includes
--
function tool:getIncludeLibs(cfg, systemonly)
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
					table.insert(result, self.includeLibPrefix .. link.linktarget.basename)
				end
			end
		end
	end

	-- The "-l" flag is fine for system libraries
	links = config.getlinks(cfg, "system", "basename")
	for _, link in ipairs(links) do
		if path.isframework(link) then
			table.insert(result, self.includeFrameworkPrefix .. path.getbasename(link))
		elseif path.isobjectfile(link) then
			table.insert(result, link)
		else
			table.insert(result, self.includeLibPrefix .. link)
		end
	end

	return result
end	

--
-- API callbacks
--

function premake.tools.newtool(toolDef)
	if not toolDef or type(toolDef) ~= 'table' then
		error('Expected tool definition table')
	end
	
	local t = inheritFrom(premake.abstract.buildtool, 'tool')
	
	-- Aliases
	if toolDef.inheritfrom then
		toolDef.inheritFrom = toolDef.inheritfrom
	end
	if toolDef.inherit_from then
		toolDef.inheritFrom = toolDef.inherit_from
	end
	
	-- Apply inherited tool
	if toolDef.inheritFrom then
		for k,v in pairs(toolDef.inheritFrom) do
			if type(v) == 'table' then
				t[k] = table.deepcopy(v)
			else
				t[k] = v
			end
		end
	end
	
	-- Apply specified values/functions
	for k,v in pairs(toolDef) do
		t[k] = v
	end
	
	if (not t.toolName) or #t.toolName < 1 then
		error('toolName not specified')
	end 
	
	-- Categorise the tool
	if (not t.isCompiler) and (not t.isLinker) then
		if t.toolName == 'cc' or t.toolName == 'cxx' then
			t.isCompiler = true
		else
			t.isLinker = true
		end
	end
	
	-- Set up a list of arguments to decorate
	t.decorateArgs = {}
	-- extraArgs are arguments we always insert
	local extraArgs = {}
	if t.fixedFlags then table.insert(extraArgs, 'fixedFlags') end
	table.insert(extraArgs, 'cfgflags')
	if t.getsysflags ~= tool.getsysflags then 
		table.insert(extraArgs, 'sysflags')
	else
		t.argumentOrder = table.exceptValues(t.argumentOrder, 'sysflags') 
	end
	table.insertflat(extraArgs, { 'input', 'output' } )
	
	if t.isCompiler then
		table.insert( extraArgs, 'buildoptions' )
	end
	if t.isLinker then
		table.insert( extraArgs, 'ldflags' )
	end
	
	local args = Seq:new(t.prefixes):concat(t.suffixes):concat(t.decorateFn):getKeys():concat(extraArgs):toSet()
	-- First add any arguments specified in the argumentOrder variable
	for _,argName in ipairs(t.argumentOrder or {}) do
		if args[argName] then
			if not t.decorateArgs[argName] then
				t.decorateArgs[argName] = argName
				table.insert(t.decorateArgs, argName)
			end
		else
			printf("Warning : Could not find a decorator for argument '%s' listed in argumentOrder", argName)
		end  
	end
	-- Then add any others
	for category,_ in pairs(args) do
		if not t.decorateArgs[category] then
			t.decorateArgs[category] = category
			table.insert(t.decorateArgs, category)
		end
	end
	
	t.cache = {}  
	
	return t
end

function tool.decorateLibList(list, startPrefix, systemlibPrefix)
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
