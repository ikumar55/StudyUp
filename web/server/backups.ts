import { existsSync, mkdirSync, readdirSync, rmSync } from 'node:fs'
import { join } from 'node:path'
import type { DatabaseSync } from 'node:sqlite'

/** Daily snapshots kept, newest first. */
export const BACKUPS_KEPT = 14

const BACKUP_NAME = /^studyup-\d{4}-\d{2}-\d{2}\.db$/

/**
 * Saves a snapshot of the database for today, unless there already is one, and removes all but the
 * newest `BACKUPS_KEPT`. A snapshot is a complete, compacted SQLite file (VACUUM INTO), safe to take
 * while the server is running. Returns the new snapshot's path, if one was made.
 */
export function backUpDatabase(db: DatabaseSync, directory: string, now = new Date()): string | null {
  mkdirSync(directory, { recursive: true })
  const path = join(directory, `studyup-${localDate(now)}.db`)
  const created = existsSync(path) ? null : path
  if (created) db.prepare('VACUUM INTO ?').run(created)
  const snapshots = readdirSync(directory).filter((name) => BACKUP_NAME.test(name)).sort()
  for (const old of snapshots.slice(0, -BACKUPS_KEPT)) rmSync(join(directory, old))
  return created
}

function localDate(date: Date): string {
  const pad = (n: number) => String(n).padStart(2, '0')
  return `${date.getFullYear()}-${pad(date.getMonth() + 1)}-${pad(date.getDate())}`
}
