; Standalone bootable pong for x86
; Copyright (C) 2025 Ollie Etherington <www.etherington.xyz>
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
%define RELEASE_MASK	0x80	; Release events are masked with this

; GAME DATA
%define TARGET_FPS			19
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
%define BALL_SIZE			6
%define BALL_CENTER_X		((SCREEN_W / 2) - (BALL_SIZE / 2))
%define BALL_CENTER_Y		((SCREEN_H / 2) - (BALL_SIZE / 2))
%define BALL_SPEED			2

; MEMORY SEGMENTS
%define VMEM_SEG		0xa000
%define DATA_SEG		0x0050

; Offsets into general game data segment
%define bat1_y			0x00
%define bat2_y			0x02
%define bat1_vel		0x04
%define bat2_vel		0x06
%define ball_x			0x08
%define ball_y			0x0a
%define ball_vel_x		0x0c
%define ball_vel_y		0x0e
%define w_pressed		0x24
%define s_pressed		0x28

; ENTRY POINT
section .text

; Stop interrupts while we do some low level setup
cli

; Setup segment registers
mov ax, VMEM_SEG
mov es, ax
mov ax, DATA_SEG
mov gs, ax

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

; Init game data
mov word [gs:bat1_y],		BAT_CENTER_Y
mov word [gs:bat2_y],		BAT_CENTER_Y
mov word [gs:ball_x],		BALL_CENTER_X
mov word [gs:ball_y],		BALL_CENTER_Y
mov word [gs:ball_vel_x],	BALL_SPEED
;mov word [gs:ball_vel_y],	0
;mov byte [gs:w_pressed],	0
;mov byte [gs:s_pressed],	0

; Draw the background
mov ax, COL_BLUE
xor bx, bx
xor cx, cx
mov bp, SCREEN_W
mov dx, SCREEN_H
call fill_rect

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
	mov ax, COL_BLUE
	mov bx, COL_BLUE
	mov cx, COL_BLUE
	call draw_scene

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

	; Calculate ball velocity
	mov cx, word [gs:ball_x]					; cx = proposed new ball x
	; Left bat collision
	mov dx, word [gs:bat1_y]
	mov si, (BAT1_X + BAT_W - (BALL_SIZE / 2))	; Collide with the right side
	mov di, BALL_SPEED							; Push back right if colliding
	call check_collision
	; Right bat collision
	mov dx, word [gs:bat2_y]
	mov si, (BAT2_X - (BALL_SIZE / 2))			; Collide with the left side
	mov di, -BALL_SPEED							; Push back left if colliding
	call check_collision
	; Move the ball by its current velocity
	mov ax, word [gs:ball_x]
	add ax, word [gs:ball_vel_x]
	mov word [gs:ball_x], ax
	mov ax, word [gs:ball_y]
	add ax, word [gs:ball_vel_y]
	mov word [gs:ball_y], ax
	; Bounce the ball off the top and bottom of the screen
	mov ax, word [gs:ball_y]
	cmp ax, 0
	jge .check_bottom				; Hit top: reverse Y velocity and clamp
	mov word [gs:ball_y], 0
	jmp .reverse_ball_y_vel
.check_bottom:
	mov bx, SCREEN_H
	sub bx, BALL_SIZE
	cmp ax, bx
	jle .done_ball_y				; Hit bottom: reverse Y velocity and clamp
	mov word [gs:ball_y], bx
.reverse_ball_y_vel:
	mov ax, word [gs:ball_vel_y]
	neg ax
	mov word [gs:ball_vel_y], ax
.done_ball_y:

	; Draw the scene
	mov ax, COL_YELLOW
	mov bx, COL_L_GREEN
	mov cx, COL_L_RED
	call draw_scene

	; Sleep until we're ready for the next frame
	mov al, 0x34				; Set up PIT: channel 0, mode 2, LSB/MSB, binary
	out 0x43, al
	mov ax, PIT_RELOAD_VALUE	; Load reload value
	out 0x40, al				; send LSB
	mov al, ah
	out 0x40, al				; send MSB
.wait_loop:
	in al, 0x40					; Read back PIT counter
	loop .wait_loop

	; Next frame!
	jmp run_loop

; Check ball/bat collision: cx=new ball x, dx=bat y, si=bat x, di=push
; amount (positive to push right, negative to push left)
; Clobbers: ax, bx
; This function collides with the exact bat x in si, so the caller should
; account for the width of the bat and ball when setting this
check_collision:
	; Vertical check
	mov ax, word [gs:ball_y]
	add ax, BALL_SIZE
	cmp ax, dx
	jb .no_collision	; Is the top of the ball above the top of the bat?
	sub ax, BALL_SIZE
	mov bx, dx
	add bx, BAT_H
	cmp ax, bx
	ja .no_collision	; Is the top of the ball below the bottom of the bat
	; Horizontal check
	cmp cx, si
	jl .no_collision	; Is the ball completely to the left of the bat
	mov bx, si
	cmp cx, bx
	jg .no_collision	; Is the ball completely to the right of the bat
	; Collision! Reverse x velocity and push ball out of bat
	neg word [gs:ball_vel_x]
	mov ax, si
	add ax, di
	mov word [gs:ball_x], ax
	; Calculate signed hit y-offset in ax
	mov ax, word [gs:ball_y]
	add ax, BALL_SIZE / 2
	mov bx, dx
	add bx, BAT_H / 2
	sub ax, bx
	; Set the y velocity
	sar ax, 1			; Signed divide to scale down
	mov word [gs:ball_vel_y], ax
.no_collision:
	ret

; Draw the scene: ax=ball1 colour, bx=ball2 colour, cx=bat colour
draw_scene:
	push cx
	push bx
	push ax
	pop ax						; Bat 1
	mov bx, BAT1_X
	mov cx, word [gs:bat1_y]
	mov bp, BAT_W
	mov dx, BAT_H
	call fill_rect
	pop ax						; Bat 2
	mov bx, BAT2_X
	mov cx, word [gs:bat2_y]
	mov bp, BAT_W
	mov dx, BAT_H
	call fill_rect
	pop ax						; Ball
	mov bx, word [gs:ball_x]
	mov cx, word [gs:ball_y]
	mov bp, BALL_SIZE
	mov dx, BALL_SIZE
	call fill_rect
	ret

; Draw a rectangle: al=colour, bx=x, cx=y, bp=width, dx=height, es=segment
; Clobbers: ax, di
fill_rect:
	push ax				; Save the colour for later
	mov ax, cx			; ax = y
	imul ax, SCREEN_W	; ax = y * SCREEN_W
	mov di, ax			; di = y * SCREEN_W
	add di, bx			; di = y * SCREEN_W + x
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
