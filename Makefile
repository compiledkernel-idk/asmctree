# =============================================================================
# Beautiful Colorful 3D Christmas Tree - Build System
# =============================================================================

CC = gcc
NASM = nasm
WAYLAND_SCANNER = wayland-scanner

# Compiler flags
CFLAGS = -Wall -O2 -g
LDFLAGS = -lwayland-client -lm

# Protocol files
XDG_SHELL_XML = /usr/share/wayland-protocols/stable/xdg-shell/xdg-shell.xml

# Source files
CSRC = wayland_window.c
ASMSRC = christmas_tree.asm
PROTOCOL_SRC = xdg-shell-protocol.c
PROTOCOL_HDR = xdg-shell-client-protocol.h

# Output
TARGET = christmas_tree

# Default target
all: $(TARGET)

# Generate XDG shell protocol files
$(PROTOCOL_HDR): $(XDG_SHELL_XML)
	$(WAYLAND_SCANNER) client-header $< $@

$(PROTOCOL_SRC): $(XDG_SHELL_XML)
	$(WAYLAND_SCANNER) private-code $< $@

# Compile assembly (for reference/hybrid approach)
christmas_tree_asm.o: $(ASMSRC)
	$(NASM) -f elf64 -o $@ $<

# Build main executable
$(TARGET): $(CSRC) $(PROTOCOL_SRC) $(PROTOCOL_HDR)
	$(CC) $(CFLAGS) -o $@ $(CSRC) $(PROTOCOL_SRC) $(LDFLAGS)

# Clean build artifacts
clean:
	rm -f $(TARGET) *.o $(PROTOCOL_SRC) $(PROTOCOL_HDR)

# Install (optional)
install: $(TARGET)
	install -Dm755 $(TARGET) $(DESTDIR)/usr/local/bin/$(TARGET)

# Run the application
run: $(TARGET)
	./$(TARGET)

.PHONY: all clean install run
