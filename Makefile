# Last Modified: 2026-04-17 13:24:00
# Modified By: Codex (GPT-5)
# Description: Build the Voice HAT kernel module inside a dedicated build folder and add clean/install/status verification targets that follow the README workflow with clearer install-phase logging and non-fatal user-service stop failures.

ifneq ($(KERNELRELEASE),)
obj-m += googlevoicehat-codec.o
else
KERNEL_RELEASE ?= $(shell uname -r)
KDIR ?= /lib/modules/$(KERNEL_RELEASE)/build
SUDO ?= sudo
SYSTEMCTL_USER ?= systemctl
SLEEP ?= sleep
CP ?= cp -f
MKDIR_P ?= mkdir -p
RM ?= rm -f
RMDIR ?= rm -rf
PRINTF ?= printf

MODULE_NAME := googlevoicehat-codec
MODULE_FILE := $(MODULE_NAME).ko
MODULE_SOURCE_FILE := $(MODULE_NAME).c
MODULE_SOURCE_DIR := $(CURDIR)
MODULE_SOURCE_PATH := $(MODULE_SOURCE_DIR)/$(MODULE_SOURCE_FILE)
BUILD_DIR := $(MODULE_SOURCE_DIR)/build
BUILD_KBUILD_PATH := $(BUILD_DIR)/Makefile
BUILD_SOURCE_PATH := $(BUILD_DIR)/$(MODULE_SOURCE_FILE)
BUILD_MODULE_PATH := $(BUILD_DIR)/$(MODULE_FILE)

MODULE_INSTALL_DIR := /lib/modules/$(KERNEL_RELEASE)/kernel/sound/soc/bcm
MODULE_INSTALL_FILE := snd-soc-googlevoicehat-codec.ko
MODULE_INSTALL_PATH := $(MODULE_INSTALL_DIR)/$(MODULE_INSTALL_FILE)
MODULE_INSTALL_COMPRESSED_PATH := $(MODULE_INSTALL_PATH).xz
MODULE_INSTALL_BACKUP_PATH := $(MODULE_INSTALL_COMPRESSED_PATH).bak

CODEC_MODULE_NAME := snd_soc_googlevoicehat_codec
SOUNDCARD_MODULE_NAME := snd_soc_rpi_simple_soundcard
STOP_AUDIO_SERVICES := pipewire.socket pipewire wireplumber
START_AUDIO_SERVICES := pipewire.service wireplumber.service
CODEC_RUNTIME_MODULE_NAMES := googlevoicehat_codec $(CODEC_MODULE_NAME)

SOURCE_TREE_ARTIFACTS := \
	$(MODULE_SOURCE_DIR)/..module-common.o.cmd \
	$(MODULE_SOURCE_DIR)/.Module.symvers.cmd \
	$(MODULE_SOURCE_DIR)/.$(MODULE_NAME).ko.cmd \
	$(MODULE_SOURCE_DIR)/.$(MODULE_NAME).mod.cmd \
	$(MODULE_SOURCE_DIR)/.$(MODULE_NAME).mod.o.cmd \
	$(MODULE_SOURCE_DIR)/.$(MODULE_NAME).o.cmd \
	$(MODULE_SOURCE_DIR)/.module-common.o \
	$(MODULE_SOURCE_DIR)/.modules.order.cmd \
	$(MODULE_SOURCE_DIR)/Module.symvers \
	$(MODULE_SOURCE_DIR)/$(MODULE_NAME).ko \
	$(MODULE_SOURCE_DIR)/$(MODULE_NAME).mod \
	$(MODULE_SOURCE_DIR)/$(MODULE_NAME).mod.c \
	$(MODULE_SOURCE_DIR)/$(MODULE_NAME).mod.o \
	$(MODULE_SOURCE_DIR)/$(MODULE_NAME).o \
	$(MODULE_SOURCE_DIR)/modules.order

.PHONY: all backup build clean install prune-source-artifacts status verify-install

all: build

# Remove source-tree outputs left by older build flows so generated files live under build/.
build: prune-source-artifacts $(BUILD_KBUILD_PATH) $(BUILD_SOURCE_PATH)
	$(MAKE) -C $(KDIR) M=$(BUILD_DIR) modules

$(BUILD_DIR):
	$(MKDIR_P) "$(BUILD_DIR)"

$(BUILD_KBUILD_PATH): | $(BUILD_DIR)
	$(PRINTF) '%s\n' 'obj-m += $(MODULE_NAME).o' > "$(BUILD_KBUILD_PATH)"

$(BUILD_SOURCE_PATH): $(MODULE_SOURCE_PATH) | $(BUILD_DIR)
	$(CP) "$(MODULE_SOURCE_PATH)" "$(BUILD_SOURCE_PATH)"

prune-source-artifacts:
	$(RM) $(SOURCE_TREE_ARTIFACTS)

backup:
	if [ -f "$(MODULE_INSTALL_COMPRESSED_PATH)" ] && [ ! -f "$(MODULE_INSTALL_BACKUP_PATH)" ]; then \
		$(SUDO) cp "$(MODULE_INSTALL_COMPRESSED_PATH)" "$(MODULE_INSTALL_BACKUP_PATH)"; \
	fi

clean: prune-source-artifacts
	$(RMDIR) "$(BUILD_DIR)"

# Report the built module, installed module, and currently loaded module state.
status:
	@echo "Kernel release: $(KERNEL_RELEASE)"
	@echo "Built module:"
	@if [ -f "$(BUILD_MODULE_PATH)" ]; then \
		echo "  path: $(BUILD_MODULE_PATH)"; \
		modinfo "$(BUILD_MODULE_PATH)" | sed -n \
			-e 's/^name:[[:space:]]*/  name: /p' \
			-e 's/^srcversion:[[:space:]]*/  srcversion: /p' \
			-e 's/^vermagic:[[:space:]]*/  vermagic: /p'; \
	else \
		echo "  path: missing"; \
		echo "  hint: run 'make build' first"; \
	fi
	@echo "Installed module:"
	@installed_module_path=""; \
	if [ -f "$(MODULE_INSTALL_PATH)" ]; then \
		installed_module_path="$(MODULE_INSTALL_PATH)"; \
	elif [ -f "$(MODULE_INSTALL_COMPRESSED_PATH)" ]; then \
		installed_module_path="$(MODULE_INSTALL_COMPRESSED_PATH)"; \
	fi; \
	if [ -n "$$installed_module_path" ]; then \
		echo "  path: $$installed_module_path"; \
		modinfo "$$installed_module_path" | sed -n \
			-e 's/^name:[[:space:]]*/  name: /p' \
			-e 's/^srcversion:[[:space:]]*/  srcversion: /p' \
			-e 's/^vermagic:[[:space:]]*/  vermagic: /p'; \
	else \
		echo "  path: missing"; \
	fi
	@echo "Modprobe codec path:"
	@modprobe_codec_path=$$(modprobe --show-depends "$(CODEC_MODULE_NAME)" 2>/dev/null | awk '$$2 ~ /\/snd-soc-googlevoicehat-codec\.ko(\.xz)?$$/ { print $$2; exit }'); \
	if [ -n "$$modprobe_codec_path" ]; then \
		echo "  path: $$modprobe_codec_path"; \
	else \
		echo "  path: unresolved"; \
	fi
	@echo "Loaded codec module:"
	@loaded_codec_name=""; \
	for module_name in $(CODEC_RUNTIME_MODULE_NAMES); do \
		if [ -f "/sys/module/$$module_name/srcversion" ]; then \
			loaded_codec_name="$$module_name"; \
			break; \
		fi; \
	done; \
	if [ -n "$$loaded_codec_name" ]; then \
		echo "  module: $$loaded_codec_name"; \
		echo "  srcversion: $$(cat /sys/module/$$loaded_codec_name/srcversion)"; \
	else \
		echo "  module: not loaded"; \
	fi
	@echo "Loaded modules:"
	@lsmod | awk 'BEGIN { found = 0 } \
		NR == 1 { header = $$0; next } \
		$$1 == "googlevoicehat_codec" || $$1 == "snd_soc_googlevoicehat_codec" || $$1 == "snd_soc_rpi_simple_soundcard" { \
			if (!found) { \
				print "  " header; \
				found = 1; \
			} \
			print "  " $$0; \
		} \
		END { if (!found) print "  none" }'

verify-install:
	@built_srcversion=""; \
	if [ -f "$(BUILD_MODULE_PATH)" ]; then \
		built_srcversion=$$(modinfo -F srcversion "$(BUILD_MODULE_PATH)" 2>/dev/null); \
	fi; \
	if [ -z "$$built_srcversion" ]; then \
		echo "Verification failed: built module is missing or unreadable at $(BUILD_MODULE_PATH)"; \
		exit 1; \
	fi; \
	installed_module_path=""; \
	if [ -f "$(MODULE_INSTALL_PATH)" ]; then \
		installed_module_path="$(MODULE_INSTALL_PATH)"; \
	elif [ -f "$(MODULE_INSTALL_COMPRESSED_PATH)" ]; then \
		installed_module_path="$(MODULE_INSTALL_COMPRESSED_PATH)"; \
	fi; \
	if [ -z "$$installed_module_path" ]; then \
		echo "Verification failed: installed module is missing from $(MODULE_INSTALL_DIR)"; \
		exit 1; \
	fi; \
	installed_srcversion=$$(modinfo -F srcversion "$$installed_module_path" 2>/dev/null); \
	if [ "$$built_srcversion" != "$$installed_srcversion" ]; then \
		echo "Verification failed: installed module srcversion ($$installed_srcversion) does not match built module ($$built_srcversion)"; \
		exit 1; \
	fi; \
	modprobe_codec_path=$$(modprobe --show-depends "$(CODEC_MODULE_NAME)" 2>/dev/null | awk '$$2 ~ /\/snd-soc-googlevoicehat-codec\.ko(\.xz)?$$/ { print $$2; exit }'); \
	if [ "$$modprobe_codec_path" != "$(MODULE_INSTALL_PATH)" ]; then \
		echo "Verification failed: modprobe resolves $(CODEC_MODULE_NAME) to '$$modprobe_codec_path' instead of '$(MODULE_INSTALL_PATH)'"; \
		exit 1; \
	fi; \
	loaded_codec_name=""; \
	for module_name in $(CODEC_RUNTIME_MODULE_NAMES); do \
		if [ -f "/sys/module/$$module_name/srcversion" ]; then \
			loaded_codec_name="$$module_name"; \
			break; \
		fi; \
	done; \
	if [ -z "$$loaded_codec_name" ]; then \
		echo "Verification failed: codec module is not loaded"; \
		exit 1; \
	fi; \
	loaded_srcversion=$$(cat /sys/module/$$loaded_codec_name/srcversion); \
	if [ "$$built_srcversion" != "$$loaded_srcversion" ]; then \
		echo "Verification failed: loaded codec module '$$loaded_codec_name' srcversion ($$loaded_srcversion) does not match built module ($$built_srcversion)"; \
		exit 1; \
	fi; \
	if [ ! -d "/sys/module/$(SOUNDCARD_MODULE_NAME)" ]; then \
		echo "Verification failed: dependent soundcard module $(SOUNDCARD_MODULE_NAME) is not loaded"; \
		exit 1; \
	fi; \
	echo "Verification passed: installed and loaded codec module matches built module ($$built_srcversion)"

# Mirror the README install flow: stop audio services, replace the module, rebuild deps, and reload it.
install: build backup
	@echo "== AIY Voice HAT install start =="
	@if ! $(SYSTEMCTL_USER) stop $(STOP_AUDIO_SERVICES); then \
		echo "Warning: failed to stop one or more user audio services ($(STOP_AUDIO_SERVICES)); continuing install"; \
	fi
	$(SLEEP) 2
	$(SUDO) modprobe -r $(SOUNDCARD_MODULE_NAME) || true
	$(SUDO) modprobe -r $(CODEC_MODULE_NAME) || true
	$(SUDO) rm -f "$(MODULE_INSTALL_COMPRESSED_PATH)"
	$(SUDO) cp "$(BUILD_MODULE_PATH)" "$(MODULE_INSTALL_PATH)"
	$(SUDO) depmod -a
	$(SUDO) modprobe $(CODEC_MODULE_NAME)
	$(SUDO) modprobe $(SOUNDCARD_MODULE_NAME)
	$(SYSTEMCTL_USER) start $(START_AUDIO_SERVICES)
	$(SLEEP) 2
	@echo "== AIY Voice HAT make status =="
	$(MAKE) status
	@echo "== AIY Voice HAT verify-install =="
	$(MAKE) verify-install
	@echo "== AIY Voice HAT install complete =="
endif
