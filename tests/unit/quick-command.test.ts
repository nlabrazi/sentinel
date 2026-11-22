import { describe, expect, it, vi } from 'vitest'
import { executeQuickCommand, validateQuickCommand } from '#server/services/quick-command'
import type { SshExecutor } from '#server/services/ssh'

describe('quick command security policy', () => {
  it('allows whitelisted diagnostic commands, safe pipelines and local .sh scripts', () => {
    expect(validateQuickCommand('docker compose ps')).toBeNull()
    expect(validateQuickCommand('docker compose logs --tail=50 | grep -i error')).toBeNull()
    expect(validateQuickCommand('git status -sb')).toBeNull()
    expect(validateQuickCommand('./status.sh')).toBeNull()
    expect(validateQuickCommand('bash ./status.sh')).toBeNull()
    expect(validateQuickCommand('df -h')).toBeNull()
  })

  it('blocks privilege escalation, destructive binaries, chaining, interpreters and secrets', () => {
    expect(validateQuickCommand('')).not.toBeNull()
    expect(validateQuickCommand('sudo ls')).not.toBeNull()
    expect(validateQuickCommand('rm -rf /')).not.toBeNull()
    expect(validateQuickCommand('docker compose ps && whoami')).not.toBeNull()
    expect(validateQuickCommand('ls; uname -a')).not.toBeNull()
    expect(validateQuickCommand('cat $(pwd)/.env')).not.toBeNull()
    expect(validateQuickCommand('cat `which ls`')).not.toBeNull()
    expect(validateQuickCommand('cat .env')).not.toBeNull()
    expect(validateQuickCommand('cat ../secret.txt')).not.toBeNull()
    expect(validateQuickCommand('cat config/ssh_key/id_rsa')).not.toBeNull()
    expect(validateQuickCommand('cat config/ssh_key/sentinel_control_panel')).not.toBeNull()
    expect(validateQuickCommand('cat server.pem')).not.toBeNull()
    expect(validateQuickCommand('python3 -c "print(1)"')).not.toBeNull()
    expect(validateQuickCommand('curl https://evil.example')).not.toBeNull()
    expect(validateQuickCommand('ls > /tmp/out')).not.toBeNull()
    expect(validateQuickCommand('ls\nwhoami')).not.toBeNull()
    expect(validateQuickCommand('ls |')).not.toBeNull()
    expect(validateQuickCommand('ls "unterminated')).not.toBeNull()
  })

  it('executes validated command inside project vps_path via SSH', async () => {
    const mockSsh: SshExecutor = {
      execute: vi.fn(async () => ({ exitCode: 0, stdout: 'up 12 days\n', stderr: '' })),
    }

    const res = await executeQuickCommand(
      { slug: 'sentinel', vpsPath: '/srv/apps/sentinel' },
      'uptime',
      mockSsh,
      '/srv/apps',
    )

    expect(res.success).toBe(true)
    expect(res.stdout).toBe('up 12 days\n')
    expect(mockSsh.execute).toHaveBeenCalledWith(
      "export GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=safe.directory GIT_CONFIG_VALUE_0='*' && cd '/srv/apps/sentinel' && uptime",
      expect.objectContaining({ timeoutSeconds: 10 }),
    )

    const blocked = await executeQuickCommand(
      { slug: 'sentinel', vpsPath: '/srv/apps/sentinel' },
      'cat .env',
      mockSsh,
      '/srv/apps',
    )
    expect(blocked.success).toBe(false)
    expect(mockSsh.execute).toHaveBeenCalledTimes(1)
  })
})
