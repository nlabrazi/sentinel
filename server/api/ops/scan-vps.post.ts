import { getDb } from '#server/db'
import { discoverVpsProjects } from '#server/services/vps-discovery'
import type { VpsScanResponseDto } from '#shared/types/api'

export default defineEventHandler(async (): Promise<VpsScanResponseDto> => {
  try {
    return await discoverVpsProjects(getDb())
  } catch (error) {
    throw createError({
      statusCode: 502,
      statusMessage: 'VPS Discovery Failed',
      message: error instanceof Error ? error.message : 'Unable to scan VPS projects',
    })
  }
})
