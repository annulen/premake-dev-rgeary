#------
# Load configuration
#
include config

#------
INSTALL_LIB=bin

all:
	cd src; $(MAKE) $@
	cd lfs; $(MAKE) $@
	mkdir -p $(INSTALL_LIB)
	cp -f src/$(MIME_SO) $(INSTALL_LIB)/mime.so
	cp -f lfs/src/$(LFS_SO) $(INSTALL_LIB)/lfs.so
	cp -f src/$(SOCKET_SO) $(INSTALL_LIB)/socket.so

clean:
	cd src; $(MAKE) $@
	cd lfs; $(MAKE) $@
	rm -f $(INSTALL_LIB)/mime.so
	rm -f $(INSTALL_LIB)/lfs.so
	rm -f $(INSTALL_LIB)/socket.so
	rmdir $(INSTALL_LIB)

#------
# End of makefile
#
