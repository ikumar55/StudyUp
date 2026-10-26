import { createHash, randomBytes, randomInt, randomUUID } from 'node:crypto'
import type { DatabaseSync, SQLOutputValue } from 'node:sqlite'
import type {
  CardRecord,
  FolderRecord,
  Library,
  Progress,
  ReviewLogRecord,
  ServerStatus,
  SyncRequest,
  SyncResponse,
} from '../shared/protocol.ts'

type Row = Record<string, SQLOutputValue>

export class NotFoundError extends Error {}
export class InvalidRequestError extends Error {}

const PAIRING_CODE_LIFETIME = 10 * 60_000
const MAX_PAIRING_ATTEMPTS = 5

/** All reads and writes of the Mac's copy of the library, including the sync merge rules. */
export class Store {
  readonly serverName: string
  #db: DatabaseSync
  #pairing: { code: string; expiresAt: number; attempts: number } | null = null

  constructor(db: DatabaseSync, serverName = 'StudyUp') {
    this.#db = db
    this.serverName = serverName
    if (!this.#meta('database_id')) this.#setMeta('database_id', randomUUID())
  }

  /** Identifies this database to the phone; see `SyncResponse.databaseId`. */
  get databaseId(): string {
    return this.#meta('database_id')!
  }

  /** Folds the write-ahead log into the main database file, so `studyup.db` alone holds everything. */
  checkpoint(): void {
    this.#db.exec('PRAGMA wal_checkpoint(TRUNCATE)')
  }

  // MARK: - Reading

  library(): Library {
    return {
      folders: this.#folders('WHERE deleted = 0 ORDER BY name COLLATE NOCASE'),
      cards: this.#cards('WHERE deleted = 0 ORDER BY created_at'),
    }
  }

  folder(id: string): FolderRecord | undefined {
    return this.#folders('WHERE id = ?', id)[0]
  }

  card(id: string): CardRecord | undefined {
    return this.#cards('WHERE id = ?', id)[0]
  }

  /** Every record, including review history, for a downloadable backup. */
  backup(): Library & { reviewLogs: ReviewLogRecord[]; exportedAt: number } {
    return { ...this.library(), reviewLogs: this.#reviewLogs('ORDER BY reviewed_at'), exportedAt: Date.now() }
  }

  status(now = Date.now()): ServerStatus {
    const pairing = this.#pairing && now <= this.#pairing.expiresAt
      ? { code: this.#pairing.code, expiresAt: this.#pairing.expiresAt }
      : null
    const devices = this.#db.prepare('SELECT name, created_at, last_sync_at FROM devices ORDER BY created_at').all()
      .map((row) => ({
        name: String(row.name),
        createdAt: Number(row.created_at),
        lastSyncAt: row.last_sync_at === null ? null : Number(row.last_sync_at),
      }))
    return { serverName: this.serverName, version: this.#currentSeq(), devices, pairing }
  }

  // MARK: - Editing from the web UI

  createFolder(name: string, parentId: string | null, now = Date.now()): FolderRecord {
    const trimmed = requireText(name, 'Folder name')
    if (parentId !== null) this.#requireFolder(parentId)
    const record: FolderRecord = { id: randomUUID(), name: trimmed, parentId, createdAt: now, updatedAt: now, deleted: false }
    return this.#transaction(() => this.#writeFolder(record))
  }

  updateFolder(id: string, changes: { name?: string; parentId?: string | null }, now = Date.now()): FolderRecord {
    return this.#transaction(() => {
      const folder = this.#requireFolder(id)
      const next = { ...folder, updatedAt: now }
      if (changes.name !== undefined) next.name = requireText(changes.name, 'Folder name')
      if (changes.parentId !== undefined) {
        if (changes.parentId !== null) {
          this.#requireFolder(changes.parentId)
          if (this.#isSelfOrDescendant(changes.parentId, id)) {
            throw new InvalidRequestError('A folder can’t be moved inside itself.')
          }
        }
        next.parentId = changes.parentId
      }
      return this.#writeFolder(next)
    })
  }

  /** Deletes a folder with everything inside it. */
  deleteFolder(id: string, now = Date.now()): void {
    this.#transaction(() => {
      const folder = this.#requireFolder(id)
      this.#writeFolder({ ...folder, deleted: true, updatedAt: now })
      // An explicit delete here removes everything inside, however recently it was edited.
      this.#cascadeDelete(id, now, { sparingNewerEdits: false })
    })
  }

  createCards(folderId: string, cards: { front: string; back: string }[], now = Date.now()): CardRecord[] {
    this.#requireFolder(folderId)
    if (cards.length === 0) throw new InvalidRequestError('No cards to add.')
    return this.#transaction(() => cards.map((card, index) => this.#writeCard({
      id: randomUUID(),
      folderId,
      front: requireText(card.front, 'Question'),
      back: requireText(card.back, 'Answer'),
      // Keep the given order when sorting by creation time.
      createdAt: now + index,
      updatedAt: now,
      deleted: false,
      progress: null,
    })))
  }

  updateCard(id: string, changes: { front?: string; back?: string; folderId?: string }, now = Date.now()): CardRecord {
    return this.#transaction(() => {
      const card = this.#requireCard(id)
      const next = { ...card, updatedAt: now }
      if (changes.front !== undefined) next.front = requireText(changes.front, 'Question')
      if (changes.back !== undefined) next.back = requireText(changes.back, 'Answer')
      if (changes.folderId !== undefined) {
        this.#requireFolder(changes.folderId)
        next.folderId = changes.folderId
      }
      return this.#writeCard(next)
    })
  }

  /** "Review today" makes a studied card due now, keeping its history; "reset" starts it over as new.
   *  Progress is normally written by the phone, but the newer `progress.updatedAt` wins on both sides,
   *  so these edits reach the phone on its next sync. */
  changeProgress(id: string, action: 'review-today' | 'reset', now = Date.now()): CardRecord {
    return this.#transaction(() => {
      const card = this.#requireCard(id)
      if (!card.progress || card.progress.state === 0) {
        throw new InvalidRequestError('This card hasn’t been studied yet, so it’s already in your new cards.')
      }
      const progress = action === 'reset'
        ? { state: 0, due: now, stability: 0, difficulty: 0, step: 0, reps: 0, lapses: 0, lastReview: null, updatedAt: now }
        : { ...card.progress, due: now, updatedAt: now }
      return this.#writeCard({ ...card, progress })
    })
  }

  deleteCard(id: string, now = Date.now()): void {
    this.#transaction(() => {
      const card = this.#requireCard(id)
      this.#writeCard({ ...card, deleted: true, updatedAt: now })
    })
  }

  // MARK: - Sync

  /** Merges the phone's changes, then returns what the phone is missing.
   *  Content: newest `updatedAt` wins per record. Progress: newest `progress.updatedAt` wins
   *  (in practice only the phone writes it). Review logs are append-only. */
  sync(request: SyncRequest): SyncResponse {
    return this.#transaction(() => {
      // The phone has seen changes this database never had, so it was replaced (e.g. by an older
      // copy). A new id tells the phone its cursor is meaningless and it should send everything.
      if (request.cursor > this.#currentSeq()) this.#setMeta('database_id', randomUUID())

      // Records now identical to what the phone sent don't need to go back to it.
      const echoed = new Set<string>()
      // Records where the Mac's copy beat the phone's go back even if the phone saw them before
      // (e.g. its clock is behind), or it would keep its losing version.
      const sendBack = { folders: new Set<string>(), cards: new Set<string>() }

      for (const incoming of request.folders) {
        const existing = this.#folders('WHERE id = ?', incoming.id)[0]
        if (existing && incoming.updatedAt <= existing.updatedAt) {
          if (differs(existing, incoming, ['name', 'parentId', 'deleted'])) sendBack.folders.add(existing.id)
          continue
        }
        // A delete from the phone carries no name; keep the Mac's, so the record stays readable.
        this.#writeFolder(incoming.deleted && existing ? { ...existing, deleted: true, updatedAt: incoming.updatedAt } : incoming)
        echoed.add(incoming.id)
        if (incoming.deleted) this.#cascadeDelete(incoming.id, incoming.updatedAt, { sparingNewerEdits: true })
      }

      for (const incoming of request.cards) {
        const existing = this.#cards('WHERE id = ?', incoming.id)[0]
        const contentWins = !existing || incoming.updatedAt > existing.updatedAt
        const progressWins = incoming.progress !== null
          && (!existing?.progress || incoming.progress.updatedAt > existing.progress.updatedAt)
        if (!contentWins && !progressWins) {
          if (differs(existing!, incoming, ['front', 'back', 'folderId', 'deleted'])
            || JSON.stringify(existing!.progress) !== JSON.stringify(incoming.progress ?? existing!.progress)) {
            sendBack.cards.add(existing!.id)
          }
          continue
        }
        // A delete from the phone carries no text; keep the Mac's, so a mistaken delete can be recovered.
        const deletion = contentWins && incoming.deleted && existing
          ? { ...existing, deleted: true, updatedAt: incoming.updatedAt }
          : undefined
        const base = deletion ?? (contentWins ? incoming : existing!)
        const merged: CardRecord = { ...base, progress: progressWins ? incoming.progress : existing?.progress ?? null }
        this.#writeCard(merged)
        if (deletion || JSON.stringify(merged) === JSON.stringify(incoming)) echoed.add(incoming.id)
      }

      const insertLog = this.#db.prepare(`
        INSERT OR IGNORE INTO review_logs (id, card_id, reviewed_at, rating, state_before, seq)
        VALUES (?, ?, ?, ?, ?, ?)`)
      for (const log of request.reviewLogs) {
        insertLog.run(log.id, log.cardId, log.reviewedAt, log.rating, log.stateBefore, this.#nextSeq())
      }

      const folders = this.#folders('WHERE seq > ? ORDER BY seq', request.cursor).filter((f) => !echoed.has(f.id))
      const cards = this.#cards('WHERE seq > ? ORDER BY seq', request.cursor).filter((c) => !echoed.has(c.id))
      for (const id of sendBack.folders) if (!folders.some((f) => f.id === id)) folders.push(this.folder(id)!)
      for (const id of sendBack.cards) if (!cards.some((c) => c.id === id)) cards.push(this.card(id)!)
      return {
        databaseId: this.databaseId,
        cursor: this.#currentSeq(),
        folders,
        cards,
        reviewLogs: request.cursor === 0 ? this.#reviewLogs('ORDER BY reviewed_at') : [],
      }
    })
  }

  // MARK: - Pairing

  /** A 6-digit code, shown in the web UI and typed on the phone. */
  createPairingCode(now = Date.now()): { code: string; expiresAt: number } {
    const code = String(randomInt(0, 1_000_000)).padStart(6, '0')
    this.#pairing = { code, expiresAt: now + PAIRING_CODE_LIFETIME, attempts: 0 }
    return { code, expiresAt: this.#pairing.expiresAt }
  }

  /** Exchanges a valid code for a long-lived token. Returns null for a wrong or expired code. */
  pair(code: string, deviceName: string, now = Date.now()): string | null {
    const pairing = this.#pairing
    if (!pairing || now > pairing.expiresAt) return null
    if (code.trim() !== pairing.code) {
      // Too many wrong guesses burns the code, so it can't be brute-forced from the network.
      pairing.attempts += 1
      if (pairing.attempts >= MAX_PAIRING_ATTEMPTS) this.#pairing = null
      return null
    }
    this.#pairing = null
    const token = randomBytes(32).toString('base64url')
    this.#db.prepare('INSERT INTO devices (token_hash, name, created_at) VALUES (?, ?, ?)')
      .run(hashToken(token), deviceName.trim() || 'iPhone', now)
    return token
  }

  /** Marks the device as synced and returns true if the token belongs to a paired device. */
  authenticate(token: string, now = Date.now()): boolean {
    const result = this.#db.prepare('UPDATE devices SET last_sync_at = ? WHERE token_hash = ?').run(now, hashToken(token))
    return result.changes > 0
  }

  forgetDevices(): void {
    this.#db.exec('DELETE FROM devices')
  }

  // MARK: - Private

  #transaction<T>(body: () => T): T {
    this.#db.exec('BEGIN IMMEDIATE')
    try {
      const result = body()
      this.#db.exec('COMMIT')
      return result
    } catch (error) {
      this.#db.exec('ROLLBACK')
      throw error
    }
  }

  #meta(key: string): string | undefined {
    const row = this.#db.prepare('SELECT value FROM meta WHERE key = ?').get(key)
    return row ? String(row.value) : undefined
  }

  #setMeta(key: string, value: string): void {
    this.#db.prepare('INSERT INTO meta (key, value) VALUES (?, ?) ON CONFLICT (key) DO UPDATE SET value = excluded.value')
      .run(key, value)
  }

  #currentSeq(): number {
    return Number(this.#meta('seq') ?? 0)
  }

  #nextSeq(): number {
    const next = this.#currentSeq() + 1
    this.#setMeta('seq', String(next))
    return next
  }

  #folders(clause: string, ...params: (string | number)[]): FolderRecord[] {
    return this.#db.prepare(`SELECT * FROM folders ${clause}`).all(...params).map(folderFromRow)
  }

  #cards(clause: string, ...params: (string | number)[]): CardRecord[] {
    return this.#db.prepare(`SELECT * FROM cards ${clause}`).all(...params).map(cardFromRow)
  }

  #reviewLogs(clause: string): ReviewLogRecord[] {
    return this.#db.prepare(`SELECT * FROM review_logs ${clause}`).all().map((row) => ({
      id: String(row.id),
      cardId: String(row.card_id),
      reviewedAt: Number(row.reviewed_at),
      rating: Number(row.rating),
      stateBefore: Number(row.state_before),
    }))
  }

  #requireFolder(id: string): FolderRecord {
    const folder = this.folder(id)
    if (!folder || folder.deleted) throw new NotFoundError('That folder no longer exists.')
    return folder
  }

  #requireCard(id: string): CardRecord {
    const card = this.card(id)
    if (!card || card.deleted) throw new NotFoundError('That card no longer exists.')
    return card
  }

  #isSelfOrDescendant(candidateId: string, ancestorId: string): boolean {
    for (let current = this.folder(candidateId); current; current = current.parentId ? this.folder(current.parentId) : undefined) {
      if (current.id === ancestorId) return true
    }
    return false
  }

  /** Marks everything inside a deleted folder as deleted too. For a delete synced from the phone,
   *  anything edited on the Mac after the delete is spared, since that edit is newer. */
  #cascadeDelete(folderId: string, at: number, options: { sparingNewerEdits: boolean }): void {
    const cutoff = options.sparingNewerEdits ? at : Number.MAX_SAFE_INTEGER
    for (const card of this.#cards('WHERE folder_id = ? AND deleted = 0 AND updated_at <= ?', folderId, cutoff)) {
      this.#writeCard({ ...card, deleted: true, updatedAt: Math.max(at, card.updatedAt) })
    }
    for (const child of this.#folders('WHERE parent_id = ? AND deleted = 0 AND updated_at <= ?', folderId, cutoff)) {
      this.#writeFolder({ ...child, deleted: true, updatedAt: Math.max(at, child.updatedAt) })
      this.#cascadeDelete(child.id, at, options)
    }
  }

  #writeFolder(folder: FolderRecord): FolderRecord {
    this.#db.prepare(`
      INSERT INTO folders (id, name, parent_id, created_at, updated_at, deleted, seq)
      VALUES (?, ?, ?, ?, ?, ?, ?)
      ON CONFLICT (id) DO UPDATE SET
        name = excluded.name, parent_id = excluded.parent_id, created_at = excluded.created_at,
        updated_at = excluded.updated_at, deleted = excluded.deleted, seq = excluded.seq`)
      .run(folder.id, folder.name, folder.parentId, folder.createdAt, folder.updatedAt, folder.deleted ? 1 : 0, this.#nextSeq())
    return folder
  }

  #writeCard(card: CardRecord): CardRecord {
    this.#db.prepare(`
      INSERT INTO cards (id, folder_id, front, back, created_at, updated_at, deleted, progress, seq)
      VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
      ON CONFLICT (id) DO UPDATE SET
        folder_id = excluded.folder_id, front = excluded.front, back = excluded.back,
        created_at = excluded.created_at, updated_at = excluded.updated_at, deleted = excluded.deleted,
        progress = excluded.progress, seq = excluded.seq`)
      .run(
        card.id, card.folderId, card.front, card.back, card.createdAt, card.updatedAt,
        card.deleted ? 1 : 0, card.progress ? JSON.stringify(card.progress) : null, this.#nextSeq(),
      )
    return card
  }
}

function folderFromRow(row: Row): FolderRecord {
  return {
    id: String(row.id),
    name: String(row.name),
    parentId: row.parent_id === null ? null : String(row.parent_id),
    createdAt: Number(row.created_at),
    updatedAt: Number(row.updated_at),
    deleted: row.deleted === 1,
  }
}

function cardFromRow(row: Row): CardRecord {
  return {
    id: String(row.id),
    folderId: row.folder_id === null ? null : String(row.folder_id),
    front: String(row.front),
    back: String(row.back),
    createdAt: Number(row.created_at),
    updatedAt: Number(row.updated_at),
    deleted: row.deleted === 1,
    progress: row.progress === null ? null : JSON.parse(String(row.progress)) as Progress,
  }
}

/** Whether two versions of a record differ in the given fields. Two deleted versions don't differ:
 *  the phone has nothing to update. */
function differs<T extends { deleted: boolean }>(a: T, b: T, fields: (keyof T)[]): boolean {
  if (a.deleted && b.deleted) return false
  return fields.some((field) => a[field] !== b[field])
}

function requireText(value: string, label: string): string {
  const trimmed = value.trim()
  if (!trimmed) throw new InvalidRequestError(`${label} can’t be empty.`)
  return trimmed
}

function hashToken(token: string): string {
  return createHash('sha256').update(token).digest('hex')
}
