import { mkdirSync } from 'node:fs'
import { homedir } from 'node:os'
import { dirname, join } from 'node:path'
import { DatabaseSync } from 'node:sqlite'

/** Images live next to the database, e.g. ~/Library/Application Support/StudyUp/images. */
export function defaultImagesDirectory(): string {
  return join(dirname(defaultDatabasePath()), 'images')
}

export function defaultDatabasePath(): string {
  return process.env.STUDYUP_DB ?? join(homedir(), 'Library', 'Application Support', 'StudyUp', 'studyup.db')
}

/** Every row carries `seq`, the value of a global change counter when it was last written,
 *  so a sync can ask for "everything after seq N". */
const SCHEMA = `
  CREATE TABLE IF NOT EXISTS meta (
    key TEXT PRIMARY KEY,
    value TEXT NOT NULL
  );
  CREATE TABLE IF NOT EXISTS folders (
    id TEXT PRIMARY KEY,
    name TEXT NOT NULL,
    parent_id TEXT,
    created_at INTEGER NOT NULL,
    updated_at INTEGER NOT NULL,
    deleted INTEGER NOT NULL DEFAULT 0,
    seq INTEGER NOT NULL
  );
  CREATE TABLE IF NOT EXISTS cards (
    id TEXT PRIMARY KEY,
    folder_id TEXT,
    front TEXT NOT NULL,
    back TEXT NOT NULL,
    created_at INTEGER NOT NULL,
    updated_at INTEGER NOT NULL,
    deleted INTEGER NOT NULL DEFAULT 0,
    progress TEXT,
    seq INTEGER NOT NULL
  );
  CREATE TABLE IF NOT EXISTS review_logs (
    id TEXT PRIMARY KEY,
    card_id TEXT NOT NULL,
    reviewed_at INTEGER NOT NULL,
    rating INTEGER NOT NULL,
    state_before INTEGER NOT NULL,
    seq INTEGER NOT NULL
  );
  CREATE TABLE IF NOT EXISTS devices (
    token_hash TEXT PRIMARY KEY,
    name TEXT NOT NULL,
    created_at INTEGER NOT NULL,
    last_sync_at INTEGER
  );
  CREATE INDEX IF NOT EXISTS folders_seq ON folders (seq);
  CREATE INDEX IF NOT EXISTS cards_seq ON cards (seq);
  CREATE INDEX IF NOT EXISTS review_logs_seq ON review_logs (seq);
`

export function openDatabase(path: string = defaultDatabasePath()): DatabaseSync {
  if (path !== ':memory:') mkdirSync(dirname(path), { recursive: true })
  const db = new DatabaseSync(path)
  if (path !== ':memory:') db.exec('PRAGMA journal_mode = WAL')
  db.exec(SCHEMA)
  return db
}
