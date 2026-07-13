#ifndef STDARG_H
#define STDARG_H

// 定义一些宏，用于可变参数

// 定义 va_list 类型为 char * 类型
typedef char *va_list;

// 将n的大小向上对齐到int大小的整数倍
#define _INTSIZEOF(n) ((sizeof(n) + sizeof(int) - 1) & ~(sizeof(int) - 1))

// 初始化ap指向第一个可变参数
#define va_start(ap, v) (ap = (va_list)&v + _INTSIZEOF(v))

// 获取当前参数并自动移动到下一个
#define va_arg(ap, type) (*(type *)((ap += _INTSIZEOF(type)) - _INTSIZEOF(type)))

// 将ap置空，防止野指针
#define va_end(ap) (ap = (va_list)0)

#endif