// Records exchanged between the Mac server, the web UI, and the iPhone app.
// The iPhone mirrors these in StudyUp/Sync/SyncProtocol.swift — keep both in sync.
//
// IDs are lowercase UUID strings. Times are milliseconds since 1970.

export interface FolderRecord {
  id: string
  name: string
  parentId: string | null
  createdAt: number
  /** Last content change: name, parent, or deletion. Newest wins when both sides edit. */
  updatedAt: number
  deleted: boolean
}

/** Spaced-repetition state. Only the iPhone writes it; the Mac keeps a copy. */
export interface Progress {
  /** 0 new, 1 learning, 2 review, 3 relearning */
  state: number
  due: number
  stability: number
  difficulty: number
  step: number
  reps: number
  lapses: number
  lastReview: number | null
  updatedAt: number
}

export interface CardRecord {
  id: string
  folderId: string | null
  front: string
  back: string
  createdAt: number
  /** Last content change: front, back, folder, or deletion. */
  updatedAt: number
  deleted: boolean
  /** Null until the card is first studied on the iPhone. */
  progress: Progress | null
}

export interface ReviewLogRecord {
  id: string
  cardId: string
  reviewedAt: number
  /** 1 Wrong, 3 Right, 4 Easy */
  rating: number
  stateBefore: number
}

/** iPhone → Mac: everything changed on the phone since its last sync. */
export interface SyncRequest {
  /** The cursor from the previous sync response; 0 on first sync. */
  cursor: number
  folders: FolderRecord[]
  cards: CardRecord[]
  reviewLogs: ReviewLogRecord[]
}

/** Mac → iPhone: everything changed on the Mac after `cursor` that the phone doesn't already have. */
export interface SyncResponse {
  /** Identifies the Mac's database. If it changes (a restored backup, a new Mac), the phone's
   *  cursor means nothing anymore, so the phone starts over with a full sync. */
  databaseId: string
  cursor: number
  folders: FolderRecord[]
  cards: CardRecord[]
  /** Only on a first sync (cursor 0), so a reinstalled app gets its history back. */
  reviewLogs: ReviewLogRecord[]
}

export interface PairRequest {
  code: string
  deviceName: string
}

export interface PairResponse {
  token: string
  serverName: string
}

/** Everything the web UI shows, in one request. */
export interface Library {
  folders: FolderRecord[]
  cards: CardRecord[]
}

export interface ServerStatus {
  serverName: string
  /** Changes whenever anything changes, so the UI knows when to refetch. */
  version: number
  devices: { name: string; createdAt: number; lastSyncAt: number | null }[]
  pairing: { code: string; expiresAt: number } | null
}
