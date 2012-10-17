--
--	Unit tests for bjam code
--

local bjam = premake.actions.convertbjam

local function test(a,b)
	if a ~= b then
		error("Not equal : "..tostring(a).." == "..tostring(b),2)
	else
		print("Success : "..tostring(a).." ~= "..tostring(b))
	end
end

function bjam.runTests()
	bjam.jamVars["repo"] = { "tae" }
	bjam.jamVars["repos"] = { "tae", "tde" }
	bjam.jamVars["twos"] = { "two", "dos" }
	bjam.jamVars["abc"] = { "a", "b", "c" }
	
	local function convertVars(v)
		return table.concat(bjam.convertVars(v), ' ')
	end
	
	test(convertVars("repo"), "repo")
	test(convertVars("$(repo)"), "tae")
	test(convertVars("a$(repo)"), "atae")
	test(convertVars("$(repo)s"), "taes")
	test(convertVars("a$(repo)s"), "ataes")
	test(convertVars("ab$(repo)s"), "abtaes")
	test(convertVars("ab$(repos)s"), "abtaes abtdes")
	test(convertVars("ab$(repo repos)s"), "abtaes abtaes abtdes")
	test(convertVars("$(repo)d $(twos)s"), "taed twos doss")
	test(convertVars("p$(repo)/$(twos)s"), "ptae/twos ptae/doss")
	test(convertVars("$(twos)/$(twos)"), "two/two two/dos dos/two dos/dos")
	test(convertVars("$(abc)/$(abc)"), "a/a a/b a/c b/a b/b b/c c/a c/b c/c")
	test(convertVars("$(abc)/$(abc)/$(abc)"), "a/a/a a/a/b a/a/c a/b/a a/b/b a/b/c a/c/a a/c/b a/c/c b/a/a b/a/b b/a/c b/b/a b/b/b b/b/c b/c/a b/c/b b/c/c c/a/a c/a/b c/a/c c/b/a c/b/b c/b/c c/c/a c/c/b c/c/c")
	
end