/* Wrapper to give QOSAL's common src/qmalloc.c a unique object name.
 *
 * Two files are named qmalloc.c: the OS-agnostic public allocator
 * (qosal/src/qmalloc.c — qmalloc()/qcalloc()/qmalloc_quota() + the quota
 * prefix logic) and the FreeRTOS backend (qosal/src/freertos/qmalloc.c —
 * qmalloc_internal()/qfree_internal() over pvPortMalloc). The nRF5 SDK
 * Makefile.common derives object names with `notdir`, so they would collide.
 * The FreeRTOS backend is compiled directly (-> qmalloc.o); this wrapper
 * compiles the common one under a unique name. `qmalloc.c` resolves to the
 * common file because qosal/src precedes qosal/src/freertos on the include
 * path (see Makefile INC_FOLDERS order). */
#include "qmalloc.c"
