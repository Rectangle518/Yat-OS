[bits 32]

%include "boot.inc"

global asm_hello_world
global asm_lidt
global asm_unhandled_interrupt
global asm_halt
global asm_out_port
global asm_in_port
global asm_time_interrupt_handler
global asm_enable_interrupt

extern c_time_interrupt_handler

; 定义一个字符串变量，用作提示信息，以 '\0' 结尾
ASM_UNHANDLED_INTERRUPT_INFO db 'Unhandled interrupt happened, halt...'
                             db 0

ASM_IDTR dw 0
         dd 0

; 定义打印字符串 "Hello World" 的函数
asm_hello_world:
    push eax
    xor eax, eax

    mov ah, 0x03 ;青色
    mov al, 'H'
    mov [gs:2 * 0], ax

    mov al, 'e'
    mov [gs:2 * 1], ax

    mov al, 'l'
    mov [gs:2 * 2], ax

    mov al, 'l'
    mov [gs:2 * 3], ax

    mov al, 'o'
    mov [gs:2 * 4], ax

    mov al, ' '
    mov [gs:2 * 5], ax

    mov al, 'W'
    mov [gs:2 * 6], ax

    mov al, 'o'
    mov [gs:2 * 7], ax

    mov al, 'r'
    mov [gs:2 * 8], ax

    mov al, 'l'
    mov [gs:2 * 9], ax

    mov al, 'd'
    mov [gs:2 * 10], ax

    pop eax
    ret

; 定义加载 IDT 的函数

; lidt指令：lidt [tag]
; lidt是将以tag为起始地址的48字节放入到寄存器IDTR中
; 由于我们打算在C代码中初始化IDT，而C语言的语法并未提供lidt语句
; 因此我们需要在汇编代码中实现能够将IDT的信息放入到IDTR的函数asm_lidt
; void asm_lidt(uint32 start, uint16 limit)
asm_lidt:
    push ebp
    mov ebp, esp
    push eax

    ; 参数二：IDT的界限，16位
    mov eax, [ebp + 4 * 3]
    mov [ASM_IDTR], ax

    ; 参数一：IDT的起始地址，32位
    mov eax, [ebp + 4 * 2]
    mov [ASM_IDTR + 2], eax
    lidt [ASM_IDTR]

    pop eax
    pop ebp
    ret

; 定义一个默认的中断处理函数
; 首先关中断，然后输出提示字符串，最后做死循环
; void asm_unhandled_interrupt()
asm_unhandled_interrupt:
    cli
    mov esi, ASM_UNHANDLED_INTERRUPT_INFO
    xor ebx, ebx
    mov ah, 0x03
.output_information:
    cmp byte[esi], 0
    je .end
    mov al, byte[esi]
    mov word[gs:bx], ax
    inc esi
    add ebx, 2
    jmp .output_information
.end:
    jmp $

; 阻塞（死循环）
asm_halt:
    jmp $

; 这个函数是对out命令的封装
; void asm_out_port(uint16 port, uint8 value)
asm_out_port:
    push ebp
    mov ebp, esp

    push edx
    push eax

    mov edx, [ebp + 4 * 2] ; port
    mov eax, [ebp + 4 * 3] ; value
    out dx, al
    
    pop eax
    pop edx
    pop ebp
    ret

; 这个函数是对in命令的封装
; void asm_in_port(uint16 port, uint8 *value)
asm_in_port:
    push ebp
    mov ebp, esp

    push edx
    push eax
    push ebx

    xor eax, eax
    mov edx, [ebp + 4 * 2] ; port
    mov ebx, [ebp + 4 * 3] ; *value

    in al, dx
    mov [ebx], al

    pop ebx
    pop eax
    pop edx
    pop ebp
    ret

; 这个函数是时间中断的处理函数
; 它不直接处理时钟中断，而是调用C中编写的时间中断处理函数
asm_time_interrupt_handler:

    ; pushad指令是将EAX,ECX,EDX,EBX,ESP,EBP,ESI,EDI依次入栈，popad则相反
    pushad
    
    nop ; 空操作，否则断点打不上去
    ; 发送EOI消息，否则下一次中断不发生
    mov al, 0x20
    out 0x20, al
    out 0xa0, al
    
    call c_time_interrupt_handler

    popad
    iret

; 开中断，使用sti指令
; void asm_enable_interrupt()
asm_enable_interrupt:
    sti
    ret