-- See comment below
--  Read bjam files, output premake
--
premake.actions.convertbjam = {}
local bjam = premake.actions.convertbjam

function bjam.read(filename)
	local jamList = {}
	local oldDir = os.getcwd()
	
	if os.isdir(filename) then
		error("Expected filename, found directory : "..filename)
	end
	
	filename = path.getabsolute(filename)
	local shortFilename = path.getrelative(oldDir, filename)
	local dir = path.getdirectory(filename)
	
	if filename:contains('/repos') or filename:contains('/super/') or filename:contains('/releases/') 
		or filename:contains('/onload/') or filename:contains('/lowbanddata-client/')
		or filename:contains('/tte') or filename:contains('/tde') or filename:contains('/tce/') or filename:contains('/tae/')
		or dir == path.getabsolute(repoRoot)
	then
		return jamList
	end 
	
	if not filename:endswith('Jamfile') and not filename:endswith('Jamroot') then
		return jamList
	end
	
	os.chdir(dir)
	local file = io.open(filename, "r")
	if not file then
		error("Could not open file "..shortFilename)
	end
	local text = " "..file:read("*a")
	local textParts = text:replace('\t',' '):gsub('[ \n]#[^\n]*','')
		:replace('\n',' '):replace("\r",""):split(' ', true)
	file:close()
	local tokens = Seq:new(textParts)
		:except('')
		:iterate()
	
	local token
	local prevTokens = {}
	local customRules = {}
	local logOutput = {}
	local function logTokens(dest)
		logOutput = dest
	end
	
	customRules['set.intersection'] = {
		invoke = function(args)
			local set = {}
			for _,v in ipairs(args) do
				set[v] = v
			end
			return getKeys(v)
		end
	}
	
	local function nextToken()
		if not tokens then
			token = nil 
			return nil
		end 
		_,token = tokens()
		
		if token then
			table.insert( logOutput, token )
		end
		
		for i=10,1,-1 do
			prevTokens[i+1]=prevTokens[i]
		end
		prevTokens[1] = token
		if not token then
			tokens = nil	-- prevent wrap-around
		end
		return token
	end

	local tokenStack = {}
	local function pushTokens(ts)
		table.insert(tokenStack, tokens)
		tokens = Seq:new(ts):iterate()
		nextToken()
	end
	
	local function popTokens()
		ts = table.remove(tokenStack)
		if ts then
			tokens = ts
		end
	end	
	local function expect(token, expectedToken)
		if token ~= expectedToken then
			errMsg = "Expected \""..tostring(expectedToken).."\", found \""..tostring(token).."\""
			errMsg = errMsg .. '\n in '..shortFilename
			errMsg = errMsg .. '\n '..Seq:new(prevTokens):reverse():mkstring(' ')
			
			error(errMsg,2)
		end
	end
	
	local function expectNext(expectedToken) 
		expect(nextToken(), expectedToken) 
	end
	
	local function readList(includeCurrent)
		local rv = {}
		if not includeCurrent then
			nextToken()
		end
		local symbolList = toSet({ ":", ";", "[", "]", "{", "}", ")" })
		while token do
			if token == '[' then
				-- command
				local cmd = nextToken()
				local arg1 = readList()
				local arg2
				if token == ':' then
					arg2 = readList()
				end
				if cmd == 'glob' or cmd == 'glob-tree' then
					if cmd == 'glob-tree' then
						arg1 = Seq:new(arg1):select(function(v) return v:replace("*","**") end):toTable()
					end
					local cwd = os.getcwd()
					rv.evaluate = function()
						if arg1 and arg1.evaluate then arg1 = arg1.evaluate() end
						if arg2 and arg2.evaluate then arg2 = arg2.evaluate() end
						local oldCwd = os.getcwd()
						os.chdir(cwd)
						local sources = os.matchfiles(unpack(arg1))
						if arg2 then
							local excludes = toSet(os.matchfiles(unpack(arg2)))
							local filteredSources = {}
							for _,v in ipairs(sources) do
								if not excludes[v] then
									table.insert(filteredSources, v)
								end
								sources = filteredSources
							end
						end
						os.chdir(oldCwd)
						return sources
					end
					table.insertflat(rv, arg1)
					rv.excludes = arg2
				
				elseif cmd == 'MATCH' then
					rv.evaluate = function()
						if arg1 and arg1.evaluate then arg1 = arg1.evaluate() end
						if arg2 and arg2.evaluate then arg2 = arg2.evaluate() end
						local rv2 = {}
						for _,regexp in ipairs(arg1) do
							for _,v in ipairs(arg2) do
								local m = string.match(v, regexp)
								if m then
									table.insert(rv2, m)
								end
							end
						end
						return rv2
					end
					
					table.insertflat(rv, arg2)
				
				elseif customRules[cmd] then
					local args = {}
					while token ~= ']' do
						local arg = readList()
						table.insert(args, arg)
					end
					customRules[cmd].invoke(args)
				else
					error("Unknown command "..cmd)
				end
				expect(token, "]")
				nextToken()				
			elseif (not token) or symbolList[token] then
				break
			elseif token:startswith("<") then
				local key,value = token:match("<([^>]+)>([^:]*)")
				--print("with "..tostring(with))
				if value:find("<") then
					value = value:sub(1,value:find("<")-2)
				end
				rv[key] = rv[key] or {}
				if value then
					table.insert(rv[key], value)
				end
				nextToken()
			else
				table.insert(rv, token)
				nextToken()
			end
		end
		return rv
	end
	
	local function readLine()
		local line = nil
		local rv = {}
		popTokens()
		nextToken()
		while token do
			if token == ';' then
				break
			end
			table.insert(rv, token)
			nextToken()
		end
		line = rv
		pushTokens(line)
		return rv
	end
	
	local rules = toSet({ "lib", "exe", "unit-test", "tde-lib", "obj", "provide", "towerscript", })
	
	local skipRules = toSet({ "nfs-install", "release-files", "old-install-to", "install", "release", "list-releases",
		"import", "branch", "sh", "gitrepo", "gitrepo.everything", "list-repos", "actions", "shell",
		"proto-import", "proto-cpp", "tag-bin", "branch", "do-export", "passthrough-props", "cpp2doxy",
		"combo-lib", "list-zip", "generated-file", "generated", "tower-feature", "feature-expand-path", "feature-dep-reqs",
		"export-idir", "export-edir", "export-pdir", "export-dreq",  
	 })
	local todo = toSet({ "make", "rename", })
	
	function processScope()
		local scopeJamList = {}
		local maxExportNameLen = 0
		while token do
			local jam = {}
			jam.type = token
			local line = { token }
			logTokens(line)
			local skip = false
	
			if token == 'project' or token == 'repo' then
				jam.name = nextToken()
				
				nextToken()
				while token == ':' do
					nextToken()
					if token == 'requirements' then
						jam.reqs = readList()
					elseif token == 'usage-requirements' then
						jam.ureqs = readList()
					elseif token == 'build-dir' then
						jam.builddir = readList()
					elseif token == 'system-libs' then
						jam.systemlibs = readList()
					elseif token == 'feature' then
						jam.feature = jam.feature or {}
						local f = {}
						f.type = 'feature'
						
						local condition = nextToken()
						local key,value = condition:match("<([^>]+)>(.*)")
						f.condition = {}
						f.condition[key] = value
						
						f.ifTrue = readList()
						table.insert( jam.feature, f )
					else
						if not jam.sources then
							jam.sources = readList(true)
						end
					end
				end
				if token == 'include-root' then
					--ignore
					nextToken()
				end
				expect(token, nil)
	
			elseif rules[token] then
				if token == 'provide' then jam.type = nextToken() end
				
				jam.name = nextToken()
				if nextToken() == ":" then
					jam.sources = readList()
				end
				if token == ':' then
					-- requirements
					jam.reqs = readList()
				end 
				if token == ':' then
					-- default build flags
					jam.defaultBuild = readList()
				end 
				if token == ':' then
					-- usage requirements
					jam.ureqs = readList()
				end 
				expect(token, nil)
				
			elseif token == 'tde-test' or token == 'unit-tests' then
				jam.name = nextToken()
				if nextToken() == ":" then
					jam.sources = readList()
				end	
				if token == ":" then
					jam.ureqs = readList()
				end
				if token == ":" then
					jam.reqs = readList()
				end
				if token == ":" then
					jam.unknown = readList()
				end
				expect(token, nil)
	
			elseif not token then
				-- do nothing
				skip = true
				
			elseif todo[token] then
				-- TODO
				skip = true
	
			elseif skipRules[token] then
				skip = true
	
			elseif customRules[token] then
				-- to do
				skip = true
	
			elseif token == 'explicit' then
				jam.explicit = readList()
				expect(token, nil)
	
			elseif token == 'export' then
				jam.exportType = nextToken()
				jam.exportName = nextToken()
				maxExportNameLen = math.max( maxExportNameLen, #jam.exportName )
				expectNext(":")
				jam.sources = readList()
				if token == ':' then
					-- ignore
					readList()
				end
				if token == ';' then
					nextToken()
				end
				expect(token, nil)
				
			elseif token == 'protos' then
				jam.cppVarName = nextToken()
				if nextToken() ~= ':' then
					jam.headerVarName = token
					nextToken()
				end
				expect(token, ":")
				jam.protofiles = readList()
				if token == ":" then
					jam.reqs = readList()
				end 
				if token == ":" then
					jam.builddefaults = readList()
				end 
				if token == ":" then
					jam.ureqs = readList()
				end
				expect(token, nil)
	
			elseif token == 'local' then
				jam.varName = nextToken()
				if nextToken() == '=' then
					jam.varValue = readList()
				else
					jam.varValue = {}
				end
				expect(token, nil)
				
			elseif token == 'path-constant' or token == 'constant' then
				jam.varName = nextToken()
				expectNext(":")
				jam.varValue = readList()
				expect(token, nil)
	
			elseif token == 'for' then
				jam.varName = nextToken()
				expectNext('in')
				jam.loopList = readList()
				expect(token, '{')
				nextToken()
				jam.loopCode = processScope()
	
			elseif token == '}' then
				nextToken()
				break
				
			elseif token == 'rule' then
				jam.ruleName = nextToken()
				nextToken()
				if token == '(' then
					jam.ruleArgs = {}
					while token ~= ')' do
						local args = readList()
						table.insert(jam.ruleArgs, args)
					end
					nextToken()
				end
				jam.invoke = function(args) end		-- TODO
				customRules[jam.ruleName] = jam
				expect(token, '{')
				nextToken()
				jam.ruleCode = processScope()
	
			elseif token == 'alias' then
				jam.varName = nextToken()
				expectNext(':')
				jam.varValue = readList()
				if token then
					skip = true
				end
				
			elseif token == 'return' then
				jam.varValue = readList()
	
			elseif token == 'use-project' then
				jam.projectAlias = nextToken()
				expectNext(':')
				jam.projectFullname = nextToken()
				expectNext(nil) 
	
			elseif token == 'if' then
				
				-- build simple evaluation tree
				function addBranch()
					local eval = {}
					nextToken()
					while token do
						if token == '!' then
							eval.type = 'not'
							eval.lhs = addBranch()
						elseif token == '(' then
							eval.type = 'brackets'
							eval.lhs = addBranch()
							return eval
						elseif token == ')' or token == '{' then
							return eval
						elseif token == 'in' then
							eval.type = 'in'
							eval.rhs = {}
						else
							-- append token to lhs or rhs lists
							if eval.rhs then
								table.insert( eval.rhs, token )
							else
								eval.lhs = eval.lhs or {}
								table.insert( eval.lhs, token )
							end
						end
						nextToken()
					end
					return eval
				end
				
				jam.condition = addBranch()
				nextToken()
				jam.ifTrueCode = processScope()
	
			elseif token == 'build-project' then
				jam.prjName = nextToken()
				expectNext(nil)

			elseif token == 'end' then
				expectNext(nil)
	
			else
				-- global var?
				local origToken = token
				jam.type = 'global'
				jam.varName = token
				nextToken()
				if token == '+=' then
					jam.varValue = readList()
					table.insert( jam.varValue, 0, "$("..jam.varName..")" ) 
				elseif token == '=' then
					jam.varValue = readList()
				else
					expect(origToken, "global variable")
				end
				expect(token, nil)
			end
		
			if skip then
				jam.comment = "Not implemented: "..token
				token = nil
			end
			
			jam.line = table.concat(line, ' ')
			table.insert( scopeJamList, jam )
			
			if token == nil then
				readLine()
			end
		end
		scopeJamList.maxExportNameLen = maxExportNameLen
		return scopeJamList
	end -- processScope
	
	readLine()
	jamList = processScope()
	 
	os.chdir(oldDir)
	return jamList
end
