import { Cron } from 'croner'

export interface ScheduledTaskStatus {
  name: string
  schedule: string
  running: boolean
  lastRunAt: string | null
  lastSuccessAt: string | null
  lastDurationMs: number | null
  lastError: string | null
  runCount: number
  nextRunAt: string | null
}

interface RegisteredTask {
  name: string
  schedule: string
  job: Cron
  running: boolean
  lastRunAt: Date | null
  lastSuccessAt: Date | null
  lastDurationMs: number | null
  lastError: string | null
  runCount: number
  handler: () => Promise<void>
}

export class SentinelScheduler {
  private readonly tasks = new Map<string, RegisteredTask>()

  register(name: string, schedule: string, handler: () => Promise<void>): void {
    this.stopTask(name)

    const record: RegisteredTask = {
      name,
      schedule,
      running: false,
      lastRunAt: null,
      lastSuccessAt: null,
      lastDurationMs: null,
      lastError: null,
      runCount: 0,
      handler,
      job: new Cron(
        schedule,
        {
          protect: true,
          timezone: 'UTC',
          paused: false,
        },
        async () => {
          await this.executeTask(record)
        },
      ),
    }

    this.tasks.set(name, record)
  }

  async triggerNow(name: string): Promise<boolean> {
    const task = this.tasks.get(name)
    if (!task) {
      return false
    }
    await this.executeTask(task)
    return true
  }

  private async executeTask(record: RegisteredTask): Promise<void> {
    if (record.running) {
      return
    }
    record.running = true
    record.lastRunAt = new Date()
    const startedAt = Date.now()
    try {
      await record.handler()
      record.lastSuccessAt = new Date()
      record.lastError = null
    } catch (error) {
      record.lastError = error instanceof Error ? error.message : String(error)
      console.error(`[sentinel:scheduler] Task '${record.name}' failed:`, record.lastError)
    } finally {
      record.lastDurationMs = Date.now() - startedAt
      record.runCount += 1
      record.running = false
    }
  }

  getStatuses(): ScheduledTaskStatus[] {
    return Array.from(this.tasks.values()).map((task) => ({
      name: task.name,
      schedule: task.schedule,
      running: task.running,
      lastRunAt: task.lastRunAt?.toISOString() ?? null,
      lastSuccessAt: task.lastSuccessAt?.toISOString() ?? null,
      lastDurationMs: task.lastDurationMs,
      lastError: task.lastError,
      runCount: task.runCount,
      nextRunAt: task.job.nextRun()?.toISOString() ?? null,
    }))
  }

  stopTask(name: string): void {
    const existing = this.tasks.get(name)
    if (existing) {
      existing.job.stop()
      this.tasks.delete(name)
    }
  }

  stopAll(): void {
    for (const task of this.tasks.values()) {
      task.job.stop()
    }
    this.tasks.clear()
  }
}

export const sentinelScheduler = new SentinelScheduler()
