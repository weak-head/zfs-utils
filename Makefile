PREFIX := /usr/local

all:

install:
	install -d $(DESTDIR)$(PREFIX)/sbin
	install zfs-sync.sh $(DESTDIR)$(PREFIX)/sbin/zfs-sync
	install zfs-snap.sh $(DESTDIR)$(PREFIX)/sbin/zfs-snap
	install zfs-aws.sh  $(DESTDIR)$(PREFIX)/sbin/zfs-aws

uninstall:
	rm $(DESTDIR)$(PREFIX)/sbin/zfs-sync
	rm $(DESTDIR)$(PREFIX)/sbin/zfs-snap
	rm $(DESTDIR)$(PREFIX)/sbin/zfs-aws