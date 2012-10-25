/**
 * \file   os_chmod.c
 * \brief  Change file permissions
 * \author Copyright (c) 2002-2008 Jason Perkins and the Premake project
 */

#include "premake.h"
#include <sys/stat.h>
#include <stdlib.h>
#include <errno.h>

// os.chmod(filename, octal_mode_string)
int os_chmod(lua_State* L)
{
	int rv;
	const char* path = luaL_checkstring(L, 1);
	const char* modeStr = luaL_checkstring(L, 2);

#if PLATFORM_WINDOWS
	// Not supported
#else
	char * endptr;
	int mode = (int)strtol(modeStr, &endptr, 8);
	rv = chmod(path, mode);
#endif

	if (rv != 0)
	{
		lua_pushnil(L);
		lua_pushfstring(L, "unable to set mode %o on '%s', errno %d : %s", mode, path, errno, strerror(errno));
		return 2;
	}
	else
	{
		lua_pushboolean(L, 1);
		return 1;
	}
}
