/*
 * Bare-metal QOSAL shims for the Qorvo uwbstack_bundle library.
 *
 * The uwbstack_bundle is compiled against QOSAL (Qorvo's OS abstraction
 * layer) which normally requires FreeRTOS. These stubs satisfy the linker
 * and provide minimal bare-metal implementations for single-threaded
 * operation.
 *
 * Limitations:
 *   - Threading stubs (qthread) run the function immediately in-place
 *   - Mutex/semaphore are no-ops (safe in single-threaded context)
 *   - Memory allocation uses a simple static pool
 *   - SPI/GPIO must be wired to actual nRF5 drivers for real HW operation
 *
 * If runtime issues arise, the correct fix is to add FreeRTOS to the
 * build and replace this file with the real QOSAL FreeRTOS sources from:
 *   SDK/Firmware/Libs/uwb-stack/libs/qosal/src/freertos/
 */

#include <stdint.h>
#include <stddef.h>
#include <stdbool.h>
#include <string.h>

#include "nrf_log.h"

/* ---- qerr ---- */

#include "qerr.h"

enum qerr qerr_convert_os_to_qerr(int error)
{
    return error == 0 ? QERR_SUCCESS : QERR_EIO;
}

int qerr_convert_qerr_to_os(enum qerr error)
{
    return (int)error;
}

const char *qerr_to_str(enum qerr error)
{
    switch (error) {
    case QERR_SUCCESS: return "SUCCESS";
    case QERR_EINVAL:  return "EINVAL";
    case QERR_ENOMEM:  return "ENOMEM";
    case QERR_EIO:     return "EIO";
    case QERR_EBUSY:   return "EBUSY";
    default:           return "UNKNOWN";
    }
}

/* ---- qmalloc ---- */

/* The uwb stack (uwbmac + niq + FiRa) needs a substantial heap during init.
 * Qorvo's FreeRTOS build sets configTOTAL_HEAP_SIZE = 50 KB; match that. Our
 * 8 KB arena OOM'd mid-init, qmalloc returned NULL, and the NULL was written
 * through -> HardFault in nrf_balloc_init. nRF52833 has 128 KB RAM and the
 * app region is ~120 KB, so 50 KB of .bss heap fits with room for the stack. */
#define HEAP_SIZE (50 * 1024)
static uint8_t  s_heap[HEAP_SIZE];
static uint32_t s_heap_used;

void *qmalloc(size_t size)
{
    size = (size + 3) & ~3u;
    if (s_heap_used + size > HEAP_SIZE) {
        NRF_LOG_ERROR("qosal: qmalloc OOM (%u + %u > %u)",
                      s_heap_used, size, HEAP_SIZE);
        return NULL;
    }
    void *p = &s_heap[s_heap_used];
    s_heap_used += size;
    return p;
}

void qfree(void *ptr)
{
    (void)ptr;
}

void *qcalloc(size_t nmemb, size_t size)
{
    void *p = qmalloc(nmemb * size);
    if (p) memset(p, 0, nmemb * size);
    return p;
}

void *qrealloc(void *ptr, size_t size)
{
    void *p = qmalloc(size);
    if (p && ptr) memcpy(p, ptr, size);
    return p;
}

void *qmalloc_quota(size_t size, const char *tag)
{
    (void)tag;
    return qmalloc(size);
}

void *qcalloc_quota(size_t nmemb, size_t size, const char *tag)
{
    (void)tag;
    return qcalloc(nmemb, size);
}

/* ---- qthread ---- */

struct qthread { int dummy; };
static struct qthread s_thread;

struct qthread *qthread_create(void (*func)(void *), void *arg,
                               const char *name, void *stack,
                               uint32_t stack_size, int priority)
{
    (void)name; (void)stack; (void)stack_size; (void)priority;
    /* bare-metal: just record it, don't run immediately */
    return &s_thread;
}

enum qerr qthread_join(struct qthread *thread)
{
    (void)thread;
    return QERR_SUCCESS;
}

enum qerr qthread_delete(struct qthread *thread)
{
    (void)thread;
    return QERR_SUCCESS;
}

enum qerr qthread_yield(void)
{
    return QERR_SUCCESS;
}

/* ---- qsignal ---- */

struct qsignal {
    volatile int  value;
    volatile bool raised;
};

static struct qsignal s_signal;

struct qsignal *qsignal_init(void)
{
    memset(&s_signal, 0, sizeof(s_signal));
    return &s_signal;
}

void qsignal_deinit(struct qsignal *sig)
{
    (void)sig;
}

enum qerr qsignal_raise(struct qsignal *sig, int value)
{
    sig->value = value;
    sig->raised = true;
    return QERR_SUCCESS;
}

enum qerr qsignal_wait(struct qsignal *sig, int *value, uint32_t timeout_ms)
{
    (void)timeout_ms;
    if (sig->raised) {
        sig->raised = false;
        if (value) *value = sig->value;
        return QERR_SUCCESS;
    }
    return QERR_ETIME;
}

/* ---- qmutex ---- */

struct qmutex { int dummy; };
static struct qmutex s_mutex;

struct qmutex *qmutex_init(void)
{
    return &s_mutex;
}

void qmutex_deinit(struct qmutex *m)
{
    (void)m;
}

enum qerr qmutex_lock(struct qmutex *m, uint32_t timeout_ms)
{
    (void)m; (void)timeout_ms;
    return QERR_SUCCESS;
}

enum qerr qmutex_unlock(struct qmutex *m)
{
    (void)m;
    return QERR_SUCCESS;
}

/* ---- qsemaphore ---- */

struct qsemaphore {
    volatile int count;
};
static struct qsemaphore s_sem;

struct qsemaphore *qsemaphore_init(int initial_count, int max_count)
{
    (void)max_count;
    s_sem.count = initial_count;
    return &s_sem;
}

void qsemaphore_deinit(struct qsemaphore *sem)
{
    (void)sem;
}

enum qerr qsemaphore_take(struct qsemaphore *sem, uint32_t timeout_ms)
{
    (void)timeout_ms;
    if (sem->count > 0) {
        sem->count--;
        return QERR_SUCCESS;
    }
    return QERR_ETIME;
}

enum qerr qsemaphore_give(struct qsemaphore *sem)
{
    sem->count++;
    return QERR_SUCCESS;
}

/* ---- qmsg_queue ---- */

struct qmsg_queue { int dummy; };
static struct qmsg_queue s_mq;

struct qmsg_queue *qmsg_queue_init(uint32_t msg_size, uint32_t max_msgs)
{
    (void)msg_size; (void)max_msgs;
    return &s_mq;
}

void qmsg_queue_deinit(struct qmsg_queue *mq)
{
    (void)mq;
}

enum qerr qmsg_queue_put(struct qmsg_queue *mq, const void *msg, uint32_t timeout_ms)
{
    (void)mq; (void)msg; (void)timeout_ms;
    return QERR_ENOBUFS;
}

enum qerr qmsg_queue_get(struct qmsg_queue *mq, void *msg, uint32_t timeout_ms)
{
    (void)mq; (void)msg; (void)timeout_ms;
    return QERR_ETIME;
}

/* ---- qtime ---- */

#include "app_timer.h"

uint64_t qtime_get_uptime_us(void)
{
    return app_timer_cnt_get() * 1000000ULL / 32768;
}

uint32_t qtime_get_uptime_ticks_default(void)
{
    return app_timer_cnt_get();
}

uint32_t qtime_get_sys_freq_hz(void)
{
    return 64000000; /* nRF52833 runs at 64 MHz */
}

void qtime_msleep(uint32_t ms)
{
    volatile uint32_t cycles = ms * 64000;
    while (cycles--) { __asm volatile ("nop"); }
}

void qtime_usleep(uint32_t us)
{
    volatile uint32_t cycles = us * 64;
    while (cycles--) { __asm volatile ("nop"); }
}

void qtime_msleep_yield(uint32_t ms) { qtime_msleep(ms); }
void qtime_usleep_yield(uint32_t us) { qtime_usleep(us); }

/* ---- qirq ----
 *
 * The uwb stack guards its data with qirq_lock/qirq_disable. The original
 * implementation used cpsid i / __disable_irq (PRIMASK), which masks ALL
 * interrupts — including the SPIM3 DMA-completion IRQ (priority 3) that
 * nrfx_spim needs to finish a transfer and clear its transfer_in_progress
 * state. Under the SoftDevice that deadlocked DW3110 bring-up: a transfer
 * issued inside a lock could never complete, and the next one returned BUSY.
 *
 * Use BASEPRI to mask only the uwb stack's own low-priority IRQs (>= 5: DW
 * pri 7, GPIOTE pri 6, timers) while leaving everything the SoftDevice and
 * the SPI driver need LIVE:
 *   - pri 0/1  SoftDevice timing-critical (never mask)
 *   - pri 3    SPIM3 DMA completion (nrfx needs it to finish transfers)
 *   - pri 4    SoftDevice SVCall + low SWI — masking this makes any sd_*()
 *              call inside a lock HardFault (the SVC can't be taken). The
 *              uwb stack calls sd_flash_*() from inside qirq_lock, so pri 4
 *              MUST stay enabled.
 * This is the standard app critical-section model under the SoftDevice. */
#define QIRQ_LOCK_BASEPRI ((uint32_t)(5u << (8u - __NVIC_PRIO_BITS)))

void qirq_disable(void)
{
    __set_BASEPRI(QIRQ_LOCK_BASEPRI);
    __DSB();
    __ISB();
}

void qirq_enable(void)
{
    __set_BASEPRI(0);
}

bool qirq_is_in_irq(void)
{
    return (SCB->ICSR & SCB_ICSR_VECTACTIVE_Msk) != 0;
}

unsigned int qirq_lock(void)
{
    unsigned int key = __get_BASEPRI();
    __set_BASEPRI(QIRQ_LOCK_BASEPRI);
    __DSB();
    __ISB();
    return key;
}

void qirq_unlock(unsigned int key)
{
    __set_BASEPRI(key);
}

/* ---- qworkqueue (stubs) ---- */

struct qworkqueue { int dummy; };

struct qworkqueue *qworkqueue_create(const char *name, void *stack,
                                     uint32_t stack_size, int priority)
{
    (void)name; (void)stack; (void)stack_size; (void)priority;
    return NULL;
}

void qworkqueue_destroy(struct qworkqueue *wq) { (void)wq; }

struct qwork { void (*func)(void *); void *arg; };

void qworkqueue_init(struct qwork *work, void (*func)(void *), void *arg)
{
    if (work) { work->func = func; work->arg = arg; }
}

enum qerr qworkqueue_schedule_work(struct qworkqueue *wq, struct qwork *work)
{
    (void)wq;
    if (work && work->func) work->func(work->arg);
    return QERR_SUCCESS;
}

enum qerr qworkqueue_cancel_work(struct qwork *work)
{
    (void)work;
    return QERR_SUCCESS;
}

/* ---- qos (scheduler stub) ---- */

void qos_start(void)
{
    /* bare-metal: no scheduler to start */
}

/* ---- qpm (power management stubs) ---- */

void qpm_sleep_state_lock(void) {}
void qpm_sleep_state_unlock(void) {}

/* ---- qprofiling / qtracing (stubs) ---- */

void qprofiling_init(void) {}
void qtracing_init(void) {}

/* ---- qlog (stub — we use NRF_LOG instead) ---- */

int qlog_init(void) { return 0; }
