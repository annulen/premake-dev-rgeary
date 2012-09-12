--
-- cmdline.lua
-- Functions to define and handle command line actions and options.
-- Copyright (c) 2002-2011 Jason Perkins and the Premake project
--


--
-- Built-in command line options
--

	newoption
	{
		trigger     = "file",
		value       = "FILE",
		description = "Read FILE as a Premake script; default is 'premake4.lua'"
	}
	
	newoption
	{
		trigger     = "help",
		description = "Display this information"
	}
		
	newoption
	{
		trigger     = "scripts",
		value       = "path",
		description = "Search for additional scripts on the given path"
	}
	
	newoption
	{
		trigger     = "version",
		description = "Display version information"
	}
	
	newoption
	{
		trigger		= "debug",
		description = "Display full stack trace for errors"
	}
	
	newoption
	{
		trigger		= "attach",
		value		= "[ip]",
		description = "Attach to the Eclipse Koneki DBGp debugger. IP address optional."
	}

	newoption
	{
		trigger		= "attachNoWait",
		value		= "[ip]",
		description = "Try attaching to the debugger, but don't wait. IP address optional."
	}
	
	newoption
	{
		trigger		= "dryrun",
		description	= "Print the files which would be modified, but do not execute commands or make any changes to the file system",
		aliases		= { 'n' },
	}
	
	newoption
	{
		trigger		= "profile",
		description	= "Run premake with timing enabled",
	}
	
	newoption
	{
		trigger		= "threads",
		value		= "#",
		description	= "If the action is also building the project, use this number of threads",
		aliases		= { 'j' },
	}
	
	newoption
	{
		trigger		= "automated",
		description = "Automated mode, no interaction available.",
		aliases 	= { 'a' },
	}
	
	newoption
	{
		trigger     = "relativepaths",
		description = "Always generate relative build paths",
	}
	
	newoption
	{
		trigger     = "systemScript",
		description = "Run a system script before the build script. Default filename is premake-system.lua. Overridden by $PREMAKE_PATH.",
	}