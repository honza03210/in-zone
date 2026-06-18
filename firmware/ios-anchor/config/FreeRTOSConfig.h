/*
 * FreeRTOS configuration for the In-Zone iOS anchor (QANI + SoftDevice S113).
 *
 * Adapted from Qorvo's DW3_QM33_SDK QANI/DWM3001CDK FreeRTOSConfig.h, which is
 * already tuned for this exact combination: the uwb-stack QOSAL layer, a Nordic
 * SoftDevice, and the nRF52833. The critical settings for SoftDevice
 * coexistence:
 *   - configTICK_SOURCE = RTC  -> FreeRTOS tick runs on RTC1 (RTC0 belongs to
 *     the SoftDevice, RTC2 to the uwb-stack). SysTick is left free.
 *   - configMAX_SYSCALL_INTERRUPT_PRIORITY = _PRIO_APP_LOW_MID (= 5 on nRF52).
 *     FreeRTOS critical sections raise BASEPRI to this, masking only priority
 *     >= 5 and leaving the SoftDevice live (timing-critical 0/1, SVCall/low 4)
 *     plus the UWB SPI (3). Same threshold our bare-metal qirq_lock used.
 *   - SVC_Handler / PendSV_Handler mapped to the FreeRTOS port; the SoftDevice
 *     forwards non-SD SVCs to the app handler.
 */

#ifndef FREERTOS_CONFIG_H
#define FREERTOS_CONFIG_H

#ifdef SOFTDEVICE_PRESENT
#include "nrf_soc.h"
#endif
#include "app_util_platform.h"

/* Possible configurations for the system timer. */
#define FREERTOS_USE_RTC     0
#define FREERTOS_USE_SYSTICK 1

#define configTICK_SOURCE FREERTOS_USE_RTC

#define configUSE_PREEMPTION                    1
#define configUSE_PORT_OPTIMISED_TASK_SELECTION 0
#define configSUPPORT_DYNAMIC_ALLOCATION        1
#define configSUPPORT_STATIC_ALLOCATION         1
#define configUSE_TICKLESS_IDLE                 1
#define configUSE_TICKLESS_IDLE_SIMPLE_DEBUG    1
#define configCPU_CLOCK_HZ                      (SystemCoreClock)
/* Must be 1000 (not 1024): portTICK_PERIOD_MS = 1000/configTICK_RATE_HZ in
 * integer math, and QOSAL's qtime divides by it — 1024 makes it 0 (div-by-0).
 * Plain integer (no TickType_t cast) so app_timer.h's APP_TIMER_TICKS works
 * from files that don't include FreeRTOS.h (e.g. cli.c). The RTC tick port
 * handles the 32768/1000 fractional reload via tick auto-correction. */
#define configTICK_RATE_HZ                      (1000)
#define configMAX_PRIORITIES                    (7)
#define configMINIMAL_STACK_SIZE                ((uint16_t)128)
#define configTOTAL_HEAP_SIZE                   ((size_t)50 * 1024)
#define configMAX_TASK_NAME_LEN                 (12)
#define configUSE_16_BIT_TICKS                  0
#define configIDLE_SHOULD_YIELD                 1
#define configUSE_MUTEXES                       1
#define configUSE_RECURSIVE_MUTEXES             1
#define configUSE_COUNTING_SEMAPHORES           1
#define configUSE_ALTERNATIVE_API               0
#define configQUEUE_REGISTRY_SIZE               8
#define configUSE_QUEUE_SETS                    0
#define configUSE_TIME_SLICING                  0
#define configUSE_NEWLIB_REENTRANT              0
#define configENABLE_BACKWARD_COMPATIBILITY     1

/* Hook functions. */
#define configUSE_IDLE_HOOK            1
#define configUSE_TICK_HOOK            0
/* Diagnostics: catch a task stack overflow (method 2 checks the stack on each
 * context switch and names the task) and a failed pvPortMalloc. Both are prime
 * suspects for the MAC task corrupting RAM -> SoftDevice assert. */
#define configCHECK_FOR_STACK_OVERFLOW 2
#define configUSE_MALLOC_FAILED_HOOK   1

/* Run-time/task stats. */
#define configGENERATE_RUN_TIME_STATS        0
#define configUSE_TRACE_FACILITY             1
#define configUSE_STATS_FORMATTING_FUNCTIONS 0
#define configRECORD_STACK_HIGH_ADDRESS      1

/* Task.c additions (Qorvo stack-profiling extra). Disabled: the header
 * freertos_tasks_c_additions.h is not part of the nRF5 SDK FreeRTOS. */
#define configINCLUDE_FREERTOS_TASK_C_ADDITIONS_H 0

/* Co-routines. */
#define configUSE_CO_ROUTINES           0
#define configMAX_CO_ROUTINE_PRIORITIES (2)

/* Software timers (used by the QOSAL workqueue and app_timer_freertos). */
#define configUSE_TIMERS             1
#define configTIMER_TASK_PRIORITY    (2)
#define configTIMER_QUEUE_LENGTH     (5)
#define configTIMER_TASK_STACK_DEPTH 256

/* Tickless idle. */
#define configEXPECTED_IDLE_TIME_BEFORE_SLEEP 2

/* Trap FreeRTOS asserts: route to our handler (logs file/line over RTT). */
#if !(defined(__ASSEMBLY__) || defined(__ASSEMBLER__))
extern void vApplicationAssert(const char *file, int line);
#define configASSERT(x) do { if (!(x)) vApplicationAssert(__FILE__, __LINE__); } while (0)
#endif

#define configINCLUDE_APPLICATION_DEFINED_PRIVILEGED_FUNCTIONS 1

/* Optional API. */
#define INCLUDE_vTaskPrioritySet               1
#define INCLUDE_uxTaskPriorityGet              1
#define INCLUDE_vTaskDelete                    1
#define INCLUDE_vTaskSuspend                   1
#define INCLUDE_xResumeFromISR                 1
#define INCLUDE_vTaskDelayUntil                1
#define INCLUDE_vTaskDelay                     1
#define INCLUDE_xTaskGetSchedulerState         1
#define INCLUDE_xTaskGetCurrentTaskHandle      1
#define INCLUDE_uxTaskGetStackHighWaterMark    1
#define INCLUDE_xTaskGetIdleTaskHandle         1
#define INCLUDE_xTimerGetTimerDaemonTaskHandle 1
#define INCLUDE_pcTaskGetTaskName              1
#define INCLUDE_eTaskGetState                  1
#define INCLUDE_xEventGroupSetBitFromISR       1
#define INCLUDE_xTimerPendFunctionCall         1

/* Interrupt priorities. */
#define configLIBRARY_LOWEST_INTERRUPT_PRIORITY      0xf
#define configLIBRARY_MAX_SYSCALL_INTERRUPT_PRIORITY _PRIO_APP_LOW_MID

#define configKERNEL_INTERRUPT_PRIORITY      configLIBRARY_LOWEST_INTERRUPT_PRIORITY
#define configMAX_SYSCALL_INTERRUPT_PRIORITY configLIBRARY_MAX_SYSCALL_INTERRUPT_PRIORITY

/* Map FreeRTOS handlers to CMSIS vector names. */
#define vPortSVCHandler    SVC_Handler
#define xPortPendSVHandler PendSV_Handler

#if (configTICK_SOURCE == FREERTOS_USE_SYSTICK)
#define xPortSysTickHandler SysTick_Handler
#elif (configTICK_SOURCE == FREERTOS_USE_RTC)
#define configSYSTICK_CLOCK_HZ (32768UL)
#if (configUSE_TICKLESS_IDLE == 2)
#define xPortSysTickHandler2 RTC1_IRQHandler
#else
#define xPortSysTickHandler RTC1_IRQHandler
#endif
#else
#error Unsupported configTICK_SOURCE value
#endif

#if !(defined(__ASSEMBLY__) || defined(__ASSEMBLER__))
#include "nrf.h"
#include "nrf_assert.h"
#ifdef __NVIC_PRIO_BITS
#define configPRIO_BITS __NVIC_PRIO_BITS
#else
#error "This port requires __NVIC_PRIO_BITS to be defined"
#endif
#if (configTICK_SOURCE == FREERTOS_USE_SYSTICK)
#include <stdint.h>
extern uint32_t SystemCoreClock;
#endif
#endif /* !assembler */

#define configUSE_DISABLE_TICK_AUTO_CORRECTION_DEBUG 0

#endif /* FREERTOS_CONFIG_H */
