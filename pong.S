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

; KEY SCAN CODES
%define SCAN_W			17		; 'w'
%define SCAN_S			31		; 's'
%define RELEASE_MASK	0x80	; Release events are masked with 0x80

; GAME DATA
%define TARGET_FPS			25
%define PIT_FREQUENCY		1193182
%define PIT_RELOAD_VALUE	(PIT_FREQUENCY / TARGET_FPS)
%define SCREEN_W			320
%define SCREEN_H			200
%define VMEM_SIZE			(SCREEN_W * SCREEN_H)
%define BAT_W				6
%define BAT_H				26
%define BAT_MARGIN			20
%define BAT1_X				BAT_MARGIN
%define BAT2_X				(SCREEN_W - BAT_MARGIN - BAT_W)
%define BAT_CENTER_Y		((SCREEN_H / 2) - (BAT_H / 2))
%define BAT_MIN_Y			0
%define BAT_MAX_Y			(SCREEN_H - BAT_H - 1)
%define BAT_SPEED			1

; MEMORY SEGMENTS
%define VMEM_SEG		0xa000
%define DATA_SEG		0x0050

; Offsets into general game data segment
%define bat1_y			0x00
%define bat2_y			0x02
%define bat1_vel		0x04
%define bat2_vel		0x06
%define w_pressed		0x24
%define s_pressed		0x28

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

; Init game data
mov word [gs:bat1_y],		BAT_CENTER_Y
mov word [gs:bat2_y],		BAT_CENTER_Y
mov byte [gs:w_pressed],	0
mov byte [gs:s_pressed],	0

; Draw the background
mov ax, VMEM_SEG
mov es, ax
push bp
FILL_RECT COL_BLUE, 0, 0, SCREEN_W, SCREEN_H
pop bp

; Run :-)
run_loop:
	; Handle keyboard input
.input_loop:
	in al, 0x64				; Check if there's anything in the buffer
	test al, 1
	jz .input_done
	test al, 0x20			; Check if it's a byte from the mouse
	jnz .input_done
	in al, 0x60				; It's keyboard input, so get the key
	mov bl, 1				; bl = 1 for press, bl = 0 for release
	test al, RELEASE_MASK
	jnz .was_release
	jmp .handle_key
.was_release:
	mov bl, 0
.handle_key:
	and al, byte (~RELEASE_MASK)	; Strip release bit to get base scancode
	cmp al, SCAN_W
	je .store_w
	cmp al, SCAN_S
	je .store_s
	jmp .input_loop
.store_w:
	mov byte [gs:w_pressed], bl
	jmp .input_loop
.store_s:
	mov byte [gs:s_pressed], bl
	jmp .input_loop
.input_done:

	; Clear the scene
	mov ax, VMEM_SEG
	mov es, ax
	FILL_RECT COL_BLUE, BAT1_X, word [gs:bat1_y], BAT_W, BAT_H
	FILL_RECT COL_BLUE, BAT2_X, word [gs:bat2_y], BAT_W, BAT_H

	; Calcuate bat velocities
	mov word [gs:bat1_vel], 0
	mov word [gs:bat2_vel], 0

	; W key moves bat up
	cmp byte [gs:w_pressed], 1
	jne .w_update_done
	mov byte [gs:bat1_vel], -1
	sub word [gs:bat1_y], BAT_SPEED
.w_update_done:
	; S key moves bat down
	cmp byte [gs:s_pressed], 1
	jne .s_update_done
	add word [gs:bat1_y], BAT_SPEED
.s_update_done:

	; Clamp bats to screen bounds
	mov ax, word [gs:bat1_y]
	cmp ax, BAT_MIN_Y
	jge .not_negative
	mov word [gs:bat1_y], BAT_MIN_Y
	jmp .clamp_done
.not_negative:
	cmp ax, BAT_MAX_Y
	jle .clamp_done
	mov word [gs:bat1_y], BAT_MAX_Y
.clamp_done:

	; Draw the scene
	mov ax, VMEM_SEG
	mov es, ax
	FILL_RECT COL_YELLOW, BAT1_X, word [gs:bat1_y], BAT_W, BAT_H
	FILL_RECT COL_L_GREEN, BAT2_X, word [gs:bat2_y], BAT_W, BAT_H

	; Next frame!
	call sleep
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

; Sleep until the next frame
; Clobbers: ax, dx, bx, cx
sleep:
	mov al, 0x34				; Set up PIT: channel 0, mode 2, LSB/MSB, binary
	out 0x43, al
	mov ax, PIT_RELOAD_VALUE	; Load reload value
	out 0x40, al				; send LSB
	mov al, ah
	out 0x40, al				; send MSB
.wait_loop:
	in al, 0x40      ; Read back PIT counter
	loop .wait_loop
	ret

; Fill file to 512 bytes with zeros and the final boot signature
times 510 - ($ - $$) db 0
dw 0xaa55
