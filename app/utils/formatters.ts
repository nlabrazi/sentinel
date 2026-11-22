export function shortSha(sha: string | null | undefined): string {
  if (!sha) {
    return '—'
  }
  return sha.slice(0, 7)
}

export function formatDuration(seconds: number | null | undefined): string {
  if (seconds === null || seconds === undefined || Number.isNaN(seconds)) {
    return '—'
  }
  if (seconds < 60) {
    return `${seconds}s`
  }
  const mins = Math.floor(seconds / 60)
  const secs = seconds % 60
  return secs > 0 ? `${mins}m ${secs}s` : `${mins}m`
}

export function formatRelativeTime(isoDate: string | null | undefined, now = new Date()): string {
  if (!isoDate) {
    return 'Jamais'
  }
  const parsed = new Date(isoDate)
  if (Number.isNaN(parsed.getTime())) {
    return 'Inconnu'
  }
  const diffSeconds = Math.floor((now.getTime() - parsed.getTime()) / 1000)
  if (diffSeconds < 60) {
    return "à l'instant"
  }
  const diffMinutes = Math.floor(diffSeconds / 60)
  if (diffMinutes < 60) {
    return `il y a ${diffMinutes} min`
  }
  const diffHours = Math.floor(diffMinutes / 60)
  if (diffHours < 24) {
    return `il y a ${diffHours} h`
  }
  const diffDays = Math.floor(diffHours / 24)
  return `il y a ${diffDays} j`
}
