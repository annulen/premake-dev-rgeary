#!/bin/bash

$(which readlink 2> /dev/null)
if [[ $? == 0 ]]; then
	premakeDir=$(readlink -f $(dirname $0) )
else
	premakeDir=$(dirname $0)
fi
premake="$premakeDir/bin/debug/premake4 --scripts=$premakeDir/src"
systemScript="--systemScript=$premakeDir/premake-system.lua"
cd $premakeDir

forceBuild=0
threads=""
verbose=
debug=""

while getopts ":vdfj:-" OPTION
do
	case "$OPTION" in
		v) verbose=1 ;;
		f) forceBuild=1 ;;
		j) threads="-j$OPTARG" ;;
		d) debug=" --debug " ;;
		-) break ;;
	  \?) ;;
	esac
done
shift $(($OPTIND-1))

if [[ $verbose ]]; then
	echo "Building Premake"
fi

if [[ $forceBuild == 1 ]]; then
	(rm -rf $premakeDir/bin 
	 rm -rf $premakeDir/obj
	 rm *.ninja
	 rm .ninja_log) 2> /dev/null
fi

if [[ ! -f "$premakeDir/build.ninja" ]]; then
	cp $premakeDir/build.ninja.default $premakeDir/build.ninja
fi
if [[ ! -f "$premakeDir/buildedges.ninja" ]]; then
	cp $premakeDir/buildedges.ninja.default $premakeDir/buildedges.ninja
fi

# Test if premake exists
if [[ ! -f "$premakeDir/bin/release/premake4" || ! -f "$premakeDir/bin/debug/premake4" ]]; then
	# Assume that ninja files in the depot are valid
	ninja $threads
	result=$?
	if [[ $result != 0 ]]; then
		echo "Error building Premake : ninja bootstrap of premake failed"
		exit $result
	fi
fi
	
# Now rebuild to make sure it's the latest
$premake --file=$premakeDir/premake4.lua embed nobuild "$@"
$premake --file=$premakeDir/premake4.lua $systemScript --relativepaths ninja $debug $threads "$@"
result=$?

if [[ $result != 0 ]]; then
	echo "Error : Failed to build Premake"
fi

if [[ $verbose ]]; then
	echo "---------------------"
fi

exit $result

