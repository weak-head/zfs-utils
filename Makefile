SBIN_DIR    := /usr/local/sbin
CRON_FILE   := /etc/cron.d/zfs-utils
SCRIPTS     := \
	zfs-clear.sh \
	zfs-snap.sh \
	zfs-to-s3.sh \
	zfs-to-zfs.sh

NC            := \033[0m
COLOR_INFO    := \033[0;34m
COLOR_ERROR   := \033[0;31m
COLOR_SUCCESS := \033[0;32m

.PHONY: install install-cron uninstall uninstall-cron

install:
	@echo -e "Installing to '${COLOR_INFO}${SBIN_DIR}${NC}'"
	@install -d ${SBIN_DIR} 2>/dev/null || { echo -e "\n${COLOR_ERROR}Failed to create directory: ${SBIN_DIR}${NC}"; exit 1; }
	@for script in ${SCRIPTS}; do \
		if install $$script ${SBIN_DIR}/$${script%.sh}; then \
			echo -e "Installed: ${COLOR_SUCCESS}$${script%.sh}${NC}"; \
		else \
			echo -e "${COLOR_ERROR}Failed to install: $${script%.sh}${NC}"; \
			exit 1; \
		fi; \
	done

install-cron:
	@echo -e "Installing cron to '${COLOR_INFO}${CRON_FILE}${NC}'"
	@if install -D cron.d/zfs-utils "${CRON_FILE}"; then \
		echo -e "Installed: ${COLOR_SUCCESS}${CRON_FILE}${NC}"; \
	else \
	  echo -e "${COLOR_ERROR}Failed to install: ${CRON_FILE}${NC}"; \
	  exit 1; \
	fi

uninstall:
	@echo -e "Uninstalling from '${COLOR_INFO}${SBIN_DIR}${NC}'"
	@for script in ${SCRIPTS}; do \
		if rm -f "${SBIN_DIR}/$${script%.sh}"; then \
		  echo -e "Uninstalled: ${COLOR_SUCCESS}$${script%.sh}${NC}"; \
		else \
			echo -e "${COLOR_ERROR}Failed to uninstall: $${script%.sh}${NC}"; \
			exit 1; \
		fi; \
	done

uninstall-cron:
	@echo -e "Uninstalling cron from '${COLOR_INFO}${CRON_FILE}${NC}'"
	@if rm -f "${CRON_FILE}"; then \
		echo -e "Uninstalled: ${COLOR_SUCCESS}${CRON_FILE}${NC}"; \
	else \
		echo -e "${COLOR_ERROR}Failed to uninstall cron: ${CRON_FILE}${NC}"; \
		exit 1; \
	fi;

