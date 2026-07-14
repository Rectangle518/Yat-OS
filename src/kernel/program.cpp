#include "program.h"
#include "stdlib.h"
#include "interrupt.h"
#include "asm_utils.h"
#include "stdio.h"
#include "thread.h"
#include "os_modules.h"

const int PCB_SIZE = 4096;                   // PCB的大小，4KB
char PCB_SET[PCB_SIZE * MAX_PROGRAM_AMOUNT]; // 存放PCB的数组，预留了MAX_PROGRAM_AMOUNT个PCB的大小空间
bool PCB_SET_STATUS[MAX_PROGRAM_AMOUNT];     // PCB的分配状态，true表示已经分配，false表示未分配

ProgramManager::ProgramManager()
{
    initialize();
}

void ProgramManager::initialize()
{
    allPrograms.initialize();
    readyPrograms.initialize();
    running = nullptr;

    // 将PCB_SET_STATUS数组全部初始化为false
    for (int i = 0; i < MAX_PROGRAM_AMOUNT; i++)
    {
        PCB_SET_STATUS[i] = false;
    }
}

// 线程实际上执行的是某一个函数的代码
// 但是，并不是所有的函数都可以放入到线程中执行的。这里我们规定线程只能执行返回值为void，参数为void *的函数，其中，void *指向了函数的参数
// 我们在include/program.h中将上面提到的这个函数定义为ThreadFunction
int ProgramManager::executeThread(ThreadFunction function, void *parameter, const char *name, int priority)
{
    // 关闭中断，防止线程创建过程中被中断
    bool status = interruptManager.getInterruptStatus();
    interruptManager.disableInterrupt();

    // 分配一页作为PCB
    PCB *thread = allocatePCB();

    if (!thread)
        return -1;

    // 初始化分配的页
    memset(thread, 0, PCB_SIZE);

    for (int i = 0; i < MAX_PROGRAM_NAME && name[i]; ++i)
    {
        thread->name[i] = name[i];
    }

    thread->status = ProgramStatus::READY;
    thread->priority = priority;
    thread->ticks = priority * 10;
    thread->ticksPassedBy = 0;
    thread->pid = ((int)thread - (int)PCB_SET) / PCB_SIZE;

    // 线程栈
    thread->stack = (int *)((int)thread + PCB_SIZE);
    thread->stack -= 7;
    thread->stack[0] = 0;
    thread->stack[1] = 0;
    thread->stack[2] = 0;
    thread->stack[3] = 0;
    thread->stack[4] = (int)function;
    thread->stack[5] = (int)program_exit;
    thread->stack[6] = (int)parameter;

    // 将线程添加到就绪队列和所有线程队列中
    allPrograms.push_back(&(thread->tagInAllList));
    readyPrograms.push_back(&(thread->tagInGeneralList));

    // 恢复中断
    interruptManager.setInterruptStatus(status);

    // 返回线程的PID
    return thread->pid;
}

// 分配一个PCB
PCB *ProgramManager::allocatePCB()
{
    // 遍历PCB_SET_STATUS数组，找到第一个为false的元素，表示该PCB还未被分配
    for (int i = 0; i < MAX_PROGRAM_AMOUNT; i++)
    {
        if (!PCB_SET_STATUS[i])
        {
            // 将该PCB的状态设置为已分配
            PCB_SET_STATUS[i] = true;

            // 返回该PCB的指针
            return (PCB *)((int)PCB_SET + i * PCB_SIZE);
        }
    }

    // 如果没有找到可用的PCB，返回nullptr
    return nullptr;
}

// 释放一个PCB
void ProgramManager::releasePCB(PCB *program)
{
    // 计算该PCB在PCB_SET数组中的索引
    int index = ((int)program - (int)PCB_SET) / PCB_SIZE;

    // 将该PCB的状态设置为未分配
    PCB_SET_STATUS[index] = false;
}

// 线程调度函数
void ProgramManager::schedule()
{
    // 关闭中断，防止线程调度过程中被中断
    bool status = interruptManager.getInterruptStatus();
    interruptManager.disableInterrupt();

    // 如果当前没有就绪的线程，则恢复中断，直接返回
    if (readyPrograms.size() == 0)
    {
        interruptManager.setInterruptStatus(status);
        return;
    }

    // 如果当前有正在运行的线程，则将其状态设置为就绪，重置时间片，并将其添加到就绪队列中
    if (running->status == ProgramStatus::RUNNING)
    {
        running->status = ProgramStatus::READY;
        running->ticks = running->priority * 10;
        readyPrograms.push_back(&(running->tagInGeneralList));
    }
    else if (running->status == ProgramStatus::DEAD)
    {
        // 如果当前线程已经死亡，则释放其PCB，并将其从所有线程队列中移除
        releasePCB(running);
    }

    // 从就绪队列中取出一个线程作为下一个运行的线程
    ListItem *item = readyPrograms.front();

    // 就绪队列的元素是ListItem *类型的，我们需要将其转换为PCB
    PCB *next = ListItem2PCB(item, tagInGeneralList);
    PCB *cur = running;
    next->status = ProgramStatus::RUNNING;
    running = next;
    readyPrograms.pop_front();

    // 切换线程上下文
    asm_switch_thread(cur, next);

    // 恢复中断
    interruptManager.setInterruptStatus(status);
}

// 线程退出函数
void program_exit()
{
    // 取出当前正在运行的线程，并将其状态设置为 DEAD
    PCB *thread = programManager.running;
    thread->status = ThreadStatus::DEAD;

    // 如果当前线程 pid不是0，则进行线程调度
    if (thread->pid)
    {
        programManager.schedule();
    }
    else
    {
        // 如果当前线程 pid是0，则表示操作系统线程退出，直接进入halt状态
        interruptManager.disableInterrupt();
        printf("halt\n");
        asm_halt();
    }
}

void ProgramManager::MESA_WakeUp(PCB *program) {
    program->status = ProgramStatus::READY;
    readyPrograms.push_front(&(program->tagInGeneralList));
}