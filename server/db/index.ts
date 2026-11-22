import path from 'node:path'
import { drizzle, type NodePgDatabase } from 'drizzle-orm/node-postgres'
import { migrate } from 'drizzle-orm/node-postgres/migrator'
import { Pool } from 'pg'
import * as schema from '#server/db/schema'
import { getEnv } from '#server/utils/env'

export type SentinelDb = NodePgDatabase<typeof schema>

let poolInstance: Pool | null = null
let dbInstance: SentinelDb | null = null

export function getPool(): Pool {
  if (!poolInstance) {
    const env = getEnv()
    poolInstance = new Pool({
      connectionString: env.databaseUrl,
      max: 10,
      idleTimeoutMillis: 30_000,
      connectionTimeoutMillis: 5_000,
    })
    poolInstance.on('error', (error) => {
      console.error('[sentinel:db] Idle PostgreSQL client error:', error.message)
    })
  }
  return poolInstance
}

export function getDb(): SentinelDb {
  if (!dbInstance) {
    dbInstance = drizzle(getPool(), { schema })
  }
  return dbInstance
}

export async function runMigrations(
  migrationsFolder = path.resolve(process.cwd(), 'server/db/migrations'),
): Promise<void> {
  const db = getDb()
  await migrate(db, { migrationsFolder })
}

export async function closeDb(): Promise<void> {
  if (poolInstance) {
    await poolInstance.end()
    poolInstance = null
    dbInstance = null
  }
}
