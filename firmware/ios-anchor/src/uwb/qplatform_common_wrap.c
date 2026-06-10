/* Wrapper to give qm33_qhal_common/src/qplatform.c a unique object name,
 * avoiding collision with qm33_qhal_non_zephyr/src/qplatform.c in the
 * flat nRF5 SDK build output directory. */
#include "qplatform.c"
