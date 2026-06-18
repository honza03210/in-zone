import CoreBluetooth

enum BLE {
    /* Qorvo Nearby Interaction Service (QNIS), as exposed by the stock
     * DWM3001CDK-QANI-FreeRTOS firmware. 128-bit base 2E93xxxx-6A61-11ED-A1EB-
     * 0242AC120002 (Nordic vendor base, 16-bit slot at bytes 12..13). */
    static let transportService = CBUUID(string: "2E938FD0-6A61-11ED-A1EB-0242AC120002")
    /* SEC: read-only, just-works secured — reading it triggers BLE pairing,
     * which the QANI firmware expects before ranging. */
    static let secChar          = CBUUID(string: "2E93941C-6A61-11ED-A1EB-0242AC120002")
    /* RX: phone -> accessory (write / write-without-response). */
    static let rxChar           = CBUUID(string: "2E93998A-6A61-11ED-A1EB-0242AC120002")
    /* TX: accessory -> phone (notify). */
    static let txChar           = CBUUID(string: "2E939AF2-6A61-11ED-A1EB-0242AC120002")

    /* Apple NI accessory protocol message ids (same as Qorvo's niq / our old
     * firmware — only the BLE transport differs). */
    static let msgInitialize:      UInt8 = 0x0A
    static let msgConfigure:       UInt8 = 0x0B
    static let msgStop:            UInt8 = 0x0C

    static let msgAccessoryConfig: UInt8 = 0x01
    static let msgUwbDidStart:     UInt8 = 0x02
    static let msgUwbDidStop:      UInt8 = 0x03
}
