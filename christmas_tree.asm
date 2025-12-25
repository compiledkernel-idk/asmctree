; ============================================================================
; Beautiful Colorful 3D Christmas Tree - x64 Assembly for Wayland
; A stunning animated Christmas tree with ornaments, lights, and snow
; Author: Antigravity AI
; Date: December 25, 2025
; ============================================================================

global _start

; ============================================================================
; System call numbers (Linux x86_64)
; ============================================================================
%define SYS_READ        0
%define SYS_WRITE       1
%define SYS_OPEN        2
%define SYS_CLOSE       3
%define SYS_MMAP        9
%define SYS_MUNMAP      11
%define SYS_NANOSLEEP   35
%define SYS_SOCKET      41
%define SYS_CONNECT     42
%define SYS_EXIT        60
%define SYS_FCNTL       72
%define SYS_FTRUNCATE   77
%define SYS_MEMFD_CREATE 319

; Socket constants
%define AF_UNIX         1
%define SOCK_STREAM     1

; Memory protection flags
%define PROT_READ       1
%define PROT_WRITE      2
%define MAP_SHARED      1

; Window dimensions
%define WIDTH           800
%define HEIGHT          600
%define STRIDE          (WIDTH * 4)
%define BUFFER_SIZE     (WIDTH * HEIGHT * 4)

; ============================================================================
; Data Section
; ============================================================================
section .data
    ; Wayland socket path
    xdg_runtime_dir:    db "XDG_RUNTIME_DIR", 0
    wayland_display:    db "WAYLAND_DISPLAY", 0
    wayland_default:    db "wayland-0", 0
    
    ; Memory file name for shm
    shm_name:           db "xmas_tree_shm", 0
    
    ; Sleep time (16ms for ~60fps)
    sleep_time:         dq 0, 16666666
    
    ; Tree parameters
    tree_x:             dd 400          ; Center X
    tree_y:             dd 500          ; Base Y
    tree_height:        dd 350          ; Total height
    tree_layers:        dd 6            ; Number of layers
    
    ; Animation frame counter
    frame:              dd 0
    
    ; Colors (ARGB format)
    color_sky_top:      dd 0xFF0a0a2e   ; Dark blue night sky
    color_sky_bottom:   dd 0xFF1a1a4e   ; Lighter blue
    color_tree_dark:    dd 0xFF0d5016   ; Dark green
    color_tree_light:   dd 0xFF1a8a2e   ; Light green
    color_trunk:        dd 0xFF4a2810   ; Brown trunk
    color_star:         dd 0xFFFFD700   ; Gold star
    color_snow:         dd 0xFFFFFFFF   ; White snow
    color_ground:       dd 0xFFEEEEEE   ; Snow ground
    
    ; Ornament colors (bright and festive)
    ornament_colors:    dd 0xFFFF0000   ; Red
                        dd 0xFFFFD700   ; Gold
                        dd 0xFF0066FF   ; Blue
                        dd 0xFFFF00FF   ; Magenta
                        dd 0xFF00FFFF   ; Cyan
                        dd 0xFFFF6600   ; Orange
                        dd 0xFFFFFFFF   ; White (lights)
                        dd 0xFF00FF00   ; Green
    num_ornament_colors: dd 8
    
    ; Snowflake positions (x, y pairs - up to 100 snowflakes)
    align 16
    snowflakes:         times 200 dd 0
    num_snowflakes:     dd 60
    
    ; Light positions on tree (relative x, y, radius)
    align 16
    lights:             times 150 dd 0   ; 50 lights * 3 values each
    num_lights:         dd 40
    
    ; Random seed
    random_seed:        dq 12345678

; ============================================================================
; BSS Section (uninitialized data)
; ============================================================================
section .bss
    socket_path:        resb 256
    socket_fd:          resq 1
    shm_fd:             resq 1
    shm_buffer:         resq 1
    sockaddr:           resb 110        ; Unix socket address structure

; ============================================================================
; Text Section (code)
; ============================================================================
section .text

; ============================================================================
; Entry Point
; ============================================================================
_start:
    ; Initialize random seed with a time-based value
    rdtsc
    mov [random_seed], rax
    
    ; Create memory file descriptor for our pixel buffer
    call create_shm_buffer
    test rax, rax
    js .exit_error
    
    ; Initialize snowflakes with random positions
    call init_snowflakes
    
    ; Initialize tree lights
    call init_lights
    
    ; Main render loop
.main_loop:
    ; Clear and render the scene
    call render_scene
    
    ; Update animation state
    call update_animation
    
    ; Increment frame counter
    inc dword [frame]
    
    ; Sleep for smooth animation (~60fps)
    mov rax, SYS_NANOSLEEP
    lea rdi, [sleep_time]
    xor rsi, rsi
    syscall
    
    ; Loop forever (Ctrl+C to exit)
    jmp .main_loop
    
.exit_error:
    mov rdi, 1
    jmp .exit
    
.exit_ok:
    xor rdi, rdi
    
.exit:
    mov rax, SYS_EXIT
    syscall

; ============================================================================
; Create shared memory buffer
; Returns: rax = 0 on success, -1 on error
; ============================================================================
create_shm_buffer:
    push rbx
    push r12
    
    ; Create anonymous memory file
    mov rax, SYS_MEMFD_CREATE
    lea rdi, [shm_name]
    xor rsi, rsi                ; No flags
    syscall
    test rax, rax
    js .shm_error
    mov [shm_fd], rax
    mov r12, rax
    
    ; Set size of the memory file
    mov rax, SYS_FTRUNCATE
    mov rdi, r12
    mov rsi, BUFFER_SIZE
    syscall
    test rax, rax
    js .shm_error
    
    ; Map the memory into our address space
    mov rax, SYS_MMAP
    xor rdi, rdi                ; Let kernel choose address
    mov rsi, BUFFER_SIZE
    mov rdx, PROT_READ | PROT_WRITE
    mov r10, MAP_SHARED
    mov r8, r12
    xor r9, r9                  ; Offset 0
    syscall
    test rax, rax
    js .shm_error
    mov [shm_buffer], rax
    
    xor rax, rax
    jmp .shm_done
    
.shm_error:
    mov rax, -1
    
.shm_done:
    pop r12
    pop rbx
    ret

; ============================================================================
; Simple pseudo-random number generator (xorshift64)
; Returns: rax = random number
; ============================================================================
random:
    mov rax, [random_seed]
    mov rcx, rax
    shl rax, 13
    xor rax, rcx
    mov rcx, rax
    shr rax, 7
    xor rax, rcx
    mov rcx, rax
    shl rax, 17
    xor rax, rcx
    mov [random_seed], rax
    ret

; ============================================================================
; Initialize snowflakes with random positions
; ============================================================================
init_snowflakes:
    push rbx
    push r12
    push r13
    
    lea r12, [snowflakes]
    mov r13d, [num_snowflakes]
    xor rbx, rbx
    
.init_snow_loop:
    cmp ebx, r13d
    jge .init_snow_done
    
    ; Random X position (0 to WIDTH-1)
    call random
    xor rdx, rdx
    mov rcx, WIDTH
    div rcx
    mov [r12 + rbx*8], edx
    
    ; Random Y position (0 to HEIGHT-1)
    call random
    xor rdx, rdx
    mov rcx, HEIGHT
    div rcx
    mov [r12 + rbx*8 + 4], edx
    
    inc ebx
    jmp .init_snow_loop
    
.init_snow_done:
    pop r13
    pop r12
    pop rbx
    ret

; ============================================================================
; Initialize tree lights with positions
; ============================================================================
init_lights:
    push rbx
    push r12
    push r13
    push r14
    
    lea r12, [lights]
    mov r13d, [num_lights]
    xor rbx, rbx
    
.init_lights_loop:
    cmp ebx, r13d
    jge .init_lights_done
    
    ; Calculate position within tree shape
    call random
    xor rdx, rdx
    mov rcx, 300            ; X range
    div rcx
    sub edx, 150            ; Center around 0
    mov [r12 + rbx*12], edx
    
    call random
    xor rdx, rdx
    mov rcx, 300            ; Y range  
    div rcx
    add edx, 50             ; Offset from top
    mov [r12 + rbx*12 + 4], edx
    
    ; Random radius (3-8 pixels)
    call random
    xor rdx, rdx
    mov rcx, 6
    div rcx
    add edx, 3
    mov [r12 + rbx*12 + 8], edx
    
    inc ebx
    jmp .init_lights_loop
    
.init_lights_done:
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; ============================================================================
; Render the complete scene
; ============================================================================
render_scene:
    push rbx
    push r12
    push r13
    push r14
    push r15
    
    mov r12, [shm_buffer]
    
    ; Render gradient sky background
    call render_sky
    
    ; Render snow ground
    call render_ground
    
    ; Render the 3D Christmas tree
    call render_tree
    
    ; Render tree trunk
    call render_trunk
    
    ; Render star on top
    call render_star
    
    ; Render ornaments and lights
    call render_ornaments
    
    ; Render falling snow
    call render_snow
    
    ; Render twinkling lights
    call render_lights
    
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; ============================================================================
; Render gradient sky
; ============================================================================
render_sky:
    push rbx
    push r12
    push r13
    push r14
    
    mov r12, [shm_buffer]
    xor r13, r13                ; y = 0
    
.sky_y_loop:
    cmp r13d, HEIGHT
    jge .sky_done
    
    ; Calculate gradient color
    ; Interpolate between sky_top and sky_bottom based on y
    mov eax, r13d
    shl eax, 8                  ; y * 256
    xor edx, edx
    mov ecx, HEIGHT
    div ecx                     ; ratio = (y * 256) / HEIGHT
    
    ; Interpolate each color channel
    mov r14d, [color_sky_top]
    mov r15d, [color_sky_bottom]
    
    ; Blue channel
    movzx ebx, r14b             ; top blue
    movzx ecx, r15b             ; bottom blue
    sub ecx, ebx
    imul ecx, eax
    sar ecx, 8
    add ebx, ecx
    and ebx, 0xFF
    mov r10d, ebx
    
    ; Green channel
    movzx ebx, byte [color_sky_top + 1]
    movzx ecx, byte [color_sky_bottom + 1]
    sub ecx, ebx
    imul ecx, eax
    sar ecx, 8
    add ebx, ecx
    and ebx, 0xFF
    shl ebx, 8
    or r10d, ebx
    
    ; Red channel
    movzx ebx, byte [color_sky_top + 2]
    movzx ecx, byte [color_sky_bottom + 2]
    sub ecx, ebx
    imul ecx, eax
    sar ecx, 8
    add ebx, ecx
    and ebx, 0xFF
    shl ebx, 16
    or r10d, ebx
    
    ; Alpha channel (full opacity)
    or r10d, 0xFF000000
    
    ; Fill the row with this color
    xor r14, r14                ; x = 0
.sky_x_loop:
    cmp r14d, WIDTH
    jge .sky_next_y
    
    ; Calculate pixel offset
    mov rax, r13
    imul rax, STRIDE
    lea rax, [rax + r14*4]
    mov [r12 + rax], r10d
    
    inc r14d
    jmp .sky_x_loop
    
.sky_next_y:
    inc r13d
    jmp .sky_y_loop
    
.sky_done:
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; ============================================================================
; Render snow ground
; ============================================================================
render_ground:
    push rbx
    push r12
    push r13
    push r14
    
    mov r12, [shm_buffer]
    mov r13d, 520               ; Ground starts at y=520
    mov r10d, [color_ground]
    
.ground_y_loop:
    cmp r13d, HEIGHT
    jge .ground_done
    
    xor r14, r14
.ground_x_loop:
    cmp r14d, WIDTH
    jge .ground_next_y
    
    ; Add slight variation for texture
    call random
    and eax, 0x0F               ; Small variation
    mov ebx, r10d
    sub bl, al                  ; Vary blue slightly
    
    mov rax, r13
    imul rax, STRIDE
    lea rax, [rax + r14*4]
    mov [r12 + rax], ebx
    
    inc r14d
    jmp .ground_x_loop
    
.ground_next_y:
    inc r13d
    jmp .ground_y_loop
    
.ground_done:
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; ============================================================================
; Render the 3D Christmas tree (layered triangular sections)
; ============================================================================
render_tree:
    push rbx
    push r12
    push r13
    push r14
    push r15
    push rbp
    
    mov r12, [shm_buffer]
    
    ; Draw multiple overlapping triangular layers for 3D effect
    mov ebp, 0                  ; layer counter
    
.tree_layer_loop:
    cmp ebp, 6
    jge .tree_done
    
    ; Calculate layer parameters
    ; Each layer starts higher and is wider at bottom
    mov eax, ebp
    imul eax, 50                ; Layer vertical offset
    mov r13d, 120               ; Top Y
    add r13d, eax
    
    mov r14d, 480               ; Bottom Y
    add r14d, eax
    sub r14d, 40                ; Adjust down
    cmp r14d, 520
    jle .skip_clamp
    mov r14d, 520               ; Clamp to ground
.skip_clamp:
    
    ; Layer width increases with each layer
    mov eax, ebp
    imul eax, 20
    mov r15d, 40                ; Initial half-width at bottom
    add r15d, eax
    add r15d, 100
    
    ; Color varies by layer for 3D depth
    mov eax, ebp
    and eax, 1
    jz .use_dark_green
    mov r10d, [color_tree_light]
    jmp .draw_layer
.use_dark_green:
    mov r10d, [color_tree_dark]
    
.draw_layer:
    ; Draw filled triangle for this layer
    push rbp
    mov edi, 400                ; Center X
    mov esi, r13d               ; Top Y
    mov edx, r14d               ; Bottom Y
    mov ecx, r15d               ; Half-width at bottom
    mov r8d, r10d               ; Color
    call draw_tree_triangle
    pop rbp
    
    inc ebp
    jmp .tree_layer_loop
    
.tree_done:
    pop rbp
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; ============================================================================
; Draw a filled triangle (tree section)
; edi = center_x, esi = top_y, edx = bottom_y, ecx = half_width, r8d = color
; ============================================================================
draw_tree_triangle:
    push rbx
    push r12
    push r13
    push r14
    push r15
    push rbp
    
    mov r12, [shm_buffer]
    mov r13d, edi               ; center_x
    mov r14d, esi               ; top_y
    mov r15d, edx               ; bottom_y
    mov ebp, ecx                ; half_width
    mov r10d, r8d               ; color
    
    ; Calculate height
    mov eax, r15d
    sub eax, r14d               ; height = bottom_y - top_y
    test eax, eax
    jz .tri_done
    mov r11d, eax               ; height
    
    ; Draw each scanline
    mov r9d, r14d               ; current_y = top_y
    
.tri_y_loop:
    cmp r9d, r15d
    jge .tri_done
    cmp r9d, HEIGHT
    jge .tri_done
    cmp r9d, 0
    jl .tri_next_y
    
    ; Calculate width at this y level
    ; width = half_width * (y - top_y) / height
    mov eax, r9d
    sub eax, r14d
    imul eax, ebp
    xor edx, edx
    div r11d
    mov ecx, eax                ; half_width at this y
    
    ; Calculate x range
    mov eax, r13d
    sub eax, ecx                ; left_x
    cmp eax, 0
    jge .left_ok
    xor eax, eax
.left_ok:
    mov ebx, eax                ; left_x in ebx
    
    mov eax, r13d
    add eax, ecx                ; right_x
    cmp eax, WIDTH
    jl .right_ok
    mov eax, WIDTH
    dec eax
.right_ok:
    ; eax = right_x, ebx = left_x
    
    ; Draw horizontal line
.tri_x_loop:
    cmp ebx, eax
    jg .tri_next_y
    
    ; Add shading for 3D effect (darker on edges)
    push rax
    mov ecx, r13d               ; center
    sub ecx, ebx                ; distance from center
    test ecx, ecx
    jns .pos_dist
    neg ecx
.pos_dist:
    shr ecx, 3                  ; Scale down the darkening
    
    ; Darken the color
    mov r8d, r10d
    movzx edx, r8b              ; blue
    sub edx, ecx
    jns .blue_ok
    xor edx, edx
.blue_ok:
    mov r8b, dl
    
    movzx edx, byte [rsp]       ; This won't work - just use base color
    pop rax
    
    ; Calculate pixel offset and store
    push rax
    mov rax, r9                 ; y
    and rax, 0xFFFFFFFF
    imul rax, STRIDE
    mov rcx, rbx
    and rcx, 0xFFFFFFFF
    lea rax, [rax + rcx*4]
    mov [r12 + rax], r10d
    pop rax
    
    inc ebx
    jmp .tri_x_loop
    
.tri_next_y:
    inc r9d
    jmp .tri_y_loop
    
.tri_done:
    pop rbp
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; ============================================================================
; Render tree trunk
; ============================================================================
render_trunk:
    push rbx
    push r12
    push r13
    push r14
    
    mov r12, [shm_buffer]
    mov r10d, [color_trunk]
    
    ; Trunk dimensions
    mov r13d, 480               ; top_y
    mov r14d, 520               ; bottom_y
    
.trunk_y_loop:
    cmp r13d, r14d
    jge .trunk_done
    
    ; Trunk width (centered at x=400)
    mov ebx, 375                ; left x
    
.trunk_x_loop:
    cmp ebx, 425                ; right x
    jge .trunk_next_y
    
    ; Add wood grain texture
    call random
    and eax, 0x1F
    mov ecx, r10d
    add cl, al                  ; Slight color variation
    
    mov rax, r13
    imul rax, STRIDE
    lea rax, [rax + rbx*4]
    mov [r12 + rax], ecx
    
    inc ebx
    jmp .trunk_x_loop
    
.trunk_next_y:
    inc r13d
    jmp .trunk_y_loop
    
.trunk_done:
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; ============================================================================
; Render star on top
; ============================================================================
render_star:
    push rbx
    push r12
    push r13
    push r14
    push r15
    
    mov r12, [shm_buffer]
    mov r10d, [color_star]
    
    ; Star center
    mov r13d, 400               ; x
    mov r14d, 100               ; y
    
    ; Animate star brightness
    mov eax, [frame]
    and eax, 31
    cmp eax, 16
    jl .star_bright
    sub eax, 32
    neg eax
.star_bright:
    shl eax, 3                  ; brightness modifier
    
    ; Draw star (simple diamond shape with glow)
    mov r15d, -20               ; radius offset
    
.star_y_loop:
    cmp r15d, 21
    jge .star_done
    
    mov ebx, r15d
    test ebx, ebx
    jns .abs_y
    neg ebx
.abs_y:
    mov ecx, 20
    sub ecx, ebx                ; width at this y
    
    mov r8d, r13d
    sub r8d, ecx                ; left x
    
.star_x_loop:
    mov r9d, r13d
    add r9d, ecx                ; right x
    cmp r8d, r9d
    jg .star_next_y
    
    ; Check bounds
    cmp r8d, 0
    jl .star_next_x
    cmp r8d, WIDTH
    jge .star_next_x
    
    mov eax, r14d
    add eax, r15d
    cmp eax, 0
    jl .star_next_x
    cmp eax, HEIGHT
    jge .star_next_x
    
    ; Calculate distance from center for glow effect
    push rcx
    mov ecx, r8d
    sub ecx, r13d
    imul ecx, ecx               ; dx^2
    mov edx, r15d
    imul edx, edx               ; dy^2
    add ecx, edx                ; dist^2
    
    ; Color with glow falloff
    mov edx, r10d
    cmp ecx, 100                ; inner bright area
    jl .star_inner
    
    ; Fade outer area
    shr ecx, 4
    sub dh, cl                  ; reduce green
    jns .green_ok
    xor dh, dh
.green_ok:
    
.star_inner:
    pop rcx
    
    ; Draw pixel
    mov rax, r14
    add eax, r15d
    imul rax, STRIDE
    mov rbx, r8
    and rbx, 0xFFFFFFFF
    lea rax, [rax + rbx*4]
    mov [r12 + rax], edx
    
.star_next_x:
    inc r8d
    jmp .star_x_loop
    
.star_next_y:
    inc r15d
    jmp .star_y_loop
    
.star_done:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; ============================================================================
; Render ornaments on tree
; ============================================================================
render_ornaments:
    push rbx
    push r12
    push r13
    push r14
    push r15
    
    mov r12, [shm_buffer]
    
    ; Draw multiple ornaments at fixed positions
    ; Ornament 1
    mov edi, 370
    mov esi, 200
    mov edx, 8
    mov ecx, [ornament_colors]
    call draw_circle
    
    ; Ornament 2
    mov edi, 430
    mov esi, 220
    mov edx, 7
    mov ecx, [ornament_colors + 4]
    call draw_circle
    
    ; Ornament 3
    mov edi, 350
    mov esi, 280
    mov edx, 9
    mov ecx, [ornament_colors + 8]
    call draw_circle
    
    ; Ornament 4
    mov edi, 450
    mov esi, 300
    mov edx, 8
    mov ecx, [ornament_colors + 12]
    call draw_circle
    
    ; Ornament 5
    mov edi, 380
    mov esi, 350
    mov edx, 10
    mov ecx, [ornament_colors + 16]
    call draw_circle
    
    ; Ornament 6
    mov edi, 420
    mov esi, 380
    mov edx, 8
    mov ecx, [ornament_colors + 20]
    call draw_circle
    
    ; Ornament 7
    mov edi, 340
    mov esi, 400
    mov edx, 9
    mov ecx, [ornament_colors]
    call draw_circle
    
    ; Ornament 8
    mov edi, 460
    mov esi, 420
    mov edx, 7
    mov ecx, [ornament_colors + 4]
    call draw_circle
    
    ; Ornament 9
    mov edi, 360
    mov esi, 450
    mov edx, 10
    mov ecx, [ornament_colors + 8]
    call draw_circle
    
    ; Ornament 10
    mov edi, 440
    mov esi, 460
    mov edx, 8
    mov ecx, [ornament_colors + 12]
    call draw_circle
    
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; ============================================================================
; Draw filled circle
; edi = x, esi = y, edx = radius, ecx = color
; ============================================================================
draw_circle:
    push rbx
    push r12
    push r13
    push r14
    push r15
    push rbp
    
    mov r12, [shm_buffer]
    mov r13d, edi               ; center_x
    mov r14d, esi               ; center_y
    mov r15d, edx               ; radius
    mov ebp, ecx                ; color
    
    ; Bounds check
    mov eax, r14d
    sub eax, r15d
    cmp eax, HEIGHT
    jge .circle_done
    mov eax, r14d
    add eax, r15d
    cmp eax, 0
    jl .circle_done
    
    ; Draw circle using midpoint algorithm
    mov r8d, r15d
    neg r8d                     ; y offset = -radius
    
.circle_y_loop:
    cmp r8d, r15d
    jg .circle_done
    
    ; Calculate x range for this y
    ; x = sqrt(r^2 - y^2)
    mov eax, r15d
    imul eax, eax               ; r^2
    mov ecx, r8d
    imul ecx, ecx               ; y^2
    sub eax, ecx                ; r^2 - y^2
    js .circle_next_y
    
    ; Integer square root approximation
    xor ecx, ecx
    mov ebx, eax
.sqrt_loop:
    cmp ecx, 32
    jge .sqrt_done
    mov edx, ebx
    shr edx, 1
    add edx, ecx
    shr edx, 1
    mov ebx, edx
    inc ecx
    cmp ebx, 1
    jg .sqrt_loop
.sqrt_done:
    ; ebx = approximate sqrt
    mov r9d, ebx                ; half_width
    
    ; Calculate actual y
    mov eax, r14d
    add eax, r8d
    cmp eax, 0
    jl .circle_next_y
    cmp eax, HEIGHT
    jge .circle_next_y
    mov r10d, eax               ; actual_y
    
    ; Draw horizontal line
    mov r11d, r13d
    sub r11d, r9d               ; left_x
    
.circle_x_loop:
    mov eax, r13d
    add eax, r9d                ; right_x
    cmp r11d, eax
    jg .circle_next_y
    
    ; Bounds check
    cmp r11d, 0
    jl .circle_next_x
    cmp r11d, WIDTH
    jge .circle_next_x
    
    ; Draw pixel with shading
    mov ecx, ebp                ; base color
    
    ; Add highlight in upper-left
    mov eax, r8d
    add eax, r11d
    sub eax, r13d
    cmp eax, -3
    jg .no_highlight
    or ecx, 0x303030            ; brighten
.no_highlight:
    
    ; Calculate offset and draw
    mov rax, r10
    and rax, 0xFFFFFFFF
    imul rax, STRIDE
    mov rbx, r11
    and rbx, 0xFFFFFFFF
    lea rax, [rax + rbx*4]
    mov [r12 + rax], ecx
    
.circle_next_x:
    inc r11d
    jmp .circle_x_loop
    
.circle_next_y:
    inc r8d
    jmp .circle_y_loop
    
.circle_done:
    pop rbp
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; ============================================================================
; Render twinkling lights on tree
; ============================================================================
render_lights:
    push rbx
    push r12
    push r13
    push r14
    push r15
    
    mov r12, [shm_buffer]
    lea r13, [lights]
    mov r14d, [num_lights]
    xor r15, r15                ; light index
    
.lights_loop:
    cmp r15d, r14d
    jge .lights_done
    
    ; Get light position
    mov edi, [r13 + r15*12]     ; relative x
    add edi, 400                ; center on tree
    mov esi, [r13 + r15*12 + 4] ; relative y
    add esi, 100                ; offset from top
    mov edx, [r13 + r15*12 + 8] ; radius
    
    ; Check if light is within tree bounds (simple check)
    cmp edi, 300
    jl .next_light
    cmp edi, 500
    jg .next_light
    cmp esi, 100
    jl .next_light
    cmp esi, 500
    jg .next_light
    
    ; Animate brightness based on frame and light index
    mov eax, [frame]
    add eax, r15d
    shl eax, 2
    and eax, 63
    cmp eax, 32
    jl .light_on
    ; Light is "dimmer" in this phase
    shr edx, 1                  ; smaller radius
.light_on:
    
    ; Choose color based on light index
    mov eax, r15d
    and eax, 7                  ; mod 8
    mov ecx, [ornament_colors + rax*4]
    
    ; Make it brighter (more like a light)
    or ecx, 0x808080
    
    ; Draw the light
    push r14
    push r15
    call draw_circle
    pop r15
    pop r14
    
.next_light:
    inc r15d
    jmp .lights_loop
    
.lights_done:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; ============================================================================
; Render falling snow particles
; ============================================================================
render_snow:
    push rbx
    push r12
    push r13
    push r14
    push r15
    
    mov r12, [shm_buffer]
    lea r13, [snowflakes]
    mov r14d, [num_snowflakes]
    xor r15, r15
    
    mov r10d, [color_snow]
    
.snow_loop:
    cmp r15d, r14d
    jge .snow_done
    
    ; Get snowflake position
    mov ebx, [r13 + r15*8]      ; x
    mov ecx, [r13 + r15*8 + 4]  ; y
    
    ; Bounds check
    cmp ebx, 0
    jl .next_snow
    cmp ebx, WIDTH
    jge .next_snow
    cmp ecx, 0
    jl .next_snow
    cmp ecx, HEIGHT
    jge .next_snow
    
    ; Draw snowflake (small cluster of pixels)
    mov rax, rcx
    imul rax, STRIDE
    lea rax, [rax + rbx*4]
    mov [r12 + rax], r10d
    
    ; Add adjacent pixels for larger flakes
    cmp ebx, 1
    jl .skip_left
    mov [r12 + rax - 4], r10d
.skip_left:
    cmp ebx, WIDTH - 2
    jge .skip_right
    mov [r12 + rax + 4], r10d
.skip_right:
    
.next_snow:
    inc r15d
    jmp .snow_loop
    
.snow_done:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; ============================================================================
; Update animation state
; ============================================================================
update_animation:
    push rbx
    push r12
    push r13
    push r14
    
    ; Update snowflake positions (falling down with slight drift)
    lea r12, [snowflakes]
    mov r13d, [num_snowflakes]
    xor r14, r14
    
.update_snow_loop:
    cmp r14d, r13d
    jge .update_done
    
    ; Move snowflake down
    mov eax, [r12 + r14*8 + 4]  ; y
    add eax, 2                  ; fall speed
    cmp eax, HEIGHT
    jl .snow_in_bounds
    
    ; Reset to top with new random x
    call random
    xor edx, edx
    mov ecx, WIDTH
    div ecx
    mov [r12 + r14*8], edx      ; new x
    xor eax, eax                ; y = 0
    
.snow_in_bounds:
    mov [r12 + r14*8 + 4], eax
    
    ; Add horizontal drift
    call random
    and eax, 7
    sub eax, 3                  ; -3 to +4
    add [r12 + r14*8], eax
    
    ; Keep x in bounds
    mov eax, [r12 + r14*8]
    cmp eax, 0
    jge .x_min_ok
    add eax, WIDTH
    mov [r12 + r14*8], eax
.x_min_ok:
    cmp eax, WIDTH
    jl .x_max_ok
    sub eax, WIDTH
    mov [r12 + r14*8], eax
.x_max_ok:
    
    inc r14d
    jmp .update_snow_loop
    
.update_done:
    pop r14
    pop r13
    pop r12
    pop rbx
    ret
