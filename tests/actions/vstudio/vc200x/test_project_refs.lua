--
-- tests/actions/vstudio/vc200x/test_project_refs.lua
-- Validate project references in Visual Studio 200x C/C++ projects.
-- Copyright (c) 2011-2012 Jason Perkins and the Premake project
--

	T.vstudio_vs200x_project_refs = { }
	local suite = T.vstudio_vs200x_project_refs
	local vc200x = premake.vstudio.vc200x


--
-- Setup
--

	local sln, prj

	function suite.setup()
		_ACTION = "vs2008"
		sln = test.createsolution()
		uuid "00112233-4455-6677-8888-99AABBCCDDEE"
		test.createproject(sln)
	end

	local function prepare(platform)
		prj = premake.solution.getproject_ng(sln, 2)
		vc200x.projectReferences(prj)
	end


--
-- If there are no sibling projects listed in links(), then the
-- entire project references item group should be skipped.
--

	function suite.noProjectReferencesGroup_onNoSiblingReferences()
		prepare()
		test.isemptycapture()
	end


--
-- If a sibling project is listed in links(), an item group should
-- be written with a reference to that sibling project.
--

	function suite.projectReferenceAdded_onSiblingProjectLink()
		links { "MyProject" }
		prepare()
		test.capture [[
		<ProjectReference
			ReferencedProjectIdentifier="{00112233-4455-6677-8888-99AABBCCDDEE}"
			RelativePathToProject="MyProject.vcproj"
		/>
		]]
	end

--
-- Project references should always be specified relative to the 
-- project doing the referencing.
--

	function suite.referencesAreRelative_onDifferentProjectLocation()
		links { "MyProject" }
		location "build/MyProject2"
		project("MyProject")
		location "build/MyProject"
		prepare()
		test.capture [[
		<ProjectReference
			ReferencedProjectIdentifier="{00112233-4455-6677-8888-99AABBCCDDEE}"
			RelativePathToProject="..\MyProject\MyProject.vcproj"
		/>
		]]
	end
		
