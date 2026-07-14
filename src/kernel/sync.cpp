#include "sync.h"
#include "asm_utils.h"
#include "stdio.h"
#include "os_modules.h"
#include "program.h"

SpinLock::SpinLock()
{
    initialize();
}

void SpinLock::initialize()
{
    bolt = 0;
}

// 获取锁，如果锁已经被占用，则一直等待
void SpinLock::lock()
{
    uint32 key = 1;

    do
    {
        asm_atomic_exchange(&key, &bolt);
    } while (key);
}

// 释放锁
void SpinLock::unlock()
{
    bolt = 0;
}

// ------------------------------------------------------------

Semaphore::Semaphore()
{
    initialize(0);
}

void Semaphore::initialize(uint32 counter)
{
    this->counter = counter;
    semLock.initialize();
    waiting.initialize();
}

void Semaphore::P()
{
    PCB *cur = nullptr;

    while (true)
    {
        // 获取锁，是为了对 count和 waiting 实现互斥访问
        semLock.lock();

        // 如果 count > 0，表明有临界资源可分配，直接分配，并释放锁，返回
        if (counter > 0)
        {
            --counter;
            semLock.unlock();
            return;
        }

        // 否则，将当前进程加入等待队列，并释放锁，阻塞当前进程，执行线程调度
        cur = programManager.running;
        waiting.push_back(&(cur->tagInGeneralList));
        cur->status = ProgramStatus::BLOCKED;

        semLock.unlock();
        programManager.schedule();
    }
}

void Semaphore::V()
{
    // 获取锁，是为了对 count和 waiting 实现互斥访问
    semLock.lock();

    // ++count 表示释放一个资源，如果 waiting 队列不为空，则唤醒一个等待进程
    ++counter;
    if (waiting.size())
    {
        PCB *program = ListItem2PCB(waiting.front(), tagInGeneralList);
        waiting.pop_front();
        semLock.unlock();
        programManager.MESA_WakeUp(program);
    }
    else
    {
        semLock.unlock();
    }
}
