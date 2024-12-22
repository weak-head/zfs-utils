PREFIX := /usr/local

all:

install:
	install -d $(DESTDIR)$(PREFIX)/sbin
	install zfs-clear.sh   $(DESTDIR)$(PREFIX)/sbin/zfs-clear
	install zfs-snap.sh    $(DESTDIR)$(PREFIX)/sbin/zfs-snap
	install zfs-to-s3.sh   $(DESTDIR)$(PREFIX)/sbin/zfs-to-s3
	install zfs-to-zfs.sh  $(DESTDIR)$(PREFIX)/sbin/zfs-to-zfs

uninstall:
	rm $(DESTDIR)$(PREFIX)/sbin/zfs-snap
	rm $(DESTDIR)$(PREFIX)/sbin/zfs-clear
	rm $(DESTDIR)$(PREFIX)/sbin/zfs-to-s3
	rm $(DESTDIR)$(PREFIX)/sbin/zfs-to-zfs
