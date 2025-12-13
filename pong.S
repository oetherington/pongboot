; Standalone bootable pong for x86
; Copyright (C) Ollie Etherington <www.etherington.xyz>
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

; GAME CONSTANTS
%define TARGET_FPS			25
%define PIT_FREQUENCY		1193182
%define PIT_RELOAD_VALUE	(PIT_FREQUENCY / TARGET_FPS)
%define SCREEN_W			320
%define SCREEN_H			200
%define VMEM_SIZE			(SCREEN_W * SCREEN_H)
%define BG_COL				COL_BLUE
%define BAT_W				6
%define BAT_H				26
%define BAT_MARGIN			20
%define BAT1_X				BAT_MARGIN
%define BAT2_X				(SCREEN_W - BAT_MARGIN - BAT_W)
%define BAT_CENTER_Y		((SCREEN_H / 2) - (BAT_H / 2))
%define BAT_MIN_Y			0
%define BAT_MAX_Y			(SCREEN_H - BAT_H - 1)
%define BAT_SPEED			2
%define BALL_SIZE			6
%define BALL_CENTER_X		((SCREEN_W / 2) - (BALL_SIZE / 2))
%define BALL_CENTER_Y		((SCREEN_H / 2) - (BALL_SIZE / 2))
%define BALL_SPEED			2
%define BALL_UPDATE_FRAMES	2	; Update ball position every N frames

; MEMORY SEGMENTS
%define VMEM_SEG			0xa000
%define DATA_SEG			0x0050

; GAME VARIABLES (Offsets into general game data section below the stack)
%define bat1_y				0x00
%define bat2_y				0x02
%define ball_x				0x08
%define ball_y				0x0a
%define ball_vel_x			0x0c
%define ball_vel_y			0x0e
%define ball_update_frame	0x24
%define w_pressed			0x26
%define s_pressed			0x28

; ENTRY POINT
section .text

; Stop interrupts while we do some low level setup
cli

; Setup video segment register
mov ax, VMEM_SEG
mov es, ax

; Setup the stack - the value is taken from GRUB_MEMORY_MACHINE_REAL_STACK.
; Conventional memory begins at 0x500, so this gives almost 7KiB of stack.
mov sp, (0x2000 - 0x10)

; Reserve some space below the stack for persistent game data. Doing this
; instead of using a separate segment results in much smaller instructions (at
; the expense of not being able to use bp for anything else).
mov bp, sp
sub bp, 0x100

; Disable IRQ 1 - we'll handle the keyboard with ports 0x60 and 0x64
mov al, 2
out 0x21, al

; Reenable interrupts
sti

; Enter graphical mode
xor ah, ah
mov al, 0x13
int 0x10

; Init game state
mov [bp + bat1_y], BAT_CENTER_Y
mov [bp + bat2_y], BAT_CENTER_Y
mov word [bp + ball_x], BALL_CENTER_X
mov word [bp + ball_y], BALL_CENTER_Y
mov word [bp + ball_vel_x], -BALL_SPEED

; Paint the background
mov al, BG_COL
mov bx, 0
mov cx, 0
mov si, SCREEN_W
mov dx, SCREEN_H
call fill_rect

; Run :-)
run_loop:
	; Handle keyboard input
.input_loop:
	in al, 0x64				; Check if there's anything in the buffer
	test al, 1
	jz .input_done
	in al, 0x60				; Get the key
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
	mov byte [bp + w_pressed], bl
	jmp .input_loop
.store_s:
	mov byte [bp + s_pressed], bl
	jmp .input_loop
.input_done:

	; Clear the scene
	mov ax, BG_COL
	mov bx, ax
	mov cx, ax
	call draw_scene

	; W key moves bat up
	cmp byte [bp + w_pressed], 1
	jne .w_update_done
	sub word [bp + bat1_y], BAT_SPEED
.w_update_done:
	; S key moves bat down
	cmp byte [bp + s_pressed], 1
	jne .s_update_done
	add word [bp + bat1_y], BAT_SPEED
.s_update_done:

	; Clamp bats to screen bounds
	mov si, bat1_y
	call clamp_bat
	mov si, bat2_y
	call clamp_bat

	; Only update ball every N frames, otherwise it moves too fast
	inc byte [bp + ball_update_frame]
	cmp byte [bp + ball_update_frame], BALL_UPDATE_FRAMES
	jb .skip_reset
	mov byte [bp + ball_update_frame], 0

	; Calculate ball velocity
	mov cx, word [bp + ball_x]					; cx = proposed new ball x
	; Left bat collision
	mov dx, word [bp + bat1_y]
	mov si, (BAT1_X + BAT_W - (BALL_SIZE / 2))	; Collide with the right side
	mov di, BALL_SPEED							; Push back right if colliding
	call check_collision
	; Right bat collision
	mov dx, word [bp + bat2_y]
	mov si, (BAT2_X - (BALL_SIZE / 2))			; Collide with the left side
	mov di, -BALL_SPEED							; Push back left if colliding
	call check_collision
	; Move the ball by its current velocity
	mov ax, word [bp + ball_x]
	add ax, word [bp + ball_vel_x]
	mov word [bp + ball_x], ax
	mov ax, word [bp + ball_y]
	mov bx, ax		; Save ball y for later
	add ax, word [bp + ball_vel_y]
	mov word [bp + ball_y], ax
	; Bounce the ball off the top and bottom of the screen
	cmp bx, 0
	jge .check_bottom				; Hit top: reverse Y velocity and clamp
	mov word [bp + ball_y], 0
	jmp .reverse_ball_y_vel
.check_bottom:
	mov ax, SCREEN_H
	sub ax, BALL_SIZE
	cmp bx, ax
	jle .done_ball_y				; Hit bottom: reverse Y velocity and clamp
	mov word [bp + ball_y], ax
.reverse_ball_y_vel:
	mov ax, word [bp + ball_vel_y]
	neg ax
	mov word [bp + ball_vel_y], ax
.done_ball_y:
	; Reset the ball position when hitting the left or right
	mov ax, word [bp + ball_x]
	cmp ax, 0			; Check left bound
	jl .reset_ball
	cmp ax, SCREEN_W	; Check right bound
	jg .reset_ball
	jmp .skip_reset
.reset_ball:
	mov word [bp + ball_x], BALL_CENTER_X
	mov word [bp + ball_y], BALL_CENTER_Y
	neg word [bp + ball_vel_x]
	mov word [bp + ball_vel_y], 0
.skip_reset:

	; "AI" to move the other bat
	mov ax, [bp + ball_y]		; ax = current ball y
	add ax, BALL_SIZE / 2		; ax = ball center y
	mov bx, [bp + bat2_y]		; bx = current bat y
	add bx, BAT_H / 2			; bx = bat center y
	cmp ax, bx
	jz .ai_done					; Already aligned
	jb .ai_move_up				; Ball is above paddle - move up
	inc word [bp + bat2_y]
	jmp .ai_done
.ai_move_up:
	dec word [bp + bat2_y]
.ai_done:

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

; Clamp bat to screen bounds: si=memory offset to bat y position
; Clobbers: ax
clamp_bat:
	mov ax, word [bp + si]
	cmp ax, BAT_MIN_Y
	jge .not_negative
	mov word [bp + si], BAT_MIN_Y
	ret
.not_negative:
	cmp ax, BAT_MAX_Y
	jle .done
	mov word [bp + si], BAT_MAX_Y
.done:
	ret

; Check ball/bat collision: cx=new ball x, dx=bat y, si=bat x, di=push
; amount (positive to push right, negative to push left)
; Clobbers: ax, bx
; This function collides with the exact bat x in si, so the caller should
; account for the width of the bat and ball when setting this
check_collision:
	; Vertical check
	mov ax, word [bp + ball_y]
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
	neg word [bp + ball_vel_x]
	mov ax, si
	add ax, di
	mov word [bp + ball_x], ax
	; Calculate signed hit y-offset in ax
	mov ax, word [bp + ball_y]
	add ax, BALL_SIZE / 2
	mov bx, dx
	add bx, BAT_H / 2
	sub ax, bx
	; Set the y velocity
	sar ax, 2			; Signed divide to scale down
	mov word [bp + ball_vel_y], ax
.no_collision:
	ret

; Draw the scene: ax=ball1 colour, bx=ball2 colour, cx=bat colour
draw_scene:
	push cx
	push bx
	push ax
	pop ax						; Bat 1
	mov bx, BAT1_X
	mov cx, word [bp + bat1_y]
	mov si, BAT_W
	mov dx, BAT_H
	call fill_rect
	pop ax						; Bat 2
	mov bx, BAT2_X
	mov cx, word [bp + bat2_y]
	mov dx, BAT_H				; si is already BAT_W, no need to set it again
	call fill_rect
	pop ax						; Ball
	mov bx, word [bp + ball_x]
	mov cx, word [bp + ball_y]
	mov si, BALL_SIZE
	mov dx, si
	call fill_rect
	ret

; Draw a rectangle: al=colour, bx=x, cx=y, si=width, dx=height, es=video segment
; Clobbers: ax, di, cx, dx
fill_rect:
	push ax				; Save the colour for later
	mov ax, cx			; ax = y
	imul ax, SCREEN_W	; ax = y * SCREEN_W
	mov di, ax			; di = y * SCREEN_W
	add di, bx			; di = y * SCREEN_W + x
	pop ax				; Restore colour
.row:
	mov cx, si			; cx = width
	rep stosb			; Write AL colour for width bytes
	add di, SCREEN_W	; Next row
	sub di, si			; Backtrack width
	dec dx				; Height--
	jnz .row
	ret

; Fill file to 512 bytes with zeros and the final boot signature
times 510 - ($ - $$) db 0
dw 0xaa55
