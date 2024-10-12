PREFIX := /usr/local

all:

install:
	install -d $(DESTDIR)$(PREFIX)/sbin
	install zfs-dataset-sync.sh $(DESTDIR)$(PREFIX)/sbin/zfs-dataset-sync

uninstall:
	rm $(DESTDIR)$(PREFIX)/sbin/zfs-dataset-sync