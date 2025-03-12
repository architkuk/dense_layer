TARGET  = dense_layer_test
SRC     = dense_layer_test.c
OBJS    = $(SRC:.c=.o)

# Use the environment variable SDK_DIR, e.g. export SDK_DIR=/home/ubuntu/sdk
CFLAGS  = -O2 -Wall -I$(SDK_DIR)/userspace/include
LDFLAGS = -L$(SDK_DIR)/userspace/lib -lfpga_mgmt -lfpga_pci -lpthread

all: $(TARGET)

$(TARGET): $(OBJS)
	$(CC) -o $@ $(OBJS) $(LDFLAGS)

%.o: %.c
	$(CC) $(CFLAGS) -c $< -o $@

clean:
	rm -f $(OBJS) $(TARGET)
