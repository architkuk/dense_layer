#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include <unistd.h>

// These headers are from the AWS-FPGA SDK
#include <fpga_mgmt.h>
#include <fpga_pci.h>

// -----------------------------------------------------------------------------
// AXI-Lite register offsets in your 'dense_layer_axil_slave'
// -----------------------------------------------------------------------------
#define REG_START           0x0000
#define REG_DEBUG_RST_LOCAL 0x0004
#define REG_DEBUG_COUNTER   0x0008
#define REG_OUTPUT_Y0       0x000C
#define REG_START_TIME_L    0x0010
#define REG_START_TIME_H    0x0014
#define REG_END_TIME_L      0x0018
#define REG_END_TIME_H      0x001C

// By default, assume single slot (slot 0) and AppPF=0, BAR0=0
static const int FPGA_SLOT_ID = 0;
static const int APP_PF       = 0;  // Usually the Application PF is 0
static const int BAR0         = 0;  // Usually BAR0 is 0

// Helper function to read 32 bits from BAR0 at 'offset'
static int do_read32(pci_bar_handle_t handle, uint32_t offset, uint32_t* value)
{
    int rc = fpga_pci_peek(handle, offset, value);
    if (rc != 0) {
        fprintf(stderr, "ERROR: fpga_pci_peek failed at offset 0x%x (rc=%d)\n", offset, rc);
    } else {
        printf("Read  0x%08x from offset 0x%08x\n", *value, offset);
    }
    return rc;
}

// Helper function to write 32 bits to BAR0 at 'offset'
static int do_write32(pci_bar_handle_t handle, uint32_t offset, uint32_t value)
{
    int rc = fpga_pci_poke(handle, offset, value);
    if (rc != 0) {
        fprintf(stderr, "ERROR: fpga_pci_poke failed at offset 0x%x, value=0x%08x (rc=%d)\n",
                offset, value, rc);
    } else {
        printf("Wrote 0x%08x to offset 0x%08x\n", value, offset);
    }
    return rc;
}

int main(int argc, char** argv)
{
    int rc;
    pci_bar_handle_t bar0_handle;
    uint32_t rd_data;
    uint32_t st_lo, st_hi, et_lo, et_hi;
    uint64_t start_time, end_time;

    printf("===========================================\n");
    printf(" Dense Layer: Minimal Host Test on AWS-FPGA\n");
    printf("===========================================\n");

    // 1) Initialize the FPGA management library
    rc = fpga_mgmt_init();
    if (rc != 0) {
        fprintf(stderr, "fpga_mgmt_init failed with rc=%d\n", rc);
        return 1;
    }

    // 2) Attach to the FPGA at slot=0, PF=0, BAR0=0
    rc = fpga_pci_attach(FPGA_SLOT_ID, APP_PF, BAR0, 0, &bar0_handle);
    if (rc != 0) {
        fprintf(stderr, "fpga_pci_attach failed with rc=%d\n", rc);
        return 2;
    }
    printf("[Host] Attached to slot %d, PF %d, BAR %d.\n", FPGA_SLOT_ID, APP_PF, BAR0);

    // -------------------------------------------------------------------------
    // Example writes & reads
    // -------------------------------------------------------------------------
    // Write debug_rst_local=1 at offset 0x4, then read it back
    printf("\n--- Write debug_rst_local = 1, read back ---\n");
    do_write32(bar0_handle, REG_DEBUG_RST_LOCAL, 1);
    do_read32 (bar0_handle, REG_DEBUG_RST_LOCAL, &rd_data);

    // Write debug_rst_local=0
    printf("\n--- Write debug_rst_local = 0, read back ---\n");
    do_write32(bar0_handle, REG_DEBUG_RST_LOCAL, 0);
    do_read32 (bar0_handle, REG_DEBUG_RST_LOCAL, &rd_data);

    // Write start=1
    printf("\n--- Write start = 1, read back ---\n");
    do_write32(bar0_handle, REG_START, 1);
    do_read32 (bar0_handle, REG_START, &rd_data);

    // Read debug_counter multiple times
    printf("\n--- Reading debug_counter 3 times ---\n");
    for (int i = 0; i < 3; i++) {
        do_read32(bar0_handle, REG_DEBUG_COUNTER, &rd_data);
        sleep(1); // Wait 1 second between reads to see if it increments
    }

    // Read start_time and end_time
    // If your design sets these only after some condition, you may see 0
    printf("\n--- Reading start_time and end_time ---\n");
    do_read32(bar0_handle, REG_START_TIME_L, &st_lo);
    do_read32(bar0_handle, REG_START_TIME_H, &st_hi);
    do_read32(bar0_handle, REG_END_TIME_L,   &et_lo);
    do_read32(bar0_handle, REG_END_TIME_H,   &et_hi);

    start_time = ((uint64_t)st_hi << 32) | st_lo;
    end_time   = ((uint64_t)et_hi << 32) | et_lo;
    printf("start_time = %lu\n", (unsigned long)start_time);
    printf("end_time   = %lu\n", (unsigned long)end_time);

    if (end_time > start_time) {
        printf("Duration (cycles): %lu\n", (unsigned long)(end_time - start_time));
    } else {
        printf("Note: end_time <= start_time, maybe design hasn't finished.\n");
    }

    // Finally, read output_y[0]
    uint32_t y0_val = 0;
    do_read32(bar0_handle, REG_OUTPUT_Y0, &y0_val);
    printf("output_y[0] as decimal: %d\n", (int32_t)y0_val);

    // -------------------------------------------------------------------------
    // Detach
    // -------------------------------------------------------------------------
    rc = fpga_pci_detach(bar0_handle);
    if (rc != 0) {
        fprintf(stderr, "fpga_pci_detach failed with rc=%d\n", rc);
        return 3;
    }

    printf("\n==== Dense Layer Host Test Completed ====\n");
    return 0;
}
