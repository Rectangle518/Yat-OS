; 目前的内存布局
; MBR         [0x7c00, 0x7e00)   512 bytes * 1
; Bootloader  [0x7e00, 0x8800)   512 bytes * 5
; GDT         [0x8800, 0x8880)   8 bytes   * 16（我们用到最多不超过16个段）

%include "boot.inc"

; TODO：取消下一行的注释
; extern open_page_mechanism

global bootloader_start
bootloader_start:
[bits 16]

; 下面往GDT中写入多个段描述符，记得每个段描述符都是8字节的
; 使用了平坦模式

;空描述符
mov dword [GDT_START_ADDRESS+0x00],0x00
mov dword [GDT_START_ADDRESS+0x04],0x00  

;创建描述符，这是一个数据段，对应0~4GB的线性地址空间
mov dword [GDT_START_ADDRESS+0x08],0x0000ffff    ; 基地址为0，段界限为0xFFFFF
mov dword [GDT_START_ADDRESS+0x0c],0x00cf9200    ; 粒度为4KB，存储器段描述符 

;建立保护模式下的堆栈段描述符      
mov dword [GDT_START_ADDRESS+0x10],0x00000000    ; 基地址为0x00000000，界限0x0 
mov dword [GDT_START_ADDRESS+0x14],0x00409600    ; 粒度为1个字节

;建立保护模式下的显存描述符   
mov dword [GDT_START_ADDRESS+0x18],0x80007fff    ; 基地址为0x000B8000，界限0x07FFF 
mov dword [GDT_START_ADDRESS+0x1c],0x0040920b    ; 粒度为字节

;创建保护模式下平坦模式代码段描述符
mov dword [GDT_START_ADDRESS+0x20],0x0000ffff    ; 基地址为0，段界限为0xFFFFF
mov dword [GDT_START_ADDRESS+0x24],0x00cf9800    ; 粒度为4kb，代码段描述符 

; 初始化描述符表寄存器GDTR
; 已经放入5个段描述符，每个段描述符8字节，界限为 5*8-1=39
; 在内存中使用一个48位的变量pgdt来表示GDTR的内容，pgdt这个变量的定义在本文件末尾
mov word [pgdt], 39
lgdt [pgdt]

; 当我们想进入保护模式时，首先需要打开第 21 根地址线
; 第21根地址线的开关位于南桥芯片的端口A20，使用 in，out 指令可以对主板端口进行读写操作
in al, 0x92                         ; 南桥芯片内的端口 
or al, 0000_0010B
out 0x92, al                        ; 打开A20

; 保护模式的真正开关——CR0
; CR0 是 32 位的寄存器，包含了一系列用于控制处理器操作模式和运行状态的标志位
; 其第0位是保护模式的开关位，称为PE（protect mode enable）位。 PE置1，CPU 进入保护模式
cli                                ; 保护模式下中断机制尚未建立，应禁止中断
mov eax, cr0
or eax, 1
mov cr0, eax                        ; 设置PE位

; 通过远跳转进入保护模式
; 此时，jmp指令将CODE_SELECTOR送入cs，将protect_mode_begin + LOADER_START_ADDRESS送入eip，进入保护模式
jmp dword CODE_SELECTOR:protect_mode_begin 

; 以下为保护模式下的代码
[bits 32]
protect_mode_begin:

; 设置段寄存器
; 因为在实模式下，段寄存器保存的是段基址（使用时需要左移4位），而在保护模式下，段寄存器保存的是段选择子
; 因此进入保护模式后需要重新设置各个段寄存器
mov eax, DATA_SELECTOR
mov ds, eax
mov es, eax
mov eax, STACK_SELECTOR
mov ss, eax
mov eax, VIDEO_SELECTOR
mov gs, eax

mov eax, KERNEL_START_SECTOR
mov ebx, KERNEL_START_ADDRESS
mov ecx, KERNEL_SECTOR_COUNT

; 假设我们实现的内核很小，因此下面我们约定内核的大小是200个扇区，起始地址是0x20000，内核存放在硬盘的起始位置是第6个扇区
load_kernel: 

    ; 即将调用asm_read_hard_disk函数，先通过栈传入参数
    push eax                 ; 传入参数2：要读取的逻辑扇区号，即block参数
    push ebx                 ; 传入参数1：要写入的内存地址，即memory参数
    call asm_read_hard_disk  ; 读取硬盘
    add esp, 8               ; 清理栈上的参数
    inc eax                  ; 读取下一个逻辑扇区，即block+1
    add ebx, 512             ; 内存地址增加512字节，指向下一个扇区的内存位置
    loop load_kernel

; TODO：取消下面几行的注释
; ============================================================================================
; call open_page_mechanism
; mov eax, PAGE_DIRECTORY
; mov cr3, eax ; 放入页目录表地址
; mov eax, cr0
; or eax, 0x80000000
; mov cr0, eax           ; 置PG=1，开启分页机制

; sgdt [pgdt]
; add dword[pgdt + 2], 0xc0000000
; lgdt [pgdt]
; ============================================================================================

; 跳转到内核入口
jmp dword CODE_SELECTOR:KERNEL_START_ADDRESS

; 死循环
jmp $

; asm_read_hard_disk(memory, block)
; 加载逻辑扇区号为block的扇区到内存地址memory

asm_read_hard_disk:                           
    push ebp
    mov ebp, esp

    push eax
    push ebx
    push ecx
    push edx

    mov eax, [ebp + 4 * 3] ; 第二个参数：逻辑扇区低16位

    mov edx, 0x1f3
    out dx, al    ; LBA地址7~0

    inc edx        ; 0x1f4
    mov al, ah
    out dx, al    ; LBA地址15~8

    xor eax, eax
    inc edx        ; 0x1f5
    out dx, al    ; LBA地址23~16 = 0

    inc edx        ; 0x1f6
    mov al, ah
    and al, 0x0f
    or al, 0xe0   ; LBA地址27~24 = 0
    out dx, al

    mov edx, 0x1f2
    mov al, 1
    out dx, al   ; 读取1个扇区

    mov edx, 0x1f7    ; 0x1f7
    mov al, 0x20     ;读命令
    out dx,al

    ; 等待处理其他操作
.waits:
    in al, dx        ; dx = 0x1f7
    and al,0x88
    cmp al,0x08
    jnz .waits                         
    
    ; 读取512字节到地址ds:bx
    mov ebx, [ebp + 4 * 2]
    mov ecx, 256   ; 每次读取一个字，2个字节，因此读取256次即可          
    mov edx, 0x1f0
.readw:
    in ax, dx
    mov [ebx], eax
    add ebx, 2
    loop .readw
      
    pop edx
    pop ecx
    pop ebx
    pop eax
    pop ebp

    ret

; 这是前面提到的 pgdt变量的定义
pgdt dw 0
    dd GDT_START_ADDRESS