PREFIX := /usr/local

all:

install:
	install -d $(DESTDIR)$(PREFIX)/sbin
	install zfs-dataset-sync.sh   $(DESTDIR)$(PREFIX)/sbin/zfs-dataset-sync
	install zfs-dataset-snap.sh   $(DESTDIR)$(PREFIX)/sbin/zfs-dataset-snap
	install zfs-dataset-to-aws.sh $(DESTDIR)$(PREFIX)/sbin/zfs-dataset-to-aws

uninstall:
	rm $(DESTDIR)$(PREFIX)/sbin/zfs-dataset-sync
	rm $(DESTDIR)$(PREFIX)/sbin/zfs-dataset-snap
	rm $(DESTDIR)$(PREFIX)/sbin/zfs-dataset-to-aws