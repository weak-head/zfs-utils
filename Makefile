SBIN_DIR    := $(DESTDIR)/usr/local/sbin
CRON_FILE   := /etc/cron.d/zfs-utils
SCRIPTS     := \
	zfs-clear.sh \
	zfs-snap.sh \
	zfs-to-s3.sh \
	zfs-to-zfs.sh

.PHONY: all install install-cron uninstall uninstall-cron

all:

install:
	@echo "Installing scripts to '$(SBIN_DIR)'..."
	@install -d $(SBIN_DIR)
	@for script in $(SCRIPTS); do \
		install $$script $(SBIN_DIR)/$${script%.sh}; \
	done

install-cron:
	@echo "Installing cron job..."
	@install -D cron.d/zfs-utils $(CRON_FILE)

uninstall:
	@echo "Uninstalling scripts from '$(SBIN_DIR)'..."
	@for script in $(SCRIPTS); do \
		rm -f $(SBIN_DIR)/$${script%.sh}; \
	done

uninstall-cron:
	@echo "Uninstalling cron job..."
	@rm -f $(CRON_FILE)

