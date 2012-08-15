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
		print('Warning : No tools defined for toolset ' .. t.toolsetName)
	else
		-- Construct tool lookup
		for _,tool in ipairs(t.tools) do
			t.tools[tool.toolName] = tool
			
			-- Construct lookup sets for extensions
			tool.extensionsForCompiling = toSet(tool.extensionsForCompiling)
			tool.extensionsForLinking = toSet(tool.extensionsForLinking)
		end
	end 
	
	premake.tools[t.toolsetName] = t
end
	