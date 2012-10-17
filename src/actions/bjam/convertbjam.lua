--
--  Read bjam files, output premake
--

local bjam = premake.actions.convertbjam

	bjam.jamVarsGlobal = {}
	bjam.jamVars = {}		-- local + global vars
	bjam.printAction = false
	bjam.jamDirToProjectList = {}	--jamDirToProjectList[jamfileDir] = list of project fullnames
	bjam.projectList = {} 

newaction {
	trigger		 = "convertbjam",
	shortname	 = "Read bjam files, output premake",
	description  = "Read bjam files, output premake",
	isnextgen    = true,
	ishelp 		 = true,
	execute = function()
		local inputs = {}
		local found = false
		
		if _OPTIONS.tests then
			bjam.runTests()
			return
		end		
		
		for i,a in ipairs(_ARGS) do
			if a == 'print' then
				_OPTIONS['dryrun'] = 'dryrun' 
				bjam.printAction = true
			elseif found then
				table.insert(inputs, a)
			end			
			if a == "convertbjam" then
				found = true
			end 
		end
		if #inputs == 0 then
			inputs = { os.getcwd() }
		end
		
		for _,v in ipairs(inputs) do
			bjam.convert(v)
		end
	end
}

function bjam.convert(filenameOrDir)

	if os.isdir(filenameOrDir) then
		local dir = path.getabsolute(filenameOrDir)
		local files = os.matchfiles(dir..'/**Jam*')
		for _,f in ipairs(files) do
			bjam.convert(f)
		end

	elseif os.isfile(filenameOrDir) then
		local filename = filenameOrDir
		local jamList = bjam.read(filename)
		bjam.jamRootDir = bjam.getJamRootDir(filename)
		if not bjam.jamRootDir then
			error("Could not find Jamroot")
		end
		
		if #jamList > 0 then
			if bjam.printAction then
				bjam.print(jamList, filename)
			else
				bjam.output(jamList, filename)
			end
		end
		--return jamList
	end
end

function bjam.getJamRootDir(filename)
	local dir = path.getdirectory(path.getabsolute(filename))
	
	-- check if the current jamroot is still correct
	if bjam.jamRootDir then
		if dir:startswith(bjam.jamRootDir) then
			return bjam.jamRootDir
		end
	end
	
	-- find Jamroot
	local p = dir
	while p and p ~= '/' do
		local files = os.matchfiles(path.join(p, "Jamroot"))
		if #files > 0 then
			return p..'/'
		end
		p = path.getdirectory(p)
	end
	return nil
end

local function mergeVars(dest, new, keyHint)
	if not new then return end
	if type(new) == 'string' then new = { new } end
	
	local destK = dest
	if keyHint and type(keyHint) == 'string' then
		dest[keyHint] = dest[keyHint] or {}
		if type(dest[keyHint]) == 'string' then
			dest[keyHint] = { dest[keyHint] }
		end
		destK = dest[keyHint]
	end
	
	for k,v in pairs(new) do
		if type(k) == 'number' then
			table.insert( destK, v )
		else
			if dest[k] and type(dest[k]) == 'string' then dest[k] = { dest[k] } end 
			if type(v) == 'table' or (type(dest[k]) == 'table') then
				dest[k] = dest[k] or {}
				if type(v) ~= 'table' then v = { v } end
				for _,v2 in ipairs(v) do
					table.insert( dest[k], v2 )
				end
			else
				dest[k] = v
			end
		end
	end
	return dest
end

function bjam.convertVars(var, evaluate, expandJustEscapedVars)

	if evaluate and var and var.evaluate then
		var = var.evaluate()
	end
	
	if type(var) == 'string' then
		local rv = {}
		local i = 1
		while i <= #var do
			local varIdx = var:find("$(",i,true)
			local spaceIdx = var:find(" ",i,true) or #var
			
			if (not varIdx) or (spaceIdx < varIdx) then
				-- regular word
				local w = var:sub(i, spaceIdx)
				
				-- special case handling, as you can use varName as well as the $(varName) form
				if (not expandJustEscapedVars) and bjam.jamVars[w] then
					mergeVars(rv, bjam.jamVars[w])
				else
					table.insert(rv, w)
				end
				i = spaceIdx+1
			else
				-- there's a variable in this word
				local prefix = var:sub(i,varIdx-1)

				local varEndIdx = var:find(")",varIdx,true)
				local varName = var:sub(varIdx+2, varEndIdx-1)
				
				-- special case for concat, ie. $(var1 var2)
				local varNames = {}
				if varName:find(" ",1,true) then
					varNames = varName:split(" ")
				else
					varNames = { varName }
				end
				
				spaceIdx = var:find(" ",varEndIdx,true) or #var+1
				local suffix = var:sub(varEndIdx+1, spaceIdx-1)
				
				for _,varName in ipairs(varNames) do
					local varValue = bjam.jamVars[varName]
					if varValue or (prefix~='') or (suffix~='') then
						for k,v in pairs(varValue) do
							if type(v) ~= 'table' then v = { v } end
							
							for _,v2 in ipairs(v) do
								local w = prefix..v2..suffix
								
								-- hacky, should really have a clean way to expand variables
								if bjam.jamVars[w] then
									mergeVars(rv, bjam.jamVars[w])
								else
									mergeVars(rv, w, k)
								end
							end
						end
					end
				end
				i = spaceIdx+1
			end
		end
		-- check if we need another pass, eg. for $X/$Y
		repeat 
			local expanded = false
			for k,v in pairs(rv) do
				if type(v) == 'string' and v:find("$(",1,true) then
					local exp = bjam.convertVars(v, evaluate, expandAlways)
					rv[k] = nil
					mergeVars(rv,exp)
					expanded = true
					break
				end
			end
		until not expanded
		return rv
	elseif type(var) == 'table' then
		local rv = {}
		for k,v in pairs(var) do
			local vExp = bjam.convertVars(v, evaluate, expandAlways)
			mergeVars(rv, vExp, k)
		end
		return rv
	elseif not var then
		return {}
	elseif type(var) == 'function' then
		return nil
	else
		error("Unexpected : "..tostring(var))
	end
end

function bjam.convertVarsFlat(var, evaluate, expandAlways)
	local varExp = bjam.convertVars(var, evaluate, expandAlways)
	return table.concat(varExp, ' ')
end

local indentIdx = 0
local indentStr = ''
local output = {
	file = nil,
	fileStack = {},
	written = {}
}
local printBeforeNextPrint = nil

local function p(s)
	
	if not s then return end

	if printBeforeNextPrint then
		if s == '' then return end
		if _OPTIONS.dryrun then 
			print(printBeforeNextPrint)
		else
			output.file:write(printBeforeNextPrint..'\n')
		end
		printBeforeNextPrint = nil
	end

	if _OPTIONS.dryrun then 
		print(indentStr..s)
	else
		output.file:write(indentStr..s..'\n')
	end
end
local function indent(change) 
	indentIdx = math.max(0, indentIdx+change)
	indentStr = string.rep(' ',indentIdx)
end

local function printList(cmd, list, maxOnOneLine)
	maxOnOneLine = maxOnOneLine or 8
	if not list or #list == 0 then
		return
	end
	
	-- remove duplicates
	list = unique(list)
	table.sort(list)
	
	if maxOnOneLine < 0 then
		-- print the command for each line
		for _,v in ipairs(list) do
			p(cmd .. ' "' .. v .. '"')
		end
	
	elseif #list > maxOnOneLine then
		p(cmd .. ' {')
		indent(2)
		for _,f in ipairs(list) do
			p('"'..f..'",')
		end
		indent(-2)
		p('}')
	
	else
		p(cmd .. ' "'..table.concat(list, ' ')..'"')
	end
end

function bjam.printJam(jam)
	indent(2)
	if jam == 'string' then
		p(jam)
	else
		for k,v in pairs(jam) do
			if type(v) == 'table' then
				p(tostring(k)..'=')
				bjam.printJam(v)
			else
				p(tostring(k)..'='..tostring(v))
			end
		end
	end
	indent(-2)
end

function bjam.print(jamList, jamFilename)
	for i,jam in ipairs(jamList) do
		p('Jam#'..i)
		
		bjam.printJam(jam)
	end
end

function bjam.output(jamList, jamFilename)
	local dir = path.getdirectory(path.getabsolute(jamFilename))
	local dirName = path.getbasename(dir)
	local parentDirName = path.getbasename(path.getdirectory(dir))
	local outputFilename = path.join(dir, "premake_"..dirName..".lua")
	local prjPrefix = ''
	
	if #jamList == 0 then
		return
	end
	
	if os.isfile(outputFilename) then
		local f = io.open(outputFilename, "r")
		local text = f:read("*a")
		f:seek("set",0)
		local fileHeader = f:lines()()
		f:close()
		if fileHeader and not fileHeader:startswith('-- Autogenerated premake file from') then
			local alternateName = outputFilename .. '~'
			print("Non-autogenerated Premake file already exists : "..outputFilename..', wrote to '..path.getname(alternateName))
			outputFilename = alternateName
			if not _OPTIONS.dryrun then 
				local prefixes = Seq:gmatch(text, 'projectprefix[ (]*"([^"]*)"')
				local prjs = Seq:gmatch(text, 'project[ (]*"([^"]*)"')
				local libs = Seq:gmatch(text, 'lib[ (]*"([^"]*)"')
				local exes = Seq:gmatch(text, 'exe[ (]*"([^"]*)"')
				local objs = Seq:gmatch(text, 'obj[ (]*"([^"]*)"')
				local usage = Seq:gmatch(text, 'usage[ (]*"([^"]*)"')
				
				local prefix = prefixes:first() or ''
				
				for _,p in prjs:concat(libs):concat(objs):concat(exes):concat(usage):each() do
					bjam.jamDirToProjectList[dir] = bjam.jamDirToProjectList[dir] or {}
					local prj = {}
					prj.name = prefix .. p
					prj.shortname = p:match(".*/([^/]*)") or p
					bjam.jamDirToProjectList[dir][prj.shortname] = prj
				end
			end  
		end
	end
	if output.written[outputFilename] then
		-- already written
		return nil
	end	
	if not _OPTIONS.dryrun then
		table.insert( output.fileStack, output.file ) 
		output.file = io.open(outputFilename, "w+")
		output.filename = outputFilename
	end

	-- hacky setup
	if jamFilename == 'Jamroot' then
		bjam.jamVarsGlobal['repo'] = { dirName }
	else
		bjam.jamVarsGlobal['repo'] = { parentDirName }
	end
	bjam.jamVarsGlobal['dist'] = bjam.jamVarsGlobal['repo']
	bjam.jamVarsGlobal['TRC_SYSTEM'] = { os.getenv("TRC_SYSTEM") }
	bjam.jamVars = table.deepcopy(bjam.jamVarsGlobal)
	local pathFromRepo = path.getrelative( repoRoot, path.getdirectory(path.getdirectory(jamFilename)) )
	if not pathFromRepo:endswith('/') then
		pathFromRepo = pathFromRepo ..'/'
	end 
		
	local pathAliases = {}
	pathAliases['hyp2%-client/Client/([^/]*)'] = "hyp2%-client/%1"
	pathAliases['hyp2/client/([^/]*)'] = "hyp2%-client/%1"
	pathAliases['^Client/([^/]*)'] = "hyp2%-client/%1"
	pathAliases['^boost/boost$'] = "boost"
	 
	local pathFields = toSet({ "use", "excludes", "sources", "name", "protofiles" })
	local function formatPath(p, prefix)
		if not p then return nil end
		
		if type(p) == 'table' then
			for k,v in pairs(p) do
				if type(k) == 'number' or pathFields[k] then
					p[k] = formatPath(v, prefix)
				end
			end
			return p
		end
		
		local str = p

		str = str:replace("//","/")
		
		if str:startswith("/") then
			str = str:sub(2)
		end
		if prefix then
			-- Prepend the project name prefix to the library
			str = prefix .. '/'.. str
		end
		if str:startswith("./") then
			str = str:sub(3)
		end
		for m,p in pairs(pathAliases) do
			str = str:gsub(m,p)
		end
		return str
	end
	
	-- header is used as a signature that it's safe to update the file
	--local jamfileDate = os.date("%c", os.stat(jamFilename).mtime)
	p('-- Autogenerated premake file from ' .. parentDirName..'/'..dirName..'/'..path.getname(jamFilename) ) --.. ' dated '..jamfileDate)
	local prj = {}	-- premake prj
	local processingIdx = 0
	
	prjPrefix = formatPath(pathFromRepo)
	if prjPrefix:endswith('/') then
		prjPrefix = prjPrefix:sub(1,#prjPrefix-1)
	end
	
	local function processReqs(prj, reqs)
		-- remove unused reqs
		local ignoreList = { 
			dependency = "Jamfile", 
			threading = "multi" 
		}
		
		prj.use = prj.use or {}
		
		local numReqs = #prj
		for k,v in pairs(reqs or {}) do
			mergeVars(prj, bjam.convertVars(v), k)
			numReqs = numReqs + 1
		end 
		
		if prj.library then
			table.insertflat( prj.use, prj.library )
			prj.library = nil
		end
		
		for i,prjName in ipairs(prj.use or {}) do
			prj.use[i] = formatPath(prjName)
			numReqs = numReqs + 1
		end
		
		for key, pattern in pairs(ignoreList) do
			if prj[key] then
				for i,v in ipairs(prj[key]) do
					if v:match(pattern) then
						table.remove( prj[key], i )
						if #prj[key] == 0 then
							prj[key] = nil
							numReqs = numReqs - 1
						end 
					end 
				end
			end
		end

		for k,v in pairs(prj) do
			prj[k] = formatPath(v)
		end

		return numReqs
	end
	
	local function processSources(prj, jam)
		local srcExp = bjam.convertVars(jam.sources)
		prj.sources = prj.sources or {}
		prj.use = prj.use or {}
		local sourceFiles = {}
		for k,v in pairs(srcExp) do
			if type(k) ~= 'number' then
				sourceFiles[k] = v
			elseif v:startswith('/') then
				jam.use = jam.use or {}
				table.insert( jam.use, v:sub(2) )
			else
				table.insert( sourceFiles, v )
			end
		end			
		mergeVars( prj, sourceFiles, 'sources' )
		mergeVars( prj, bjam.convertVars(jam.use), 'use' )
		local defaultBuild = bjam.convertVars(jam.defaultBuild)
		if not table.isempty(defaultBuild) then
			mergeVars( prj, defaultBuild, 'defaultBuild' )
		end
		if prj.protofiles and prj.use then
			prj.use = table.exceptValues(prj.use, 'system/protobuf')
		end
		if jam.ureqs then
			prj.ureqs = bjam.convertVars(jam.ureqs)
			if prj.ureqs.library then
				mergeVars( prj.ureqs, prj.ureqs.library, 'use' )
				prj.ureqs.library = nil
			end
			-- remove redundant features
			if prj.ureqs.use then
				for _,u in ipairs(prj.use) do
					prj.ureqs.use[u] = nil
				end
				if #prj.ureqs.use == 0 then
					prj.ureqs.use = nil
				end
			end
			if prj.ureqs.protofiles then
				if table.equals(prj.protofiles, prj.ureqs.protofiles) then
					prj.ureqs.protofiles = nil
				end
				prj.ureqs.use = table.exceptValues(prj.ureqs.use, '/system//protobuf')
			end
			if prj.ureqs['implicit-dependency'] and prj.protofiles then
				local ureqs = prj.ureqs['implicit-dependency']
				for k,v in pairs(ureqs) do
					if v:match('\.pb\.cc$') then
						ureqs[k] = nil
					end
				end
				
				if #ureqs == 0 then 
					prj.ureqs['implicit-dependency'] = nil 
				end
			end
			if table.isempty(prj.ureqs) then
				prj.ureqs = nil
			end			
		end
		local systemlibs = bjam.convertVars(jam.systemlibs)
		if not table.isempty(systemlibs) then
			mergeVars( prj, systemlibs, 'use' )
		end
		
		prj.feature = jam.feature
		
		-- only used by obj workaround & libraries in source lists without <library> tag  
		if srcExp.define then
			prj.define = prj.define or {}
			local srcExp = bjam.convertVars(jam.sources)
			mergeVars( prj.define, srcExp.define )
		end
		if srcExp.use then
			prj.use = prj.use or {}
			mergeVars( prj.use, srcExp.use )
		end
		if srcExp.library then
			prj.use = prj.use or {}
			mergeVars( prj.use, srcExp.library )
		end
	end
	
	function testForUnusedJam(jam, usedList)
		usedList = toSet(usedList)
		local unused = {}
		for k,v in pairs(jam) do
			if not usedList[k] then
				unused[k] = v
			end
		end
		if #unused > 0 then
			p("--[[ Unused : ")
			bjam.printJam(unused)
			p("]]")
		end		
	end
	
	local defaultUsage
	local activeConfiguration = nil
	local toInclude = {}
	function processJam(scopedJamList)
		local prj = {}
		if not scopedJamList or type(scopedJamList) ~= 'table' then
			error("Invalid argument")
		end 
		if #scopedJamList == 0 then
			scopedJamList = {scopedJamList}
		end
		for jamNumber,jam in ipairs(scopedJamList) do
			processingIdx = jamNumber
			
			local function processFeatures(prj, exceptUses)
				printList('protobuf', prj.protofiles, 10000)
				local useList = prj.use
				if exceptUses then
					useList = Seq:new(useList):except(exceptUses):toTable()
				end
				--[[if prj.link then
					if prj.link[1] == "static" then
						p('kind "StaticLib"')
					elseif prj.link[1] == "shared" then
						p('kind "SharedLib"')
					end
				end
				]]
				if prj.type ~= 'obj' and prj.type ~= 'repo' then
					printList('uses', useList, 1)
				end
				printList('define', prj.define, 1)
				printList('cflags', prj.cflags, 1)
				
				
				if prj.warnings then
					for _,w in ipairs(prj.warnings) do
						if w == "off" then
							p('flags "Warnings=Off"')
						else
							p("-- Unsupported bjam : warnings="..tostring(w))
						end
					end
				end
				
				if prj.linkflags then
					p('linkflags "'..table.concat(prj.linkflags, ' ')..'"')
				end
				
				if prj['whole-archive'] then
					p('flags "WholeArchive"')
				end
				
				for req,value in pairs(prj) do
					if value[1] == 'on' then
						p('uses "'..req..'"')
					end
				end
								
				-- check for unusual reqs
				local ignoreList = toSet( { "name", "use", "define", "cflags", "sources", "feature", "excludes", 
					"shortname", "protofiles", "warnings", "linkflags", "whole-archive", "ureqs", "systemlibs", "type" } )
				for req,value in pairs(prj) do
					if not ignoreList[req] then
						if not table.isempty(value) and value[1] ~= 'on' then
							p("-- Unsupported bjam : "..tostring(req)..' = '..mkstring(value))
						end
					end
				end
				if prj.type ~= 'towerscript' then
					p('')
				end
			
			end
			
			if activeConfiguration and not jam.condition then
				indent(2)
				p('configuration {}')
				p('')
				indent(-2)
				activeConfiguration = nil
			end
			
			if jam.type == 'project' or  jam.type == 'tde-lib' or jam.type == 'lib' or jam.type == 'obj' 
				or jam.type == 'exe' or jam.type == 'repo' or jam.type == 'towerscript' 
			then
				prj = {}
				local prjName = bjam.convertVarsFlat(jam.name, false, true)
				prjName = formatPath(prjName)
				if jam.type == 'project' then
					--prjPrefix = prjName
					p('projectprefix "'..prjPrefix..'/"')
				elseif defaultUsage then
					prj.use = prj.use or {}
					table.insert( prj.use, defaultUsage )
				end

				prj.shortname = prjName:match("[^/]*$") or prjName

				if (bjam.projectList[prjPrefix..'/'..prjName] or {}).isReal then
					-- duplicate project name already exists, (eg. hyp2-client/lib3/datasources/listen), separate them
					prjName = path.getname(dir)..'/'..prjName
				end				
				prj.name = prjPrefix .. '/'..prjName
				prj.type = jam.type
								
				processSources(prj, jam)
				local numReqs = processReqs(prj, jam.reqs)
				--local numReqs = #prj.use + #prj.sources + #(prj.define or {}) 
				
				-- add project name as a jam var alias
				bjam.jamVars[prjName] = { use = prjName }
				
				if (not jam.sources) and (numReqs == 0) and table.isempty(jam.ureqs or {}) then
					-- empty project
				else
				
					p('')
					if prj.type == 'exe' then
						p('exe \"'..prjName.."\"")
					elseif prj.type == 'lib' or prj.type == 'tde-lib' then
						p('lib \"'..prjName.."\"")
					elseif prj.type == 'obj' then
						p('obj \"'..prjName.."\"")
					elseif prj.type == 'project' then
						p('usage \"'..prjName.."\"")
						defaultUsage = prjName
					elseif prj.type == 'repo' then
						local deps = concat(prj.sources, prj.use)
						if prj.sources then
							p('solution( "'.. jam.name ..'", "'.. table.concat(deps, ' ') ..'" )')
						else
							p('solution( "'.. jam.name ..'" )')
						end
					elseif prj.type == 'towerscript' then
						p('script( "'..prjName..'", "'..table.concat( prj.sources, ' && ')..'" )')
					else
						error("Not implemented")
					end
					indent(2)
					
					if prj.type ~= 'repo' and prj.type ~= 'towerscript' then
						printList('files', prj.sources)
					end
					--[[if prj.type ~= 'obj' then
						printList('uses', prj.systemlibs)
					end]]
					printList('excludes', prj.excludes)
					
					processFeatures(prj)
					
					if prj.feature then
						processJam(prj.feature)
					end
					
					if prj.ureqs then
						printBeforeNextPrint = 'usage()'
						processFeatures(prj.ureqs, prj.use)
						printBeforeNextPrint = nil
					end
					
					testForUnusedJam(jam, { "type", "sources", "reqs", })

					if prj.type ~= 'project' then
						prj.isReal = true
					end
					bjam.jamDirToProjectList[dir] = bjam.jamDirToProjectList[dir] or {}
					bjam.jamDirToProjectList[dir][prj.shortname] = prj
					bjam.projectList[prjPrefix..'/'..prjName] = prj
					
					indent(-2)
				end -- empty project
			
				
			elseif jam.type == 'feature' then
				if jam.condition then
					local cfg = Seq:new(jam.condition):getKeys():select(function(v) return '"'..v..'"' end)
					indent(-2)
					p('usage '.. cfg:mkstring(', ') )
				end
				indent(2)
				processFeatures(jam.ifTrue)
				indent(-2)
			
			
			elseif jam.type == 'local' or jam.type == 'path-constant' or jam.type == 'constant' then
				local value = bjam.convertVars(jam.varValue, true)
				bjam.jamVars[jam.varName] = value
			
			elseif jam.type == 'alias' then
				local value = bjam.convertVars(jam.varValue, true)
				bjam.jamVars[jam.varName] = value
				
				bjam.jamDirToProjectList[dir] = bjam.jamDirToProjectList[dir] or {}
				local prj = bjam.jamDirToProjectList[dir][jam.varValue[1]]
				bjam.jamDirToProjectList[dir][jam.varName] = prj
			
			elseif jam.type == 'global' then
				local value = bjam.convertVars(jam.varValue, true)
				bjam.jamVarsGlobal[jam.varName] = value
				bjam.jamVars[jam.varName] = value
				
			elseif jam.type == 'obj' then
				-- Treat obj as an alias for the .cpp file, as .o files will always be passed to another build project
				local value = bjam.convertVars(jam.sources, true)
				prj = {}
				processReqs(prj, jam.reqs)
				value.define = prj.define
				value.use = prj.use
				
				bjam.jamVars[jam.name] = value
	
			elseif jam.type =='tde-test' or jam.type == 'unit-tests' then
				local srcs = bjam.convertVarsFlat(jam.sources)
				local testPrj = {}
				processReqs(testPrj, jam.reqs)
				
				for i,u in ipairs(testPrj.use) do
					if not u:contains('/') then
						testPrj.use[i] = prjPrefix ..'/'.. u
					end
				end
				
				local uses = mkstring( testPrj.use, ' ')
				indent(2)
				
				local cmd = iif( jam.type =='tde-test', 'tdeUnitTests', 'unitTests' )
				if #uses == 0 then
					p(cmd ..' "'..srcs..'"')
				else
					p(cmd ..'( "'..srcs..'", "'..uses..'")') 
				end
				
				indent(-2)
				
			elseif jam.type == 'protos' then
			
				-- add cppVarName as a local variable mapping to the resultant .cpp files
				local protofiles = bjam.convertVars(jam.protofiles)
				--p('protobuf "'..table.concat(protofiles, ' ')..'"')
				
				local protoCppFiles = Seq:new(protofiles):select(function(v) return path.setextension(v, ".pb.cc") end):toTable()
				protoCppFiles.protofiles = protofiles
				bjam.jamVars[jam.cppVarName] = protoCppFiles
				-- add headerVarName as a local variable mapping to the resultant .cpp files
				if jam.headerVarName then
					local protoHeaderFiles = Seq:new(protofiles):select(function(v) return path.setextension(v, ".pb.h") end):toTable()
					protoHeaderFiles.protofiles = protofiles 
					bjam.jamVars[jam.headerVarName] = protoHeaderFiles
				end
				 
			
				
			elseif jam.type == 'for' then
				local loopVar = jam.varName
				local loopList = bjam.convertVars(jam.loopList, true)
				for _,v in ipairs(loopList) do
					bjam.jamVars[loopVar] = { v }
					processJam(jam.loopCode)
				end
				
			elseif jam.type == 'if' then
				local function evaluate(node)
					if not node then return nil
					elseif node.type == 'not' then
						return not evaluate(node.lhs)
					elseif node.type == 'in' then
						local lhs = evaluate(node.lhs)
						local rhs = toSet(evaluate(node.rhs))
						return rhs[lhs]
					elseif node.type == 'brackets' then
						return evaluate(node.lhs)
					elseif not node.type then
						-- values
						return bjam.convertVars(node)
					else
						error("Unknown code \""..tostring(node.type).."\"")
					end
				end
				if evaluate(jam.condition) then
					processJam(jam.ifTrueCode)
				end
			
			elseif jam.type == 'build-project' then
				local childPrjName = bjam.convertVarsFlat(jam.prjName, true)
				toInclude[childPrjName] = childPrjName

			elseif jam.type == 'use-project' then
				local alias = bjam.convertVarsFlat(jam.projectAlias)
				local dir = jam.projectFullname:match("(.*)//")
				if dir then
					toInclude[dir] = dir
				end
				local fullname = bjam.convertVarsFlat(jam.projectFullname)
				alias = path.wildcards(alias)
				fullname = path.wildcards(fullname)
				pathAliases[alias] = fullname
				

			elseif jam.type == 'explicit' then
				p("--Not implemented : explicit "..bjam.convertVarsFlat(jam.explicit))
				
			elseif jam.type == 'export' and (
				jam.exportType == 'lib' or jam.exportType == 'exe' or jam.exportType == 'obj'  
				or jam.exportType == 'shlib' or jam.exportType == 'stlib'
			) then
				local srcExp = bjam.convertVars(jam.sources)
				
				for i,s in ipairs(srcExp) do
					local expDir = s:match("(.*)//")
					
					if expDir then
						toInclude[expDir] = expDir
						
						expDir = path.join(dir, expDir)
						local exportPrjs = bjam.jamDirToProjectList[expDir]
						if not exportPrjs then
							if os.isfile(expDir..'/Jamfile') then
								bjam.convert(expDir..'/Jamfile')
							elseif os.isfile(expDir..'/Jamroot') then
								bjam.convert(expDir..'/Jamroot')
							else
							 	error("Could not find Jamfile in directory "..expDir) 
							end
							
							exportPrjs = bjam.jamDirToProjectList[expDir]
							
							if not exportPrjs then 
								bjam.convert(expDir..'/Jamfile')
								error("No Jam projects in directory "..expDir) 
							end 
						end
						
						local shortname = s:match(".*//([^/]*)") or s
						local ePrj = exportPrjs[shortname]
						if not ePrj then 
							error("Could not find project "..shortname.." in directory "..expDir..', used by project '..jamFilename) 
						end
						s = ePrj.name
					end
					
					srcExp[i] = formatPath(s) 
				end
				local exportAlias = jam.exportName
				local len = (scopedJamList.maxExportNameLen or 0)
				local padding = string.rep(' ',len-#exportAlias)
				if #srcExp > 0 then
					p('export( '..padding..'"'..exportAlias..'", "'..table.concat(srcExp, ' ')..'" )')
				end
				
			elseif jam.type == 'end' then
				-- do nothing
				
			else
				if not jam.comment then
					if jam.line then
						p("--[[ Not implemented bjam " ..jam.type.. " : "..jam.line:replace("]]", "] ]").." ]]")
					elseif jam.type then
						p("--Not implemented : "..jam.type)
					end
				end
			end
			if jam.comment then
				p("--"..jam.comment)
			end 
		end -- for scopedJamList
		
	end -- processJam
	
	processJam(jamList)
	p('')
	local includeList = getKeys(toInclude)
	table.sort(includeList)
	if not table.isempty(includeList) then
		for _,dir in ipairs(includeList) do
			p("include \""..dir.."/\"")
		end
		p('')
	end
	if output.file then 
		output.file:close()
		output.file = table.remove(output.fileStack)
		print("Wrote "..outputFilename)
		output.written[output.filename] = output.filename 
	end
	
end

