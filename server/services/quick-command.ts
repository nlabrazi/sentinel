import path from 'node:path'
import type { ProjectRow } from '#server/db/schema'
import { truncateLog } from '#server/services/deploy'
import { defaultSshExecutor, type SshExecutor, shellEscape } from '#server/services/ssh'
import { getEnv } from '#server/utils/env'
import { isSafeVpsPath } from '#shared/schemas/project'

export const QUICK_COMMAND_TIMEOUT_SECONDS = 10
export const QUICK_COMMAND_MAX_OUTPUT_BYTES = 64 * 1024
export const QUICK_COMMAND_MAX_LENGTH = 500

export const ALLOWED_BINARIES = new Set([
  'cat',
  'head',
  'tail',
  'grep',
  'egrep',
  'fgrep',
  'wc',
  'find',
  'ls',
  'diff',
  'stat',
  'file',
  'uptime',
  'df',
  'free',
  'ps',
  'pwd',
  'date',
  'whoami',
  'uname',
  'git',
  'docker',
  'docker-compose',
])

export const FORBIDDEN_TOKENS = new Set([
  'sudo',
  'su',
  'rm',
  'rmdir',
  'mv',
  'cp',
  'chmod',
  'chown',
  'chgrp',
  'kill',
  'killall',
  'pkill',
  'reboot',
  'shutdown',
  'poweroff',
  'halt',
  'init',
  'mkfs',
  'dd',
  'wget',
  'curl',
  'nc',
  'netcat',
  'ncat',
  'telnet',
  'eval',
  'exec',
  'python',
  'python3',
  'perl',
  'ruby',
  'php',
  'node',
  'npm',
  'yarn',
])

const FORBIDDEN_PATTERNS = [
  /\\/,
  /`/,
  /\$\(/,
  /[;&\r\n]/,
  /[><]/,
  /\.\./,
  /\.env/i,
  /\.key\b/i,
  /\.pem\b/i,
  /id_rsa/i,
  /sentinel_control_panel/i,
  /credentials(\.yml)?\.enc/i,
]

const SAFE_LOCAL_SCRIPT = /^\.\/[a-zA-Z0-9_-]+\.sh$/
const SAFE_SH_ARG = /^(\.\/)?[a-zA-Z0-9_-]+\.sh$/

export interface QuickCommandResult {
  success: boolean
  command: string
  exitCode: number
  stdout: string
  stderr: string
  durationSeconds: number
}

export function splitShellWords(input: string): string[] {
  const tokens: string[] = []
  let current = ''
  let quote: '"' | "'" | null = null
  let hasToken = false

  for (let i = 0; i < input.length; i += 1) {
    const ch = input[i]
    if (quote) {
      if (ch === quote) {
        quote = null
      } else {
        current += ch
      }
      continue
    }

    if (ch === '"' || ch === "'") {
      quote = ch
      hasToken = true
      continue
    }

    if (/\s/.test(ch ?? '')) {
      if (hasToken) {
        tokens.push(current)
        current = ''
        hasToken = false
      }
      continue
    }

    current += ch
    hasToken = true
  }

  if (quote) {
    throw new Error('Unmatched quote in command')
  }
  if (hasToken) {
    tokens.push(current)
  }

  return tokens
}

function validateSegment(segment: string): string | null {
  let tokens: string[]
  try {
    tokens = splitShellWords(segment)
  } catch (error) {
    return `Malformed command arguments: ${error instanceof Error ? error.message : String(error)}`
  }

  if (tokens.length === 0 || !tokens[0]) {
    return 'Empty command segment.'
  }

  const binary = tokens[0]

  for (const token of tokens) {
    const base = path.posix.basename(token).toLowerCase()
    if (FORBIDDEN_TOKENS.has(base)) {
      return `Forbidden command or token: ${base}`
    }
  }

  if (ALLOWED_BINARIES.has(binary)) {
    return null
  }

  if (SAFE_LOCAL_SCRIPT.test(binary)) {
    return null
  }

  if ((binary === 'sh' || binary === 'bash') && tokens[1] && SAFE_SH_ARG.test(tokens[1])) {
    return null
  }

  return `Unauthorized command '${binary}'. Only diagnostic binaries and local ./*.sh scripts are allowed.`
}

export function validateQuickCommand(rawCommand: string): string | null {
  const trimmed = rawCommand.trim()
  if (!trimmed) {
    return 'Command cannot be empty.'
  }
  if (trimmed.length > QUICK_COMMAND_MAX_LENGTH) {
    return `Command exceeds maximum length of ${QUICK_COMMAND_MAX_LENGTH} characters.`
  }

  for (const pattern of FORBIDDEN_PATTERNS) {
    if (pattern.test(trimmed)) {
      return 'Command contains forbidden syntax or accesses sensitive files.'
    }
  }

  const segments = trimmed.split('|').map((seg) => seg.trim())
  if (segments.some((seg) => !seg)) {
    return 'Command contains an empty pipeline segment.'
  }

  for (const segment of segments) {
    const err = validateSegment(segment)
    if (err) {
      return err
    }
  }

  return null
}

export async function executeQuickCommand(
  project: Pick<ProjectRow, 'slug' | 'vpsPath'>,
  rawCommand: string,
  ssh: SshExecutor = defaultSshExecutor,
  appsRoot = getEnv().vps.appsRoot,
): Promise<QuickCommandResult> {
  const command = rawCommand.trim()
  const validationError = validateQuickCommand(command)
  if (validationError) {
    return {
      success: false,
      command,
      exitCode: 1,
      stdout: '',
      stderr: validationError,
      durationSeconds: 0,
    }
  }

  if (!isSafeVpsPath(project.vpsPath, appsRoot)) {
    return {
      success: false,
      command,
      exitCode: 1,
      stdout: '',
      stderr: `Unsafe VPS path rejected: ${project.vpsPath}`,
      durationSeconds: 0,
    }
  }

  const startedAt = Date.now()
  const fullCommand = `cd ${shellEscape(project.vpsPath)} && ${command}`
  const result = await ssh.execute(fullCommand, {
    timeoutSeconds: QUICK_COMMAND_TIMEOUT_SECONDS,
  })
  const durationSeconds = Number(((Date.now() - startedAt) / 1000).toFixed(2))

  return {
    success: result.exitCode === 0,
    command,
    exitCode: result.exitCode,
    stdout: truncateLog(result.stdout, QUICK_COMMAND_MAX_OUTPUT_BYTES),
    stderr: truncateLog(result.stderr, QUICK_COMMAND_MAX_OUTPUT_BYTES),
    durationSeconds,
  }
}
