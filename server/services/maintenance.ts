import path from 'node:path'
import { eq } from 'drizzle-orm'
import type { SentinelDb } from '#server/db'
import { type ProjectRow, projects } from '#server/db/schema'
import {
  defaultSshExecutor,
  type SshExecutor,
  shellEscape,
  wrapBashCommand,
} from '#server/services/ssh'
import { getEnv } from '#server/utils/env'
import { isSafeVpsPath } from '#shared/schemas/project'

export function buildMaintenanceCommand(
  vpsPath: string,
  enabled: boolean,
  appsRoot = getEnv().vps.appsRoot,
): string {
  if (!isSafeVpsPath(vpsPath, appsRoot)) {
    throw new Error(`Unsafe VPS path rejected: ${vpsPath}`)
  }
  const flagPath = path.posix.join(vpsPath, 'maintenance.on')
  const action = enabled ? 'touch' : 'rm -f'
  return wrapBashCommand(`${action} ${shellEscape(flagPath)}`)
}

export async function toggleProjectMaintenance(
  db: SentinelDb,
  project: ProjectRow,
  enabled: boolean,
  ssh: SshExecutor = defaultSshExecutor,
  appsRoot = getEnv().vps.appsRoot,
): Promise<{ maintenanceMode: boolean }> {
  const command = buildMaintenanceCommand(project.vpsPath, enabled, appsRoot)
  const result = await ssh.execute(command, { timeoutSeconds: 15 })

  if (result.exitCode !== 0) {
    throw new Error(result.stderr.trim() || `Maintenance toggle failed (exit ${result.exitCode})`)
  }

  await db
    .update(projects)
    .set({
      maintenanceMode: enabled,
      updatedAt: new Date(),
    })
    .where(eq(projects.id, project.id))

  return { maintenanceMode: enabled }
}
