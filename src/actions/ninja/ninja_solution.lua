--
-- Root build.ninja solution file generator
--

local ninja = premake.ninja
local solution = premake.solution
local project = premake5.project

function ninja.generate_solution(sln)
  
	_p('# %s solution build.ninja autogenerated by Premake', premake.action.current().shortname)
	_p('# Ninja build is available to download at http://martine.github.com/ninja/')
	_p('# Type "ninja help" for usage help')
	_p('')
	
	ninja.writeToolsets(sln)
	
end

function ninja.writeToolsets(sln)

	for cfg in solution.eachconfig(sln) do

        local toolset = premake.tools[cfg.toolset or "gcc"]
        print('toolset : ' .. table.concat(toolset, ","))
        
		-- Find compiler & linker tools
		local tooldir = "/apps/infrafs1/environ/20110323/bin"
		--local ccdir = os.searchpath(premake.platforms)
		local ccTool = tooldir .. "/" .. toolset.cc
		local cxxTool = tooldir .. "/icpc12"
		local linkTool = tooldir .. "/icpc12"
		local libTool = tooldir .. "/xiar12"
		
		local arch = ""
		local solutionName=""
		-- The Intel ar tool outputs unwanted information to stderr. Allow the toolset to pipe it to somewhere else  
		local redirectStderr = "" 
	    if(toolset.redirectStderr) then
	      local hostIsWindows = string.find(os.getversion(), "Windows")
	      if( hostIsWindows ) then
	        redirectStderr = '2> nul'
	      else
	        redirectStderr = '2> /dev/null'
	      end
	    end	 
	
		_p('# Environment settings & directories')
		--_p('tooldir=' .. tooldir)
		_p('arch=' .. arch)
		--_p('osver=' .. osver)
		--_p('compilerVer=' .. compilerVer)
		--_p('solution=' .. solutionName)
	
		_p('# Build tool locations')
		_p('ccTool = ' .. ccTool)
		_p('cxxTool = ' .. cxxTool)
		_p('linkTool = ' .. linkTool)
		_p('arTool = ' .. arTool)
		_p('')
		
		_p('# Global includes')
		_p('includeFlags = -I "."')
		_p('')
		
		_p('# Build tool flags')
		local cCommonFlags = table.concat(toolset.getcppflags(cfg), " ")	-- cppflags = C PreProcessor flags
		_p('cFlags = ' .. cCommonFlags .. table.concat(toolset.getcflags(cfg), " ") )
		_p('cxxFlags = ' .. cCommonFlags .. table.concat(toolset.getcxxflags(cfg), " "))
		_p('linkFlags = ' .. table.concat(table.join(toolset.getldflags(cfg), cfg.linkoptions), " ") )
		_p('arFlags = rc')
		_p('')
	
		-- C Compiler rule
		_p('# C Compiler rule')
		_p('rule cc')
		_p('  command = $ccTool $cFlags $includeFlags -o $out -MMD -MF $out.d $in' .. redirectStderr)
		_p('  depfile = $out.d')
		_p('  description = cc $out')
		_p('')
		
		-- C++ Compiler rule
		_p('# C++ Compiler rule')
		_p('rule cxx')
		_p('  command = $cxxTool $cxxFlags $includeFlags -o $out -MMD -MF $out.d $in' .. redirectStderr)
		_p('  depfile = $out.d')
		_p('  description = cc $out')
		_p('')
		
		-- Link Compiler rule
		_p('# Link rule')
		_p('rule cxx')
		_p('  command = $linkTool $linkFlags -o $out -Wl,--start-group $in -Wl,--end-group' .. redirectStderr)
		_p('  description = link $out')
		_p('')
		
		-- Archive tool rule
		_p('# Archive tool rule')
		_p('rule ar')
		_p('  command = $arTool $arFlags $out $in ' .. redirectStderr)
		_p('  description = ar $out')
		_p('')
	end
end 