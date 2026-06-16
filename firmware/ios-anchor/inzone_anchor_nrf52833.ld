/* In-Zone anchor: nRF52833 (512K flash / 128K RAM) with SoftDevice S113 7.2.0.
 *
 * RAM ORIGIN/LENGTH must match the SoftDevice's needs for our BLE config
 * (1 peripheral link, MTU 247). On first boot the firmware logs
 * "SoftDevice RAM start 0x........" — if it differs from ORIGIN below,
 * adjust ORIGIN/LENGTH and rebuild.
 */
SEARCH_DIR(.)
GROUP(-lgcc -lc -lnosys)

MEMORY
{
  FLASH (rx) : ORIGIN = 0x1C000,     LENGTH = 0x64000
  RAM (rwx)  : ORIGIN = 0x20002C00,  LENGTH = 0x1D400
}

SECTIONS
{
  . = ALIGN(4);
  .mem_section_dummy_ram :
  {
  }
  .log_dynamic_data :
  {
    PROVIDE(__start_log_dynamic_data = .);
    KEEP(*(SORT(.log_dynamic_data*)))
    PROVIDE(__stop_log_dynamic_data = .);
  } > RAM
  .log_filter_data :
  {
    PROVIDE(__start_log_filter_data = .);
    KEEP(*(SORT(.log_filter_data*)))
    PROVIDE(__stop_log_filter_data = .);
  } > RAM
  .fs_data :
  {
    PROVIDE(__start_fs_data = .);
    KEEP(*(.fs_data))
    PROVIDE(__stop_fs_data = .);
  } > RAM
} INSERT AFTER .data;

SECTIONS
{
  .mem_section_dummy_rom :
  {
  }
  .sdh_ble_observers :
  {
    PROVIDE(__start_sdh_ble_observers = .);
    KEEP(*(SORT(.sdh_ble_observers*)))
    PROVIDE(__stop_sdh_ble_observers = .);
  } > FLASH
  .sdh_soc_observers :
  {
    PROVIDE(__start_sdh_soc_observers = .);
    KEEP(*(SORT(.sdh_soc_observers*)))
    PROVIDE(__stop_sdh_soc_observers = .);
  } > FLASH
  .sdh_state_observers :
  {
    PROVIDE(__start_sdh_state_observers = .);
    KEEP(*(SORT(.sdh_state_observers*)))
    PROVIDE(__stop_sdh_state_observers = .);
  } > FLASH
  .sdh_stack_observers :
  {
    PROVIDE(__start_sdh_stack_observers = .);
    KEEP(*(SORT(.sdh_stack_observers*)))
    PROVIDE(__stop_sdh_stack_observers = .);
  } > FLASH
  .sdh_req_observers :
  {
    PROVIDE(__start_sdh_req_observers = .);
    KEEP(*(SORT(.sdh_req_observers*)))
    PROVIDE(__stop_sdh_req_observers = .);
  } > FLASH
  .log_const_data :
  {
    PROVIDE(__start_log_const_data = .);
    KEEP(*(SORT(.log_const_data*)))
    PROVIDE(__stop_log_const_data = .);
  } > FLASH
  .log_backends :
  {
    PROVIDE(__start_log_backends = .);
    KEEP(*(SORT(.log_backends*)))
    PROVIDE(__stop_log_backends = .);
  } > FLASH
  .nrf_balloc :
  {
    PROVIDE(__start_nrf_balloc = .);
    KEEP(*(.nrf_balloc))
    PROVIDE(__stop_nrf_balloc = .);
  } > FLASH
  .pwr_mgmt_data :
  {
    PROVIDE(__start_pwr_mgmt_data = .);
    KEEP(*(SORT(.pwr_mgmt_data*)))
    PROVIDE(__stop_pwr_mgmt_data = .);
  } > FLASH

  /* l1_config (DW3110 calibration/config) persists to flash at runtime via
   * sd_flash, page-erasing the page that holds its storage. The precompiled
   * uwbstack bundle emits these as orphan sections; left unplaced they land in
   * .rodata (~0x47E90) and the erase wipes application code -> HardFault.
   * Pin them to dedicated, page-aligned (4 KB) flash pages clear of code
   * (text ends ~0x48288; these sit near the top of the 0x1C000..0x80000
   * region). Each gets its own page so an erase touches nothing else. */
  .l1_config_persist_storage 0x7D000 (NOLOAD) :
  {
    KEEP(*(.l1_config_persist_storage))
  }
  .l1_config_persist_storage_sha256 0x7E000 (NOLOAD) :
  {
    KEEP(*(.l1_config_persist_storage_sha256))
  }
} INSERT AFTER .text

INCLUDE "nrf_common.ld"
