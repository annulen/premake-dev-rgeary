--
-- _clean.lua
-- The "clean" action: removes all generated files.
-- Copyright (c) 2002-2009 Jason Perkins and the Premake project
--

	premake.actions.clean = { }
	local clean = premake.actions.clean
	local project = premake5.project


--
-- Clean a solution or project specific directory. Uses information in the
-- project object to build the target path.
--
-- @param obj
--    A solution or project object.
-- @param pattern
--    A filename pattern to clean; see premake.project.getfilename() for
--    a description of the format.
--

	function clean.directory(obj, pattern, removeParentsIfEmpty)
		if pattern == '.' then
			return false		-- avoid deleting everything
		end
		local fname = premake.project.getfilename(obj, pattern)
		os.rmdir(fname)
		if removeParentsIfEmpty then
			os.rmdirParentsIfEmpty(fname)
		end
		return true
	end


--
-- Clean a solution or project specific file. Uses information in the project
-- object to build the target filename.
--
-- @param obj
--    A solution or project object.
-- @param pattern
--    A filename pattern to clean; see premake.project.getfilename() for
--    a description of the format.
--

	function clean.file(obj, pattern)
		local fname = premake.project.getfilename(obj, pattern)
		os.remove(fname)
	end


--
-- Register the "clean" action.
--

	newaction {
		trigger     = "clean",
		description = "Remove all binaries and generated files",
		
		isnextgen 	= true,

		onsolution = function(sln)
			for action in premake.action.each() do
				if action.oncleansolution then
					action.oncleansolution(sln)
				end
			end
		end,
		
		onproject = function(prj)
			for action in premake.action.each() do
				if action.oncleanproject then
					action.oncleanproject(prj)
				end
			end

			if (prj.objectsdir) then
				clean.directory(prj, prj.objectsdir)
			end

			-- build a list of supported target platforms that also includes a generic build
			local platforms = prj.solution.platforms or { }
			if not table.contains(platforms, "Native") then
				platforms = table.join(platforms, { "Native" })
			end

			if not prj.isUsage then
				for cfg in project.eachconfig(prj) do
					if cfg.objdir then
						clean.directory(prj, cfg.objdir, true)
					end
					if cfg.linktarget then
						clean.directory(prj, cfg.linktarget.directory, true)
					end
	
					-- call action.oncleantarget() with the undecorated target name
					local target = cfg.project.basedir
					for action in premake.action.each() do
						if action.oncleantarget then
							action.oncleantarget(target)
						end
					end
				end
			end
		end
	}
