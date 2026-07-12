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

; 这是前面提到的 pgdt变量的定义
pgdt dw 0
    dd GDT_START_ADDRESS