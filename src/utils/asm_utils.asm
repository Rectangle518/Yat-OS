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
global asm_disable_interrupt
global asm_interrupt_status
global asm_switch_thread
global asm_atomic_exchange
global asm_init_page_reg
global asm_system_call
global asm_system_call_handler

extern c_time_interrupt_handler
extern system_call_table

; 定义一个字符串变量，用作提示信息，以 '\0' 结尾
ASM_UNHANDLED_INTERRUPT_INFO db 'Unhandled interrupt happened, halt...'
                             db 0

ASM_IDTR dw 0
         dd 0

ASM_TEMP dd 0

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

; 关中断，使用cli指令
; void asm_disable_interrupt()
asm_disable_interrupt:
    cli
    ret

; 获取中断状态，返回中断标志位的值，返回值为0表示中断关闭，返回值为1表示中断开启
; int asm_interrupt_status();
asm_interrupt_status:
    xor eax, eax
    pushfd
    pop eax
    and eax, 0x200
    ret

; 切换线程，保存当前线程的上下文，恢复下一个线程的上下文
; void asm_switch_thread(PCB *cur, PCB *next);
asm_switch_thread:

    ; 将被调用者保存的寄存器入栈
    push ebp
    push ebx
    push edi
    push esi

    mov eax, [esp + 5 * 4]   ; 获取 cur参数
    mov [eax], esp           ; 当前栈顶指针esp保存到cur结构体的第一个字段（stack字段）

    mov eax, [esp + 6 * 4]   ; 获取 next参数
    mov esp, [eax]           ; 从 next结构体的第一个字段（stack字段）恢复栈顶指针esp

    pop esi
    pop edi
    pop ebx
    pop ebp

    sti
    ret

; 原子地交换一个32位寄存器和内存中的值
; 一个重要的假设：形式参数register指向的变量不是一个共享变量，只有满足这个条件才是原子的
; void asm_atomic_exchange(uint32 *register, uint32 *memeory);
asm_atomic_exchange:
    push ebp
    mov ebp, esp
    pushad

    mov ebx, [ebp + 4 * 2] ; register
    mov eax, [ebx]         ; 
    mov ebx, [ebp + 4 * 3] ; memory
    xchg [ebx], eax        ;
    mov ebx, [ebp + 4 * 2] ; memory
    mov [ebx], eax         ; 

    popad
    pop ebp
    ret

; 初始化页寄存器
; void asm_init_page_reg(uint32 *page_directory_table)
asm_init_page_reg:
    push ebp
    mov ebp, esp

    push eax

    mov eax, [ebp + 4 * 2]
    mov cr3, eax ; 放入页目录表地址
    mov eax, cr0
    or eax, 0x80000000
    mov cr0, eax           ; 置PG=1，开启分页机制

    pop eax
    pop ebp

    ret

; 系统调用
asm_system_call:
    push ebp
    mov ebp, esp

    ; 保护现场
    push ebx
    push ecx
    push edx
    push esi
    push edi
    push ds
    push es
    push fs
    push gs

    ; 将系统调用的参数放到5个寄存器ebx, ecx, edx, esi, edi中，将系统调用号放到eax中
    mov eax, [ebp + 2 * 4]
    mov ebx, [ebp + 3 * 4]
    mov ecx, [ebp + 4 * 4]
    mov edx, [ebp + 5 * 4]
    mov esi, [ebp + 6 * 4]
    mov edi, [ebp + 7 * 4]

    ; 我们将系统调用的中断向量号定义为0x80
    ; 保护现场后，使用指令int 0x80调用0x80中断
    ; 0x80中断处理函数会根据保存在eax的系统调用号来调用不同的函数
    int 0x80

    ; 恢复现场
    pop gs
    pop fs
    pop es
    pop ds
    pop edi
    pop esi
    pop edx
    pop ecx
    pop ebx
    pop ebp

    ret

; asm_system_call_handler是0x80号中断的处理函数
asm_system_call_handler:

    ; 保护现场
    push ds
    push es
    push fs
    push gs
    pushad

    ; 保存原始的 eax（系统调用号）
    push eax

    ; 栈段会从tss中自动加载

    ; 实际的系统调用处理函数是通过C语言来实现的
    ; 但是，由于中断发生后只是更改了cs寄存器，ds，es，fs和gs寄存器并未修改
    ; 因此在调用这些使用C语言实现的系统调用之前，我们需要手动修改这些段寄存器
    mov eax, DATA_SELECTOR
    mov ds, eax
    mov es, eax

    mov eax, VIDEO_SELECTOR
    mov gs, eax

    ; 恢复原始的 eax（系统调用号）
    pop eax

    ; 参数压栈
    push edi
    push esi
    push edx
    push ecx
    push ebx

    ; 开中断，调用系统调用处理函数
    sti    
    call dword[system_call_table + eax * 4]
    cli

    ; 修改esp寄存器，相当于将之前压入栈中的5个参数弹出栈
    add esp, 5 * 4
    
    ; 系统调用处理函数返回后，函数的返回值会放在eax中
    ; 因为eax保存了系统调用处理函数的返回值并且popad会修改eax的值，所以我们将eax保存在变量ASM_TEMP中
    ; ASM_TEMP的定义在本文件的开头
    mov [ASM_TEMP], eax

    ; 恢复现场
    popad
    pop gs
    pop fs
    pop es
    pop ds
    mov eax, [ASM_TEMP]
    
    iret