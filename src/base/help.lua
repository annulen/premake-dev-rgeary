--
-- help.lua
-- User help, displayed on /help option.
-- Copyright (c) 2002-2008 Jason Perkins and the Premake project
--


	function premake.showhelp()
	
		-- display the basic usage
		printf("Premake %s, a build script generator", _PREMAKE_VERSION)
		printf("%s, %s %s", _PREMAKE_COPYRIGHT, _VERSION, _COPYRIGHT)
		printf("")
		printf("Usage: premake4 [options] action [arguments]")
		printf("")

		
		-- display all options
		printf("OPTIONS")
		for option in premake.option.each() do
			local trigger = option.trigger
			local description = option.description
			if (option.value) then trigger = trigger .. "=" .. option.value end
			if (option.aliases) then
				local aliasStr = table.concat( option.aliases, ', -' )
				trigger = trigger .. ", -" .. aliasStr
			end
			if (option.allowed) then description = description .. "; one of:" end
			
			printf(" --%-15s %s", trigger, description) 
			if (option.allowed) then
				for _, value in ipairs(option.allowed) do
					printf("     %-14s %s", value[1], value[2])
				end
			end
		end
		printf("")

		-- display all actions
		printf("ACTIONS")
		for action in premake.action.each() do
			if type(action.description) == 'string' then
				printf(" %-17s %s", action.trigger, action.description)
			else
				local first = action.description[1]
				printf(" %-17s %s", action.trigger, first)
				for i=2,#action.description do
				printf(" %-17s  %s", ' ', action.description[i])
				end
			end
		end
		printf("")


		-- see more
		printf("For additional information, see http://industriousone.com/premake")
		
	end


