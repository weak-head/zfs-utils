PREFIX := /usr/local

all:

install:
	install -d $(DESTDIR)$(PREFIX)/sbin
	install zfs-repl.sh $(DESTDIR)$(PREFIX)/sbin/zfs-repl
	install zfs-snap.sh $(DESTDIR)$(PREFIX)/sbin/zfs-snap
	install zfs-aws.sh  $(DESTDIR)$(PREFIX)/sbin/zfs-aws
	install zfs-rm.sh   $(DESTDIR)$(PREFIX)/sbin/zfs-rm

uninstall:
	rm $(DESTDIR)$(PREFIX)/sbin/zfs-repl
	rm $(DESTDIR)$(PREFIX)/sbin/zfs-snap
	rm $(DESTDIR)$(PREFIX)/sbin/zfs-aws
	rm $(DESTDIR)$(PREFIX)/sbin/zfs-rm