--
-- Toolset functions
--

	premake.Toolset = {}
	local Toolset = premake.Toolset
	
--
-- All available defined toolsets. New toolsets must add themselves to this table
--
	premake.Toolset.allToolsets = {}
	
	function map(table,fn)
	  rv = {}
	  for key,value in pairs(table) do
	  	rv = rv + fn(key,value)
	  end
	  return rv
	end
	
	function premake.Toolset.getToolsetNames()
	    --toolsetNames = map(Toolset.allToolsets, function(k,v) return k; end)
	    local toolsetNames = {}
		for k,v in pairs(premake.Toolset.allToolsets) do
			table.insert(toolsetNames, k)
		end 
	    return toolsetNames
	end 
--
-- Select a default toolset for the appropriate platform / source type
--

	function premake.Toolset.getdefault(cfg)	
	end
	
	

