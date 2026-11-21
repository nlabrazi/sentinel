import { createHmac, timingSafeEqual } from 'node:crypto'
import { appendFileSync, existsSync, readFileSync } from 'node:fs'
import path from 'node:path'
import { Client } from 'ssh2'
import { getEnv, type SentinelEnv } from '#server/utils/env'

export interface SshExecutionResult {
  exitCode: number
  stdout: string
  stderr: string
}

export interface SshExecutionOptions {
  timeoutSeconds?: number
  onStdout?: (chunk: string) => void
  onStderr?: (chunk: string) => void
  env?: SentinelEnv
}

export interface SshExecutor {
  execute(command: string, options?: SshExecutionOptions): Promise<SshExecutionResult>
}

export function shellEscape(value: string): string {
  return `'${value.replace(/'/g, "'\\''")}'`
}

export function wrapBashCommand(command: string): string {
  return `bash -lc ${shellEscape(command)}`
}

function matchesKnownHostPattern(hostEntry: string, targetHost: string): boolean {
  const candidates = hostEntry.split(',').map((entry) => entry.trim())
  const normalizedTarget = targetHost.toLowerCase()

  for (const candidate of candidates) {
    if (!candidate || candidate.startsWith('!')) {
      continue
    }

    if (candidate.startsWith('|1|')) {
      const parts = candidate.split('|')
      if (parts.length === 4 && parts[2] && parts[3]) {
        try {
          const salt = Buffer.from(parts[2], 'base64')
          const expected = Buffer.from(parts[3], 'base64')
          const computed = createHmac('sha1', salt).update(normalizedTarget).digest()
          if (expected.length === computed.length && timingSafeEqual(expected, computed)) {
            return true
          }
        } catch {
          // Malformed hashed known_hosts entry
        }
      }
      continue
    }

    const stripped = candidate.replace(/^\[([^\]]+)\]:\d+$/, '$1').toLowerCase()
    if (stripped === normalizedTarget) {
      return true
    }
  }

  return false
}

export function verifyKnownHostKey(params: {
  host: string
  keyBuffer: Buffer
  mode: 'always' | 'accept_new' | 'never'
  knownHostsContent: string | null
  onAcceptNew?: (line: string) => void
}): boolean {
  if (params.mode === 'never') {
    return true
  }

  const presentedKeyBase64 = params.keyBuffer.toString('base64')
  const keyType = extractSshKeyType(params.keyBuffer)

  let hostFound = false
  if (params.knownHostsContent) {
    for (const rawLine of params.knownHostsContent.split(/\r?\n/)) {
      const line = rawLine.trim()
      if (!line || line.startsWith('#')) {
        continue
      }
      const tokens = line.split(/\s+/)
      if (tokens.length < 3 || !tokens[0] || !tokens[2]) {
        continue
      }
      if (!matchesKnownHostPattern(tokens[0], params.host)) {
        continue
      }
      hostFound = true
      if (tokens[2] === presentedKeyBase64) {
        return true
      }
    }
  }

  if (!hostFound && params.mode === 'accept_new') {
    params.onAcceptNew?.(`${params.host} ${keyType} ${presentedKeyBase64}\n`)
    return true
  }

  return false
}

function extractSshKeyType(keyBuffer: Buffer): string {
  if (keyBuffer.length < 4) {
    return 'ssh-unknown'
  }
  const len = keyBuffer.readUInt32BE(0)
  if (len <= 0 || len + 4 > keyBuffer.length) {
    return 'ssh-unknown'
  }
  return keyBuffer.subarray(4, 4 + len).toString('utf8')
}

export async function executeSshCommand(
  command: string,
  options: SshExecutionOptions = {},
): Promise<SshExecutionResult> {
  const env = options.env ?? getEnv()
  const { host, user, sshKeyPath, sshKnownHostsPath, sshVerifyHostKey } = env.vps

  if (!host) {
    return { exitCode: 1, stdout: '', stderr: 'VPS_HOST is not configured' }
  }

  const resolvedKeyPath = path.resolve(process.cwd(), sshKeyPath)
  if (!existsSync(resolvedKeyPath)) {
    return { exitCode: 1, stdout: '', stderr: `SSH private key not found at ${sshKeyPath}` }
  }

  let privateKey: Buffer
  try {
    privateKey = readFileSync(resolvedKeyPath)
  } catch (error) {
    return {
      exitCode: 1,
      stdout: '',
      stderr: `Unable to read SSH private key: ${error instanceof Error ? error.message : String(error)}`,
    }
  }

  const resolvedKnownHostsPath = path.resolve(process.cwd(), sshKnownHostsPath)
  const knownHostsContent = existsSync(resolvedKnownHostsPath)
    ? readFileSync(resolvedKnownHostsPath, 'utf8')
    : null

  const timeoutMs = (options.timeoutSeconds ?? env.vps.commandTimeoutSeconds) * 1000
  const readyTimeoutMs = env.vps.connectTimeoutSeconds * 1000

  return new Promise<SshExecutionResult>((resolve) => {
    const client = new Client()
    let stdout = ''
    let stderr = ''
    let settled = false

    const finish = (result: SshExecutionResult) => {
      if (settled) {
        return
      }
      settled = true
      clearTimeout(timer)
      try {
        client.end()
      } catch {
        // Ignore cleanup errors
      }
      resolve(result)
    }

    const timer = setTimeout(() => {
      client.destroy()
      finish({
        exitCode: 124,
        stdout,
        stderr: stderr
          ? `${stderr}\nCommand timed out after ${Math.round(timeoutMs / 1000)}s.`
          : `Command timed out after ${Math.round(timeoutMs / 1000)}s.`,
      })
    }, timeoutMs)

    client
      .on('ready', () => {
        client.exec(command, (execErr, stream) => {
          if (execErr) {
            finish({ exitCode: 1, stdout, stderr: execErr.message })
            return
          }

          stream.on('data', (chunk: Buffer) => {
            const text = chunk.toString('utf8')
            stdout += text
            options.onStdout?.(text)
          })

          stream.stderr.on('data', (chunk: Buffer) => {
            const text = chunk.toString('utf8')
            stderr += text
            options.onStderr?.(text)
          })

          stream.on('close', (code: number | null) => {
            finish({ exitCode: code ?? 1, stdout, stderr })
          })
        })
      })
      .on('error', (err) => {
        finish({ exitCode: 1, stdout, stderr: err.message })
      })
      .connect({
        host,
        port: 22,
        username: user,
        privateKey,
        readyTimeout: readyTimeoutMs,
        hostVerifier: (hashedOrRawKey: Buffer) =>
          verifyKnownHostKey({
            host,
            keyBuffer: hashedOrRawKey,
            mode: sshVerifyHostKey,
            knownHostsContent,
            onAcceptNew: (line) => {
              try {
                appendFileSync(resolvedKnownHostsPath, line, 'utf8')
              } catch {
                // Non-fatal if known_hosts is mounted read-only
              }
            },
          }),
      })
  })
}

export const defaultSshExecutor: SshExecutor = {
  execute: executeSshCommand,
}
