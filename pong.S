; Standalone bootable pong for x86
; Copyright (C) 2025 Ollie Etherington
;
; This program is free software: you can redistribute it and/or modify
; it under the terms of the GNU General Public License as published by
; the Free Software Foundation, either version 3 of the License, or
; (at your option) any later version.
;
; This program is distributed in the hope that it will be useful,
; but WITHOUT ANY WARRANTY; without even the implied warranty of
; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
; GNU General Public License for more details.
;
; You should have received a copy of the GNU General Public License
; along with this program. If not, see <https://www.gnu.org/licenses/>.

[bits 16]			; 16 bit code :-(
[org 0x7c00]		; BIOS loads the bootloader at physical address 0x7c00

; ENTRY POINT
section .text

; Stop interrupts while we do some low level setup
cli

; Clear segment registers
xor ax, ax
mov ds, ax
mov es, ax
mov fs, ax
mov gs, ax
mov ss, ax

; Setup the stack
mov sp, (0x2000 - 0x10)	; Value taken from GRUB_MEMORY_MACHINE_REAL_STACK.
						; Conventional memory begins at 0x500, so this
						; gives a little under 7KiB of stack.
mov bp, sp

; Disable IRQ 1 - we'll handle the keyboard with ports 0x60 and 0x64
mov al, 2
out 0x21, al

; Reenable interrupts
sti

; Enter graphical mode
xor ah, ah
mov al, 0x13
int 0x10

; Loop
jmp $

; Fill file to 512 bytes with zeros and the final boot signature
times 510 - ($ - $$) db 0
dw 0xaa55
