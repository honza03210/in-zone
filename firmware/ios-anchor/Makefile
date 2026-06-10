# In-Zone anchor firmware — iOS / Apple Nearby Interaction build
#
# Requirements:
#   SDK_ROOT     -> nRF5 SDK 17.1.0 (free download, no registration)
#   GNU_GCC_ROOT -> arm-none-eabi-gcc 10.3+ toolchain
#   UWB_BACKEND  -> stub (default, builds without Qorvo SDK) | qani
#   QANI_ROOT    -> Qorvo QANI package (only for UWB_BACKEND=qani),
#                   default ../vendor/qani
#
# Targets: all (default), flash, flash_softdevice, erase, rtt
#
#   make SDK_ROOT=C:/nRF5_SDK_17.1.0_ddde560                # stub build
#   make SDK_ROOT=... UWB_BACKEND=qani                       # full build

PROJECT_NAME     := inzone_anchor_ios
TARGETS          := nrf52833_xxaa
OUTPUT_DIRECTORY := _build

SDK_ROOT    ?= $(error Set SDK_ROOT to your nRF5 SDK 17.1.0 path)
UWB_BACKEND ?= stub
QANI_ROOT   ?= ../vendor/qani
PROJ_DIR    := .

SOFTDEVICE_HEX := $(SDK_ROOT)/components/softdevice/s113/hex/s113_nrf52_7.2.0_softdevice.hex

$(OUTPUT_DIRECTORY)/nrf52833_xxaa.out: \
  LINKER_SCRIPT := inzone_anchor_nrf52833.ld

# ---- application sources ----
SRC_FILES += \
  $(PROJ_DIR)/src/app/main.c \
  $(PROJ_DIR)/src/app/anchor_id.c \
  $(PROJ_DIR)/src/app/watchdog.c \
  $(PROJ_DIR)/src/board/leds.c \
  $(PROJ_DIR)/src/ble/ble_stack.c \
  $(PROJ_DIR)/src/ble/svc_ni_transport.c \
  $(PROJ_DIR)/src/ble/svc_anchor_info.c \
  $(PROJ_DIR)/src/ni/ni_protocol.c

ifeq ($(UWB_BACKEND),qani)
  SRC_FILES += $(PROJ_DIR)/src/uwb/uwb_port_qani.c
  INC_FOLDERS += $(QANI_ROOT)/Libs/niq/include
  LIB_FILES += $(QANI_ROOT)/Libs/niq/libniq-m4-hfp.a
  # VERIFY(vendor/README.md): uwbstack + driver libs and their exact
  # paths/names differ per QANI release; list them here.
  CFLAGS += -DUWB_BACKEND_QANI
else
  SRC_FILES += $(PROJ_DIR)/src/uwb/uwb_port_stub.c
endif

# ---- nRF5 SDK sources ----
SRC_FILES += \
  $(SDK_ROOT)/modules/nrfx/mdk/gcc_startup_nrf52833.S \
  $(SDK_ROOT)/modules/nrfx/mdk/system_nrf52833.c \
  $(SDK_ROOT)/components/ble/ble_advertising/ble_advertising.c \
  $(SDK_ROOT)/components/ble/common/ble_advdata.c \
  $(SDK_ROOT)/components/ble/common/ble_conn_params.c \
  $(SDK_ROOT)/components/ble/common/ble_conn_state.c \
  $(SDK_ROOT)/components/ble/common/ble_srv_common.c \
  $(SDK_ROOT)/components/ble/nrf_ble_gatt/nrf_ble_gatt.c \
  $(SDK_ROOT)/components/softdevice/common/nrf_sdh.c \
  $(SDK_ROOT)/components/softdevice/common/nrf_sdh_ble.c \
  $(SDK_ROOT)/components/softdevice/common/nrf_sdh_soc.c \
  $(SDK_ROOT)/components/libraries/timer/app_timer2.c \
  $(SDK_ROOT)/components/libraries/timer/drv_rtc.c \
  $(SDK_ROOT)/components/libraries/util/app_error.c \
  $(SDK_ROOT)/components/libraries/util/app_error_handler_gcc.c \
  $(SDK_ROOT)/components/libraries/util/app_error_weak.c \
  $(SDK_ROOT)/components/libraries/util/app_util_platform.c \
  $(SDK_ROOT)/components/libraries/util/nrf_assert.c \
  $(SDK_ROOT)/components/libraries/atomic/nrf_atomic.c \
  $(SDK_ROOT)/components/libraries/atomic_flags/nrf_atflags.c \
  $(SDK_ROOT)/components/libraries/balloc/nrf_balloc.c \
  $(SDK_ROOT)/components/libraries/memobj/nrf_memobj.c \
  $(SDK_ROOT)/components/libraries/ringbuf/nrf_ringbuf.c \
  $(SDK_ROOT)/components/libraries/strerror/nrf_strerror.c \
  $(SDK_ROOT)/components/libraries/sortlist/nrf_sortlist.c \
  $(SDK_ROOT)/components/libraries/pwr_mgmt/nrf_pwr_mgmt.c \
  $(SDK_ROOT)/components/libraries/experimental_section_vars/nrf_section_iter.c \
  $(SDK_ROOT)/components/libraries/log/src/nrf_log_backend_rtt.c \
  $(SDK_ROOT)/components/libraries/log/src/nrf_log_backend_serial.c \
  $(SDK_ROOT)/components/libraries/log/src/nrf_log_default_backends.c \
  $(SDK_ROOT)/components/libraries/log/src/nrf_log_frontend.c \
  $(SDK_ROOT)/components/libraries/log/src/nrf_log_str_formatter.c \
  $(SDK_ROOT)/external/fprintf/nrf_fprintf.c \
  $(SDK_ROOT)/external/fprintf/nrf_fprintf_format.c \
  $(SDK_ROOT)/external/segger_rtt/SEGGER_RTT.c \
  $(SDK_ROOT)/external/segger_rtt/SEGGER_RTT_printf.c \
  $(SDK_ROOT)/integration/nrfx/legacy/nrf_drv_clock.c \
  $(SDK_ROOT)/modules/nrfx/drivers/src/nrfx_clock.c \
  $(SDK_ROOT)/modules/nrfx/drivers/src/nrfx_wdt.c \
  $(SDK_ROOT)/modules/nrfx/soc/nrfx_atomic.c

INC_FOLDERS += \
  $(PROJ_DIR)/config \
  $(PROJ_DIR)/src/app \
  $(PROJ_DIR)/src/ble \
  $(PROJ_DIR)/src/board \
  $(PROJ_DIR)/src/ni \
  $(PROJ_DIR)/src/uwb \
  $(SDK_ROOT)/components \
  $(SDK_ROOT)/components/ble/ble_advertising \
  $(SDK_ROOT)/components/ble/common \
  $(SDK_ROOT)/components/ble/nrf_ble_gatt \
  $(SDK_ROOT)/components/libraries/atomic \
  $(SDK_ROOT)/components/libraries/atomic_flags \
  $(SDK_ROOT)/components/libraries/balloc \
  $(SDK_ROOT)/components/libraries/delay \
  $(SDK_ROOT)/components/libraries/experimental_section_vars \
  $(SDK_ROOT)/components/libraries/log \
  $(SDK_ROOT)/components/libraries/log/src \
  $(SDK_ROOT)/components/libraries/memobj \
  $(SDK_ROOT)/components/libraries/mutex \
  $(SDK_ROOT)/components/libraries/pwr_mgmt \
  $(SDK_ROOT)/components/libraries/ringbuf \
  $(SDK_ROOT)/components/libraries/sortlist \
  $(SDK_ROOT)/components/libraries/strerror \
  $(SDK_ROOT)/components/libraries/timer \
  $(SDK_ROOT)/components/libraries/util \
  $(SDK_ROOT)/components/softdevice/common \
  $(SDK_ROOT)/components/softdevice/s113/headers \
  $(SDK_ROOT)/components/softdevice/s113/headers/nrf52 \
  $(SDK_ROOT)/components/toolchain/cmsis/include \
  $(SDK_ROOT)/external/fprintf \
  $(SDK_ROOT)/external/segger_rtt \
  $(SDK_ROOT)/integration/nrfx \
  $(SDK_ROOT)/integration/nrfx/legacy \
  $(SDK_ROOT)/modules/nrfx \
  $(SDK_ROOT)/modules/nrfx/drivers/include \
  $(SDK_ROOT)/modules/nrfx/hal \
  $(SDK_ROOT)/modules/nrfx/mdk

# ---- flags ----
OPT = -O3 -g3
CFLAGS += $(OPT)
CFLAGS += -DAPP_TIMER_V2 -DAPP_TIMER_V2_RTC1_ENABLED
CFLAGS += -DBOARD_CUSTOM
CFLAGS += -DCONFIG_GPIO_AS_PINRESET
CFLAGS += -DFLOAT_ABI_HARD
CFLAGS += -DNRF52833_XXAA
CFLAGS += -DNRF_SD_BLE_API_VERSION=7
CFLAGS += -DS113 -DSOFTDEVICE_PRESENT
CFLAGS += -DUSE_APP_CONFIG
CFLAGS += -mcpu=cortex-m4 -mthumb -mabi=aapcs
CFLAGS += -Wall -Werror
CFLAGS += -mfloat-abi=hard -mfpu=fpv4-sp-d16
CFLAGS += -ffunction-sections -fdata-sections -fno-strict-aliasing
CFLAGS += -fno-builtin -fshort-enums

ASMFLAGS += -g3 -mcpu=cortex-m4 -mthumb -mabi=aapcs
ASMFLAGS += -mfloat-abi=hard -mfpu=fpv4-sp-d16
ASMFLAGS += -DAPP_TIMER_V2 -DAPP_TIMER_V2_RTC1_ENABLED
ASMFLAGS += -DBOARD_CUSTOM -DCONFIG_GPIO_AS_PINRESET -DFLOAT_ABI_HARD
ASMFLAGS += -DNRF52833_XXAA -DNRF_SD_BLE_API_VERSION=7
ASMFLAGS += -DS113 -DSOFTDEVICE_PRESENT -DUSE_APP_CONFIG

LDFLAGS += $(OPT)
LDFLAGS += -mthumb -mabi=aapcs -L$(SDK_ROOT)/modules/nrfx/mdk -T$(LINKER_SCRIPT)
LDFLAGS += -mcpu=cortex-m4 -mfloat-abi=hard -mfpu=fpv4-sp-d16
LDFLAGS += -Wl,--gc-sections
LDFLAGS += --specs=nano.specs

nrf52833_xxaa: CFLAGS += -D__HEAP_SIZE=4096 -D__STACK_SIZE=4096
nrf52833_xxaa: ASMFLAGS += -D__HEAP_SIZE=4096 -D__STACK_SIZE=4096

LIB_FILES += -lc -lnosys -lm

.PHONY: default flash flash_softdevice erase rtt

default: nrf52833_xxaa

TEMPLATE_PATH := $(SDK_ROOT)/components/toolchain/gcc
include $(TEMPLATE_PATH)/Makefile.common
$(foreach target, $(TARGETS), $(call define_target, $(target)))

flash: default
	nrfjprog -f nrf52 --program $(OUTPUT_DIRECTORY)/nrf52833_xxaa.hex --sectorerase --verify --reset

flash_softdevice:
	nrfjprog -f nrf52 --program $(SOFTDEVICE_HEX) --sectorerase --verify --reset

erase:
	nrfjprog -f nrf52 --eraseall

rtt:
	JLinkRTTViewer -d NRF52833_XXAA -if SWD &
