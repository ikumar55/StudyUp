// Small per-browser conveniences (selected folder, collapsed folders, unsent draft).
// Storage can be unavailable (private windows, blocked site data), so every access is guarded.

const prefix = 'studyup.'

export function loadValue<T>(key: string, fallback: T): T {
  try {
    const raw = localStorage.getItem(prefix + key)
    return raw === null ? fallback : (JSON.parse(raw) as T)
  } catch {
    return fallback
  }
}

export function saveValue(key: string, value: unknown): void {
  try {
    if (value === undefined) localStorage.removeItem(prefix + key)
    else localStorage.setItem(prefix + key, JSON.stringify(value))
  } catch {
    // Not persisting is fine.
  }
}
