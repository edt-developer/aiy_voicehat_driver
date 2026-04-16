KDIR ?= /lib/modules/$(shell uname -r)/build
obj-m += googlevoicehat-codec.o

all:
	$(MAKE) -C $(KDIR) M=$(shell pwd) modules

clean:
	$(MAKE) -C $(KDIR) M=$(shell pwd) clean
