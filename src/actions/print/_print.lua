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

		local uProj = project.getUsageProject(prj.name)
		p('Usage Project', usageProj.name)
		indent(2)
			local ucfg = project.getConfigs(uProj):first() or {}
			for k,v in pairs(ucfg) do
				if v and premake.fields[k] and premake.fields[k].usagefield then
					if type(v) == 'table' then
						if #v > 0 then
							p(k..' = '..table.concat(v, ' '))
						end
					else
						p(k..' = '..tostring(v))
					end
				end
			end
		indent(-2)

		p('RealProject', prj.name)
		indent(2)
		for cfg in project.eachconfig(prj) do
			p('kind', cfg.kind)
			p('uses', cfg.uses)
			p('config', cfg.shortname)
			if cfg.toolset then
				local toolset = premake.tools[cfg.toolset]
				p('toolset ' .. cfg.toolset)
				indent(2)
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
					p('compile cmd  ', compileTool:getCommandLine(compileTool:getBinary(), compileCmdArgsFlat))
					p('objdir       ', cfg.objdir)
					p('link cmd     ', linkTool:getCommandLine(linkTool:getBinary(), linkCmdArgsFlat))
					p('link flags   ', linkTool:getsysflags(cfg), ' ')
					for k,v in pairs(linkCmdArgs) do
					 p(' .' .. tostring(k) ..' = '..v)
					end				
					p('link target  ', cfg.linktarget.directory .. '/' .. cfg.linktarget.name)
					p('build target  ', cfg.buildtarget.directory .. '/' .. cfg.buildtarget.name)
					p('build targetdir', cfg.targetdir )
					if 0 < #cfg.prebuildcommands then
						p('prebuild cmd ', table.concat(cfg.prebuildcommands, "\n" .. indentStr .. '                '))
					end
					if 0 < #cfg.postbuildcommands then
						p('postbuild cmd', table.concat(cfg.postbuildcommands, "\n".. indentStr .. '                '))
					end
				indent(-2)
			end -- if toolset
		end
		indent(-2)
		for k,v in pairs(prj) do
			--print('  ' .. tostring(k) .. ' = ' .. tostring(v))
		end
	end
	