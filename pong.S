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

; COLOUR CODES
%define COL_BLACK		0x0
%define COL_BLUE		0x1
%define COL_GREEN		0x2
%define COL_CYAN		0x3
%define COL_RED			0x4
%define COL_MAGENTA		0x5
%define COL_BROWN		0x6
%define COL_L_GRAY		0x7
%define COL_GRAY		0x8
%define COL_L_BLUE		0x9
%define COL_L_GREEN		0xa
%define COL_L_CYAN		0xb
%define COL_L_RED		0xc
%define COL_L_MAGENTA	0xd
%define COL_YELLOW		0xe
%define COL_WHITE		0xf

; GAME DATA
%define SCREEN_W		320
%define SCREEN_H		200
%define VMEM_SIZE		(SCREEN_W * SCREEN_H)
%define BAT_W			6
%define BAT_H			26
%define BAT_MARGIN		20
%define BAT1_X			BAT_MARGIN
%define BAT2_X			(SCREEN_W - BAT_MARGIN - BAT_W)
%define BAT_CENTER_Y	((SCREEN_H / 2) - (BAT_H / 2))

; MEMORY SEGMENTS
%define VMEM_SEG		0xa000
%define DATA_SEG		0x0050

; Offsets into general game data segment
%define bat1_y			0x00
%define bat2_y			0x02

; Convenience macro to call fill_rect(colour, x, y, w, h)
%macro FILL_RECT 5
	mov al, %1
	mov bx, %2
	mov cx, %3
	mov bp, %4
	mov dx, %5
	call fill_rect
%endmacro

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

; Setup the game data segment in gs
mov ax, DATA_SEG
mov gs, ax

; TODO TMP
%define frame_count 0x22
mov byte [gs:frame_count], 0

; Init game data
mov word [gs:bat1_y],		BAT_CENTER_Y
mov word [gs:bat2_y],		BAT_CENTER_Y

; Run :-)
run_loop:
	; Wait for vsync
	mov dx, 0x3da
.wait_retrace_end:
	in al, dx
	test al, 8
	jnz .wait_retrace_end
.wait_retrace_start:
	in al, dx
	test al, 8
	jz .wait_retrace_start

	; Draw the scene
	mov ax, VMEM_SEG
	mov es, ax
	push bp
	FILL_RECT [gs:frame_count], 0, 0, SCREEN_W, SCREEN_H
	FILL_RECT COL_YELLOW, BAT1_X, word [gs:bat1_y], BAT_W, BAT_H
	FILL_RECT COL_BLUE, BAT2_X, word [gs:bat2_y], BAT_W, BAT_H
	pop bp

	; Next frame!
	inc byte [gs:frame_count]
	jmp run_loop

; Draw a rectangle: al=colour, bx=x, cx=y, bp=width, dx=height, es=segment
; Clobbers: ax, di
fill_rect:
	push ax				; Save the colour for later
	mov ax, cx          ; ax = y
	imul ax, SCREEN_W   ; ax = y * SCREEN_W
	mov di, ax			; di = y * SCREEN_W
	add di, bx          ; di = y * SCREEN_W + x
	pop ax				; Restore colour
.row:
	mov cx, bp			; cx = width (bytes)
	rep stosb			; write AL colour for width bytes
	add di, SCREEN_W	; next row
	sub di, bp			; correct for width advance
	dec dx				; height--
	jnz .row
	ret

; Fill file to 512 bytes with zeros and the final boot signature
times 510 - ($ - $$) db 0
dw 0xaa55
