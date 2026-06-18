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
QANI_ROOT   ?= $(SDK_ROOT)/../DW3_QM33_SDK_1.1.1/SDK/Firmware
PROJ_DIR    := .

SOFTDEVICE_HEX := $(SDK_ROOT)/components/softdevice/s113/hex/s113_nrf52_7.2.0_softdevice.hex

$(OUTPUT_DIRECTORY)/nrf52833_xxaa.out: \
  LINKER_SCRIPT := inzone_anchor_nrf52833.ld

# ---- application sources ----
SRC_FILES += \
  $(PROJ_DIR)/src/app/main.c \
  $(PROJ_DIR)/src/app/anchor_id.c \
  $(PROJ_DIR)/src/app/cli.c \
  $(PROJ_DIR)/src/app/watchdog.c \
  $(PROJ_DIR)/src/board/leds.c \
  $(PROJ_DIR)/src/ble/ble_stack.c \
  $(PROJ_DIR)/src/ble/svc_ni_transport.c \
  $(PROJ_DIR)/src/ble/svc_anchor_info.c \
  $(PROJ_DIR)/src/ni/ni_protocol.c

ifeq ($(UWB_BACKEND),qani)
  # ---- our application sources ----
  SRC_FILES += \
    $(PROJ_DIR)/src/uwb/uwb_port_qani.c

  # ---- FreeRTOS kernel + Nordic nRF52 RTC port (SoftDevice coexistence) ----
  # Replaces the bare-metal main loop + qosal_shim.c. RTC1 = FreeRTOS tick
  # (RTC0 = SoftDevice, RTC2 = uwb-stack). app_timer_freertos reimplements the
  # app_timer API over FreeRTOS software timers, so leds/cli/watchdog are
  # unchanged. heap_4 (free + coalescing) backs QOSAL's qmalloc / pvPortMalloc.
  CFLAGS   += -DFREERTOS -DINZONE_FREERTOS
  ASMFLAGS += -DFREERTOS
  # SoftDevice events fetched by the nrf_sdh_freertos task (sdk_config.h is
  # git-ignored, so pin the dispatch model here for reproducibility).
  CFLAGS   += -DNRF_SDH_DISPATCH_MODEL=2
  SRC_FILES += \
    $(SDK_ROOT)/external/freertos/source/croutine.c \
    $(SDK_ROOT)/external/freertos/source/event_groups.c \
    $(SDK_ROOT)/external/freertos/source/list.c \
    $(SDK_ROOT)/external/freertos/source/queue.c \
    $(SDK_ROOT)/external/freertos/source/stream_buffer.c \
    $(SDK_ROOT)/external/freertos/source/tasks.c \
    $(SDK_ROOT)/external/freertos/source/timers.c \
    $(SDK_ROOT)/external/freertos/source/portable/MemMang/heap_4.c \
    $(SDK_ROOT)/external/freertos/portable/GCC/nrf52/port.c \
    $(SDK_ROOT)/external/freertos/portable/CMSIS/nrf52/port_cmsis.c \
    $(SDK_ROOT)/external/freertos/portable/CMSIS/nrf52/port_cmsis_systick.c \
    $(SDK_ROOT)/components/softdevice/common/nrf_sdh_freertos.c \
    $(SDK_ROOT)/components/libraries/timer/app_timer_freertos.c

  # ---- QOSAL FreeRTOS implementation (replaces bare-metal qosal_shim.c) ----
  # Public qmalloc()/quota live in the OS-agnostic src/qmalloc.c (wrapped to
  # avoid an object-name clash with src/freertos/qmalloc.c, which provides the
  # pvPortMalloc backend). See qosal_qmalloc_common_wrap.c.
  SRC_FILES += \
    $(PROJ_DIR)/src/uwb/qosal_qmalloc_common_wrap.c \
    $(QANI_ROOT)/Libs/uwb-stack/libs/qosal/src/qerr_common.c \
    $(QANI_ROOT)/Libs/uwb-stack/libs/qosal/src/freertos/qerr.c \
    $(QANI_ROOT)/Libs/uwb-stack/libs/qosal/src/freertos/qirq.c \
    $(QANI_ROOT)/Libs/uwb-stack/libs/qosal/src/freertos/qmalloc.c \
    $(QANI_ROOT)/Libs/uwb-stack/libs/qosal/src/freertos/qmsg_queue.c \
    $(QANI_ROOT)/Libs/uwb-stack/libs/qosal/src/freertos/qmutex.c \
    $(QANI_ROOT)/Libs/uwb-stack/libs/qosal/src/freertos/qos.c \
    $(QANI_ROOT)/Libs/uwb-stack/libs/qosal/src/freertos/qpm.c \
    $(QANI_ROOT)/Libs/uwb-stack/libs/qosal/src/freertos/qprivate.c \
    $(QANI_ROOT)/Libs/uwb-stack/libs/qosal/src/freertos/qprofiling.c \
    $(QANI_ROOT)/Libs/uwb-stack/libs/qosal/src/freertos/qrand.c \
    $(QANI_ROOT)/Libs/uwb-stack/libs/qosal/src/freertos/qsemaphore.c \
    $(QANI_ROOT)/Libs/uwb-stack/libs/qosal/src/freertos/qsignal.c \
    $(QANI_ROOT)/Libs/uwb-stack/libs/qosal/src/freertos/qthread.c \
    $(QANI_ROOT)/Libs/uwb-stack/libs/qosal/src/freertos/qtime.c \
    $(QANI_ROOT)/Libs/uwb-stack/libs/qosal/src/freertos/qtracing.c \
    $(QANI_ROOT)/Libs/uwb-stack/libs/qosal/src/freertos/qworkqueue.c

  # ---- Qorvo fira init (fira_uwb_mcps_init) ----
  SRC_FILES += $(QANI_ROOT)/Src/Apps/Src/fira/fira_dw3000.c

  # ---- Qorvo qplatform (SPI, GPIO, IRQ for DW3110) ----
  # qplatform_common_wrap.c includes qm33_qhal_common/src/qplatform.c to avoid
  # basename collision with qm33_qhal_non_zephyr/src/qplatform.c (nRF5 SDK
  # Makefile.common uses notdir for object names).
  SRC_FILES += \
    $(PROJ_DIR)/src/uwb/qplatform_common_wrap.c \
    $(QANI_ROOT)/Libs/uwb-stack/libs/qplatform/qm33_qhal_non_zephyr/src/qplatform.c \
    $(QANI_ROOT)/Libs/uwb-stack/libs/qplatform/qm33_qhal_common/src/qplatform_deca_impl.c

  # ---- Qorvo qhal NRFX (GPIO, SPI, timer, RTC, flash, power) ----
  # qpwr_qm33_wrap.c includes qhal/src/qm33/qpwr.c to avoid basename
  # collision with qhal/src/qpwr.c.
  SRC_FILES += \
    $(QANI_ROOT)/Libs/uwb-stack/libs/qhal/src/qpwr.c \
    $(QANI_ROOT)/Libs/uwb-stack/libs/qhal/src/qrtc.c \
    $(QANI_ROOT)/Libs/uwb-stack/libs/qhal/src/nrfx/qgpio.c \
    $(QANI_ROOT)/Libs/uwb-stack/libs/qhal/src/nrfx/qspi.c \
    $(QANI_ROOT)/Libs/uwb-stack/libs/qhal/src/nrfx/qtimer.c \
    $(QANI_ROOT)/Libs/uwb-stack/libs/qhal/src/nrfx/qrtc_share.c \
    $(QANI_ROOT)/Libs/uwb-stack/libs/qhal/src/nrfx/persistent_time.c \
    $(QANI_ROOT)/Libs/uwb-stack/libs/qhal/src/nrfx/qflash.c \
    $(PROJ_DIR)/src/uwb/qpwr_qm33_wrap.c \
    $(QANI_ROOT)/Libs/uwb-stack/libs/qhal/src/qm33/qotp.c

  # ---- DWT UWB driver (DecaWave transceiver) ----
  SRC_FILES += \
    $(QANI_ROOT)/Libs/dwt_uwb_driver/deca_interface.c \
    $(QANI_ROOT)/Libs/dwt_uwb_driver/deca_compat.c \
    $(QANI_ROOT)/Libs/dwt_uwb_driver/deca_rsl.c \
    $(QANI_ROOT)/Libs/dwt_uwb_driver/dw3000/dw3000_device.c \
    $(QANI_ROOT)/Libs/dwt_uwb_driver/lib/qmath/src/qmath.c

  # ---- Board platform (DWM3001CDK calibration + helpers) ----
  SRC_FILES += \
    $(QANI_ROOT)/Src/Boards/Src/DWM3001CDK/platform_l1_config.c \
    $(QANI_ROOT)/Src/Boards/Src/Common/helper_platform_l1_config.c

  # ---- UWB utilities ----
  SRC_FILES += \
    $(QANI_ROOT)/Src/UWB/uwb_translate.c \
    $(QANI_ROOT)/Src/UWB/uwb_utils.c \
    $(PROJ_DIR)/src/uwb/mcps_crypto_stub.c

  # ---- nRF5 SDK drivers needed by qhal NRFX ----
  SRC_FILES += \
    $(SDK_ROOT)/modules/nrfx/drivers/src/nrfx_spim.c \
    $(SDK_ROOT)/modules/nrfx/drivers/src/nrfx_gpiote.c \
    $(SDK_ROOT)/modules/nrfx/drivers/src/nrfx_timer.c \
    $(SDK_ROOT)/modules/nrfx/drivers/src/nrfx_rtc.c \
    $(SDK_ROOT)/modules/nrfx/drivers/src/nrfx_nvmc.c \
    $(SDK_ROOT)/modules/nrfx/drivers/src/prs/nrfx_prs.c \
    $(SDK_ROOT)/modules/nrfx/drivers/src/nrfx_systick.c

  # ---- niq library (Apple NI accessory protocol) ----
  INC_FOLDERS += $(QANI_ROOT)/Libs/niq/Inc
  LIB_FILES += $(QANI_ROOT)/Libs/niq/libniq-m4-hfp-2.1.0.0.a

  # ---- nrf_oberon (AES-CMAC, AES-CCM, AES-CBC for mcps_crypto) ----
  INC_FOLDERS += $(SDK_ROOT)/external/nrf_oberon/include
  LIB_FILES += $(SDK_ROOT)/external/nrf_oberon/lib/cortex-m4/hard-float/liboberon_3.0.8.a

  # ---- uwbstack bundle (FiRa MAC, pre-compiled) ----
  INC_FOLDERS += $(QANI_ROOT)/Libs/uwbstack_libs/delivery/fira/Release/include/uwbstack_bundle
  INC_FOLDERS += $(QANI_ROOT)/Libs/uwbstack_libs/delivery/fira/Release/include/uwbstack_bundle/uwbmac
  INC_FOLDERS += $(QANI_ROOT)/Libs/uwbstack_libs/delivery/fira/Release/include/uwbstack_bundle/net
  LIB_FILES += $(QANI_ROOT)/Libs/uwbstack_libs/delivery/fira/Release/lib/arm-cortex-m4-hard_floating/uwbstack_bundle/libuwbstack_bundle_fira_arm-cortex-m4-hard_floating_rtos_R12.7.0-00405-gb33c5c42726c.a

  # ---- QOSAL headers (qerr.h, qthread.h, qlog.h, etc.) ----
  INC_FOLDERS += $(QANI_ROOT)/Libs/uwb-stack/libs/qosal/include
  INC_FOLDERS += $(QANI_ROOT)/Libs/uwb-stack/libs/qosal/include/dummy
  # qosal/src must precede qosal/src/freertos so the qmalloc wrapper's
  # `#include "qmalloc.c"` resolves to the common (public) qmalloc.c, and
  # qosal/src/freertos provides qprivate.h.
  INC_FOLDERS += $(QANI_ROOT)/Libs/uwb-stack/libs/qosal/src
  INC_FOLDERS += $(QANI_ROOT)/Libs/uwb-stack/libs/qosal/src/freertos

  # ---- FreeRTOS kernel + Nordic nRF52 port ----
  # NB: do NOT add external/freertos/config — its FreeRTOSConfig.h would shadow
  # ours (config/ is added later, so the SDK copy would win and lacks
  # configSUPPORT_STATIC_ALLOCATION). Our config/FreeRTOSConfig.h is authoritative.
  INC_FOLDERS += $(SDK_ROOT)/external/freertos/source/include
  INC_FOLDERS += $(SDK_ROOT)/external/freertos/portable/GCC/nrf52
  INC_FOLDERS += $(SDK_ROOT)/external/freertos/portable/CMSIS/nrf52

  # ---- qplatform headers ----
  INC_FOLDERS += $(QANI_ROOT)/Libs/uwb-stack/libs/qplatform/include
  INC_FOLDERS += $(QANI_ROOT)/Libs/uwb-stack/libs/qplatform/qm33_qhal_common/include
  INC_FOLDERS += $(QANI_ROOT)/Libs/uwb-stack/libs/qplatform/qm33_qhal_common/src

  # ---- qhal headers ----
  INC_FOLDERS += $(QANI_ROOT)/Libs/uwb-stack/libs/qhal/include
  INC_FOLDERS += $(QANI_ROOT)/Libs/uwb-stack/libs/qhal/src/nrfx
  INC_FOLDERS += $(QANI_ROOT)/Libs/uwb-stack/libs/qhal/src/qm33

  # ---- DWT driver headers ----
  INC_FOLDERS += $(QANI_ROOT)/Libs/dwt_uwb_driver
  INC_FOLDERS += $(QANI_ROOT)/Libs/dwt_uwb_driver/lib/qmath/include

  # ---- L1 config / config manager headers ----
  INC_FOLDERS += $(QANI_ROOT)/Libs/uwb-stack/config_manager/plugins/l1_config/include
  INC_FOLDERS += $(QANI_ROOT)/Libs/uwb-stack/config_manager/src

  # ---- App/fira headers ----
  INC_FOLDERS += $(QANI_ROOT)/Src/Apps/Src/fira
  INC_FOLDERS += $(QANI_ROOT)/Src/Apps/Src/fira/Inc

  # ---- UWB utility headers ----
  INC_FOLDERS += $(QANI_ROOT)/Src/UWB/Inc

  # ---- Board headers ----
  INC_FOLDERS += $(QANI_ROOT)/Src/Boards/Src/Common
  INC_FOLDERS += $(QANI_ROOT)/Src/Boards/Src/Common_OTP

  # ---- DWM3001CDK hardware defines (SPI, GPIO, IRQ pins) ----
  CFLAGS += -DUWB_BACKEND_QANI
  CFLAGS += -DQANI_BUILD
  CFLAGS += -DCONFIG_DW3000=1
  CFLAGS += -DCONFIG_QM33=1
  CFLAGS += -DCONFIG_QPLATFORM_IMPL_NRF
  CFLAGS += -DCONFIG_QHAL_MAX_GPIO_CALLBACKS=6
  CFLAGS += -DCONFIG_CFG_MANAGER_VOLATILE_MODE
  CFLAGS += -DCONFIG_L1_CONFIG_CUSTOM_DEFAULT_USE_DEDICATED_SECTION
  CFLAGS += -DBOARD_DWM3001_A1
  CFLAGS += -DUSE_NIQ
  CFLAGS += -DCONFIG_UWB_SPI_INSTANCE=3
  CFLAGS += -DCONFIG_UWB_SPI_FRAME_SIZE=8
  CFLAGS += -DCONFIG_SPI_UWB_IRQ_PRIORITY=3
  CFLAGS += -DCONFIG_SPI_UWB_SCK_GPIO_PORT=0
  CFLAGS += -DCONFIG_SPI_UWB_SCK_GPIO_PIN=3
  CFLAGS += -DCONFIG_SPI_UWB_MOSI_GPIO_PORT=0
  CFLAGS += -DCONFIG_SPI_UWB_MOSI_GPIO_PIN=8
  CFLAGS += -DCONFIG_SPI_UWB_MISO_GPIO_PORT=0
  CFLAGS += -DCONFIG_SPI_UWB_MISO_GPIO_PIN=29
  CFLAGS += -DCONFIG_SPI_UWB_CS_GPIO_PORT=1
  CFLAGS += -DCONFIG_SPI_UWB_CS_GPIO_PIN=6
  CFLAGS += -DCONFIG_DWT_WU_GPIO_PORT=1
  CFLAGS += -DCONFIG_DWT_WU_GPIO_PIN=19
  CFLAGS += -DCONFIG_DWT_IRQ_GPIO_PORT=1
  CFLAGS += -DCONFIG_DWT_IRQ_GPIO_PIN=2
  CFLAGS += -DCONFIG_DWT_RSTN_GPIO_PORT=0
  CFLAGS += -DCONFIG_DWT_RSTN_GPIO_PIN=25
  # nRF5 SDK peripheral driver enables (legacy names — apply_old_config.h
  # maps these to NRFX_* defines; SPI0 enabled as dummy because the
  # legacy layer only checks instances 0-2 for NRFX_SPIM_ENABLED).
  CFLAGS += -DSPI_ENABLED=1
  CFLAGS += -DSPI0_ENABLED=1 -DSPI0_USE_EASY_DMA=1
  CFLAGS += -DSPI3_ENABLED=1 -DSPI3_USE_EASY_DMA=1
  CFLAGS += -DNRFX_SPIM3_ENABLED=1
  CFLAGS += -DNRFX_SPIM_MISO_PULL_CFG=1
  CFLAGS += -DGPIOTE_ENABLED=1
  CFLAGS += -DGPIOTE_CONFIG_NUM_OF_LOW_POWER_EVENTS=1
  CFLAGS += -DTIMER_ENABLED=1 -DTIMER1_ENABLED=1
  CFLAGS += -DRTC_ENABLED=1 -DRTC2_ENABLED=1
  CFLAGS += -DNRFX_NVMC_ENABLED=1
  CFLAGS += -DNRFX_PRS_ENABLED=1
  CFLAGS += -DNRFX_SYSTICK_ENABLED=1
else
  SRC_FILES += $(PROJ_DIR)/src/uwb/uwb_port_stub.c
  # Stub build stays bare-metal: regular app_timer (RTC1). The qani build uses
  # app_timer_freertos instead (RTC1 belongs to the FreeRTOS tick there).
  SRC_FILES += $(SDK_ROOT)/components/libraries/timer/app_timer.c
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
  $(SDK_ROOT)/components/libraries/atomic_fifo \
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
  $(SDK_ROOT)/components/libraries/scheduler \
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
CFLAGS += -DAPP_TIMER_V1
CFLAGS += -DBOARD_CUSTOM
CFLAGS += -DCONFIG_GPIO_AS_PINRESET
CFLAGS += -DFLOAT_ABI_HARD
CFLAGS += -DNRF52833_XXAA
CFLAGS += -DNRF_SD_BLE_API_VERSION=7
CFLAGS += -DS113 -DSOFTDEVICE_PRESENT
CFLAGS += -DUSE_APP_CONFIG
CFLAGS += -mcpu=cortex-m4 -mthumb -mabi=aapcs
CFLAGS += -Wall -Werror -Wno-array-bounds -Wno-enum-int-mismatch -Wno-error=maybe-uninitialized
CFLAGS += -mfloat-abi=hard -mfpu=fpv4-sp-d16
CFLAGS += -ffunction-sections -fdata-sections -fno-strict-aliasing
CFLAGS += -fno-builtin -fshort-enums

ASMFLAGS += -g3 -mcpu=cortex-m4 -mthumb -mabi=aapcs
ASMFLAGS += -mfloat-abi=hard -mfpu=fpv4-sp-d16
ASMFLAGS += -DAPP_TIMER_V1
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
PASS_LINKER_INPUT_VIA_FILE := 0
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
