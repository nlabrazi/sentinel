import { createHmac } from 'node:crypto'
import { describe, expect, it, vi } from 'vitest'
import { shellEscape, verifyKnownHostKey, wrapBashCommand } from '#server/services/ssh'
import {
  buildVpsDiscoveryCommand,
  humanizeSlug,
  parseDiscoveryOutput,
} from '#server/services/vps-discovery'

function buildFakeSshKeyBuffer(type = 'ssh-ed25519', payload = 'sentinel-test-key'): Buffer {
  const typeBuf = Buffer.from(type, 'utf8')
  const lenBuf = Buffer.alloc(4)
  lenBuf.writeUInt32BE(typeBuf.length, 0)
  return Buffer.concat([lenBuf, typeBuf, Buffer.from(payload, 'utf8')])
}

describe('ssh helpers & known_hosts verification', () => {
  it('safely escapes POSIX shell arguments', () => {
    expect(shellEscape("/srv/apps/it's-here")).toBe("'/srv/apps/it'\\''s-here'")
    expect(wrapBashCommand('echo ok')).toBe("bash -lc 'echo ok'")
  })

  it('verifies plain and hashed OpenSSH known_hosts entries', () => {
    const keyBuf = buildFakeSshKeyBuffer()
    const keyB64 = keyBuf.toString('base64')
    const wrongKeyBuf = buildFakeSshKeyBuffer('ssh-ed25519', 'different-key')

    const plainKnownHosts = `vps.nabster.dev ssh-ed25519 ${keyB64}\n`
    expect(
      verifyKnownHostKey({
        host: 'vps.nabster.dev',
        keyBuffer: keyBuf,
        mode: 'always',
        knownHostsContent: plainKnownHosts,
      }),
    ).toBe(true)

    expect(
      verifyKnownHostKey({
        host: 'vps.nabster.dev',
        keyBuffer: wrongKeyBuf,
        mode: 'always',
        knownHostsContent: plainKnownHosts,
      }),
    ).toBe(false)

    // Hashed OpenSSH known_hosts format |1|<salt>|<hmac-sha1>
    const salt = Buffer.from('1234567890abcdef1234', 'utf8')
    const hash = createHmac('sha1', salt).update('203.0.113.10').digest('base64')
    const hashedKnownHosts = `|1|${salt.toString('base64')}|${hash} ssh-ed25519 ${keyB64}\n`
    expect(
      verifyKnownHostKey({
        host: '203.0.113.10',
        keyBuffer: keyBuf,
        mode: 'always',
        knownHostsContent: hashedKnownHosts,
      }),
    ).toBe(true)

    // accept_new records unknown host, rejects changed host
    const onAcceptNew = vi.fn()
    expect(
      verifyKnownHostKey({
        host: 'new.nabster.dev',
        keyBuffer: keyBuf,
        mode: 'accept_new',
        knownHostsContent: plainKnownHosts,
        onAcceptNew,
      }),
    ).toBe(true)
    expect(onAcceptNew).toHaveBeenCalledWith(`new.nabster.dev ssh-ed25519 ${keyB64}\n`)

    expect(
      verifyKnownHostKey({
        host: 'vps.nabster.dev',
        keyBuffer: wrongKeyBuf,
        mode: 'accept_new',
        knownHostsContent: plainKnownHosts,
      }),
    ).toBe(false)

    // never bypasses check
    expect(
      verifyKnownHostKey({
        host: 'unknown.host',
        keyBuffer: wrongKeyBuf,
        mode: 'never',
        knownHostsContent: null,
      }),
    ).toBe(true)
  })
})

describe('vps discovery parser', () => {
  it('humanizes project slugs and builds safe discovery command', () => {
    expect(humanizeSlug('lazarus-exchange')).toBe('Lazarus Exchange')
    expect(humanizeSlug('sawt_ai')).toBe('Sawt Ai')
    const cmd = buildVpsDiscoveryCommand('/srv/apps')
    expect(cmd).toMatch(/^bash -lc '/)
    expect(cmd).toContain('/srv/apps')
    expect(cmd).toContain('safe.directory="*"')
    expect(cmd).toContain('$dir/repo/.git')
  })

  it('parses git metadata, SSH remotes, scripts, maintenance flag and sentinel.json', () => {
    const manifest = Buffer.from(
      JSON.stringify({
        name: 'Portfolio 3D',
        kind: 'app',
        production_url: 'https://nabster.dev',
        grafana_app_value: 'https://nabster.dev',
        cron_monitoring: true,
      }),
    ).toString('base64')

    const stdout = [
      `portfolio\t/srv/apps/portfolio\tgit@github-portfolio:nlabrazi/portfolio-3d.git\tmaster\t1234567890abcdef1234567890abcdef12345678\t1\t1\t0\t${manifest}`,
      'sjvtdm\t/srv/apps/sjvtdm\thttps://github.com/nlabrazi/sjvtdm.git\tmain\tabcdef1234567\t0\t1\t1\t',
      'umami\t/srv/apps/umami\t\t\t\t0\t1\t0\t',
      'evil\t/etc/passwd\t\t\t\t0\t0\t0\t',
      'broken-manifest\t/srv/apps/broken-manifest\t\t\t\t1\t0\t0\tnot-valid-base64!!!',
    ].join('\n')

    const { projects, warnings } = parseDiscoveryOutput(stdout, '/srv/apps')

    expect(projects).toHaveLength(4)
    expect(warnings).toHaveLength(2)

    expect(projects[0]).toMatchObject({
      slug: 'portfolio',
      name: 'Portfolio 3D',
      kind: 'app',
      vpsPath: '/srv/apps/portfolio',
      repoUrl: 'https://github.com/nlabrazi/portfolio-3d.git',
      productionBranch: 'master',
      productionUrl: 'https://nabster.dev',
      grafanaAppValue: 'https://nabster.dev',
      hasDeployScript: true,
      hasStatusScript: true,
      cronMonitoringEnabled: true,
      maintenanceMode: false,
      lastCommitDeployed: '1234567890abcdef1234567890abcdef12345678',
    })

    expect(projects[1]).toMatchObject({
      slug: 'sjvtdm',
      name: 'Sjvtdm',
      kind: 'cron',
      productionBranch: 'main',
      hasDeployScript: false,
      hasStatusScript: true,
      cronMonitoringEnabled: true,
      maintenanceMode: true,
    })

    expect(projects[2]).toMatchObject({
      slug: 'umami',
      kind: 'service',
      repoUrl: null,
      hasStatusScript: true,
    })

    expect(projects[3]).toMatchObject({
      slug: 'broken-manifest',
      name: 'Broken Manifest',
      kind: 'app',
      hasDeployScript: true,
    })
  })
})
