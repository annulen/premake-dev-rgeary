--
-- Print action, explains what each configuration will do
--  Useful for finding & explaining compiler flags
--

-- capital P to distinguish it from the global function print()
	premake.actions.Print = {}
	local Print = premake.actions.Print
	local config = premake5.config
	local project = premake5.project
	
	newaction {
		trigger		= "print",
		shortname	= "Print meta-action",
		description = "Explains the commands to be run for each configuration",
		
		isnextgen	= true,
		
		onsolution 	= function(sln) Print.onSolution(sln) end,
		onproject 	= function(prj) Print.onProject(prj) end,	
	}
	
	local indentStr = ''
	local function indent(change)
		local len = #indentStr + change
		indentStr = ''
		for i = 1,len do
			indentStr = indentStr .. ' '
		end
	end
	
	local function pRecursive(name, obj, depth)
		depth = depth or 2
		local str = iif(name, tostring(name) .. ' : ', '')
		if( obj and type(obj) == "table" ) then
			if depth < 0 then
				print(indentStr .. str .. tostring(obj))
			else
				if( isStringSeq(obj) ) then
					print(indentStr .. str .. table.concat(getIValues(obj), ', '))
				else
					print(indentStr .. str)
					indent(2)
					for k,v in pairs(obj) do
						pRecursive(k, v, depth-1)
					end
					indent(-2)
				end
			end
		elseif obj then
			print(indentStr .. str .. tostring(obj))
		else
			print(indentStr .. tostring(name))
		end
	end
	
	-- need to separate out this from pRecursive otherwise calling with tables will put the 2nd value as the depth
	local function p(name, obj)
		return pRecursive(name, obj, nil)
	end
	
	function Print.onSolution(sln)
		p('Solution ', sln.name)
		indent(2)
		p('platforms', getIValues(sln.platforms))
		p('language', sln.language)
		p('basedir', sln.basedir)
		p('configurations', sln.configurations)
		indent(-2)
	end
	
	function Print.onProject(prj)
		if prj.isUsage then
			p('Usage', prj.name)
			return nil
		end

		p('Project', prj.name)
		
		indent(2)
		for cfg in project.eachconfig(prj) do
			p('config', cfg.shortname)
			local toolset = premake.tools[cfg.toolset]
			p('toolset ' .. cfg.toolset)
			indent(2)
				--[[p('cppflags', toolset:getcppflags(cfg))
				p('cflags', toolset:getcflags(cfg))
				p('cxxflags', toolset:getcxxflags(cfg))
				p('sysflags', toolset.sysflags)]]
				
				local function flattenArgs(t)
					local t2 = {}
					for k,v in pairs(t) do
						if type(k) ~= 'number' then
							if v ~= '' then
								table.insert(t2, '$'..k)
							end
						else
							table.insert(t2, v)
						end
					end
					return t2
				end
				
				local compileTool = toolset:getCompileTool(cfg)
				local linkTool = toolset:getLinkTool(cfg)
				
				local compileSysflags = compileTool:getsysflags(cfg)
				local compileCmdArgs = compileTool:decorateInputs(cfg, '$out', '$in')
				--local compileVars = Seq:new(compileCmdArgs):getKeys():prependEach('$'):prepend(compileSysflags):mkstring(' ')
				local compileCmdArgsFlat = flattenArgs(compileCmdArgs)
				local linkCmdArgs = linkTool:decorateInputs(cfg, '$out', '$in')
				local linkVars = Seq:new(linkCmdArgs):getKeys():prependEach('$'):prepend(linkSysflags):mkstring(' ')
				local linkCmdArgsFlat = flattenArgs(linkCmdArgs)
				
--				p('cfg          ', cfg)
				p('flags        ', cfg.flags)
				p('compiler tool', compileTool.toolName)
				p('compiler bin ', compileTool:getBinary())
				p('compile sysflags', compileSysflags)
				for k,v in pairs(compileCmdArgs) do
				 p(' .' .. tostring(k) ..' = '..v)
				end				
				p('compile cmd  ', compileTool:getCommandLine(compileCmdArgsFlat))
				p('objdir       ', cfg.objdir)
				p('link cmd     ', linkTool:getCommandLine(linkCmdArgsFlat))
				p('link flags   ', linkTool:getsysflags(cfg), ' ')
				for k,v in pairs(linkCmdArgs) do
				 p(' .' .. tostring(k) ..' = '..v)
				end				
				p('link target  ', cfg.buildtarget.directory .. '/' .. cfg.buildtarget.name)
				if 0 < #cfg.prebuildcommands then
					p('prebuild cmd ', table.concat(cfg.prebuildcommands, "\n" .. indentStr .. '                '))
				end
				if 0 < #cfg.postbuildcommands then
					p('postbuild cmd', table.concat(cfg.postbuildcommands, "\n".. indentStr .. '                '))
				end
			indent(-2)
		end
		indent(-2)
		for k,v in pairs(prj) do
			--print('  ' .. tostring(k) .. ' = ' .. tostring(v))
		end
	end
	