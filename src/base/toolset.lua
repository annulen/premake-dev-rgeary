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

-- Default toolset by file extension
toolset.toolsByExt = {}

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
	t.buildoptions	= cfg.buildoptions
	t.default		= '$in'
	
	return t
end

--
-- Toolset only provides "compile" and "link" features, but this allows 
--  for different tool names for different configurations
--	
function toolset:getCompileTool(cfg, fileExt)
    if cfg.project.language == "C" then
	    return self.tools['cc']
	else
		if fileExt then
			if self.toolsByExt[fileExt] then
				return self.toolsByExt[fileExt]
			end
		end

		return nil
	end	    	
end

function toolset:getLinkTool(cfg)
    if cfg.kind == premake.STATICLIB then
    	return self.tools['ar'] or self.tools['link']
    else
    	return self.tools['link']
    end
end

--
-- Callback for newtoolset api function
--
function premake.tools.newtoolset(toolsetDef)
	if not toolsetDef or type(toolsetDef) ~= 'table' then
		error('Invalid toolset definition, expected table')
	end
	if not toolsetDef.toolsetName or toolsetDef.toolsetName == '' then
		error('newtoolset does not define toolsetName')
	end
	
	local t = inheritFrom(premake.abstract.toolset)
	
	-- Apply specified values/functions
	for k,v in pairs(toolsetDef) do
		t[k] = v
	end
	ptypeSet(t, 'toolset')
	
	if t.tools == nil then
		if t.toolsetName ~= 'command' then
			print('Warning : No tools defined for toolset "' .. t.toolsetName .. '"')
		end
		t.tools = {}
		t.toolsByExt = {}
	else
		-- Construct tool lookup
		t.toolsByExt = {}
		
		for _,tool in ipairs(t.tools) do
			t.tools[tool.toolName] = tool
			
			if toolsetDef.binarydir then
				tool.binaryDir = tool.binaryDir or toolsetDef.binaryDir
			end
			
			-- Create unique rule name
			tool.ruleName = toolsetDef.toolsetName .. '_' .. tool.toolName
			
			-- Construct lookup sets for extensions
			if tool.extensionsForCompiling then
				tool.extensionsForCompiling = toSet(tool.extensionsForCompiling)
				for k,v in pairs(tool.extensionsForCompiling) do 
					t.toolsByExt[k] = tool
				end
			end
			if tool.extensionsForLinking then
				tool.extensionsForLinking = toSet(tool.extensionsForLinking)
				for k,v in pairs(tool.extensionsForLinking) do 
					t.toolsByExt[k] = tool
				end
			end
		end
		-- Special case, make sure it's the default
		if t.tools['cc'] and t.tools['cc'].extensionsForCompiling['.c'] then
			t.toolsByExt['.c'] = t.tools['cc']
		end
	end 
	
	premake.tools[t.toolsetName] = t
end
	
--
--  The simplest tool. This just executes a specified command on the input files
--   When running actions which don't support arbitrary execution (eg. VS), this will be executed by Premake 
--

newtoolset {
	toolsetName = 'command',
}