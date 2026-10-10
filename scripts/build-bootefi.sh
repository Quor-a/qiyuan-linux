#!/bin/bash
# build-bootefi.sh — standalone GRUB EFI (内嵌 cfg, serial console, root=LABEL=qyroot)
set -e
cat > /tmp/qygrub.cfg <<'EOF'
serial --unit=0 --speed=115200
terminal_input serial console
terminal_output serial console
set timeout=2
set default=0
menuentry "LANXIU Linux" {
    search --no-floppy --label --set=root qyroot
    linux ($root)/boot/vmlinuz-6.16.1 root=LABEL=qyroot console=ttyS0
    initrd ($root)/boot/initramfs.img
}
menuentry "LANXIU Linux (rescue)" {
    search --no-floppy --label --set=root qyroot
    linux ($root)/boot/vmlinuz-6.16.1 root=LABEL=qyroot console=ttyS0 single
    initrd ($root)/boot/initramfs.img
}
EOF
grub-mkstandalone -O x86_64-efi -o /tmp/BOOTX64.EFI "boot/grub/grub.cfg=/tmp/qygrub.cfg" \
  --modules="part_gpt part_msdos ext2 fat search search_label linux normal echo serial terminfo"
ls -la /tmp/BOOTX64.EFI
