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
	@printf "Installing to '${COLOR_INFO}${SBIN_DIR}${NC}'\n"
	@install -d ${SBIN_DIR} 2>/dev/null || { printf "\n${COLOR_ERROR}Failed to create directory: ${SBIN_DIR}${NC}\n"; exit 1; }
	@for script in ${SCRIPTS}; do \
		if install $$script ${SBIN_DIR}/$${script%.sh}; then \
			printf "Installed: ${COLOR_SUCCESS}$${script%.sh}${NC}\n"; \
		else \
			printf "${COLOR_ERROR}Failed to install: $${script%.sh}${NC}\n"; \
			exit 1; \
		fi; \
	done

install-cron:
	@printf "Installing cron to '${COLOR_INFO}${CRON_FILE}${NC}'\n"
	@if install -D cron.d/zfs-utils "${CRON_FILE}"; then \
		printf "Installed: ${COLOR_SUCCESS}${CRON_FILE}${NC}\n"; \
	else \
	  printf "${COLOR_ERROR}Failed to install: ${CRON_FILE}${NC}\n"; \
	  exit 1; \
	fi

uninstall:
	@printf "Uninstalling from '${COLOR_INFO}${SBIN_DIR}${NC}'\n"
	@for script in ${SCRIPTS}; do \
		if rm -f "${SBIN_DIR}/$${script%.sh}"; then \
		  printf "Uninstalled: ${COLOR_SUCCESS}$${script%.sh}${NC}\n"; \
		else \
			printf "${COLOR_ERROR}Failed to uninstall: $${script%.sh}${NC}\n"; \
			exit 1; \
		fi; \
	done

uninstall-cron:
	@printf "Uninstalling cron from '${COLOR_INFO}${CRON_FILE}${NC}'\n"
	@if rm -f "${CRON_FILE}"; then \
		printf "Uninstalled: ${COLOR_SUCCESS}${CRON_FILE}${NC}\n"; \
	else \
		printf "${COLOR_ERROR}Failed to uninstall cron: ${CRON_FILE}${NC}\n"; \
		exit 1; \
	fi;

