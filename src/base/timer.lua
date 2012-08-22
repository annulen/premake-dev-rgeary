--
-- Timing functions to help improve performance
--

local enabled = {}
local disabled = {}
timer = disabled

enabled.order = {}
enabled.totals = {}				-- { allTime, childTime, numCalls }
enabled.startTime = {}
enabled.stackName = {}
enabled.stackChildTime = {}

function timer.enable()
	timer = enabled
end

function timer.disable()
	timer = disabled
end

function enabled.start(name)
	table.insert( timer.stackName, name )
	table.insert( timer.stackChildTime, 0.0 )
	if not enabled.order[name] then
		table.insert(enabled.order, name)
		enabled.order[name] = 1
	end
	enabled.totals[name] = enabled.totals[name] or { 0.0, 0.0, 0 }
	local t = os.clock()
	timer.startTime[name] = t
	return name
end

function enabled.stop(name_)
	local endTime = os.clock()
	
	if #enabled.stackName == 0 then
		timer.print()
		error('Called timer.stop() with nothing on the timer stack')
	end
	
	local name = table.remove( enabled.stackName )
	if name_ and name ~= name_ then
		error('Mismatched timer.stop. Expected '..name..' got '.. (name_ or '(nil)'))
	end
	local startTime = enabled.startTime[name]
	local childTime = table.remove( enabled.stackChildTime )

	local diff = endTime - startTime
	local totals = enabled.totals[name] or { 0.0, 0.0, 0 }
	enabled.totals[name] = { totals[1] + diff, totals[2] + childTime, totals[3] + 1 }
	if #enabled.stackChildTime > 0 then
		-- add the time to the parent's child time
		local i = #enabled.stackChildTime
		enabled.stackChildTime[i] = enabled.stackChildTime[i] + diff
	end 
end

function enabled.print()
	local totalTime = 0.0
	local maxLen = Seq:new(enabled.totals):getKeys():max()
	local sName = '%'..maxLen..'s'
	for _,name in ipairs(enabled.order) do
		local timeT = enabled.totals[name]
		local selfTime = timeT[1]-timeT[2]
		printf(sName.." : %.4f    (self %.4f  child %.4f   calls %d)", name, timeT[1], selfTime, timeT[2], timeT[3])
		totalTime = totalTime + selfTime
	end
	printf(sName.." : %.4f", 'Total', totalTime)
end

function disabled.start(name) end
function disabled.stop() end
function disabled.print() end
