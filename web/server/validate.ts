import type { CardRecord, FolderRecord, Progress, ReviewLogRecord, SyncRequest } from '../shared/protocol.ts'
import { InvalidRequestError } from './store.ts'

// Checks and normalizes JSON from the network, so the store can trust its input.

/** How far ahead of the Mac's clock an edit's time may be. Newest edit wins, so a time far in the
 *  future (a phone with a wrong clock, or a forged request) would otherwise win every later edit. */
export const MAX_CLOCK_AHEAD = 24 * 3_600_000

export function parseSyncRequest(body: unknown, now = Date.now()): SyncRequest {
  const value = object(body, 'request')
  const editTime = (input: unknown, label: string) => Math.min(time(input, label), now + MAX_CLOCK_AHEAD)
  return {
    cursor: integer(value.cursor, 'cursor'),
    folders: array(value.folders, 'folders').map((folder) => parseFolder(folder, editTime)),
    cards: array(value.cards, 'cards').map((card) => parseCard(card, editTime)),
    reviewLogs: array(value.reviewLogs, 'reviewLogs').map(parseReviewLog),
  }
}

type EditTime = (input: unknown, label: string) => number

function parseFolder(input: unknown, editTime: EditTime): FolderRecord {
  const value = object(input, 'folder')
  return {
    id: id(value.id),
    name: string(value.name, 'folder.name'),
    parentId: value.parentId === null || value.parentId === undefined ? null : id(value.parentId),
    createdAt: time(value.createdAt, 'folder.createdAt'),
    updatedAt: editTime(value.updatedAt, 'folder.updatedAt'),
    deleted: value.deleted === true,
  }
}

function parseCard(input: unknown, editTime: EditTime): CardRecord {
  const value = object(input, 'card')
  return {
    id: id(value.id),
    folderId: value.folderId === null || value.folderId === undefined ? null : id(value.folderId),
    front: string(value.front, 'card.front'),
    back: string(value.back, 'card.back'),
    createdAt: time(value.createdAt, 'card.createdAt'),
    updatedAt: editTime(value.updatedAt, 'card.updatedAt'),
    deleted: value.deleted === true,
    progress: value.progress === null || value.progress === undefined ? null : parseProgress(value.progress, editTime),
  }
}

function parseProgress(input: unknown, editTime: EditTime): Progress {
  const value = object(input, 'progress')
  return {
    state: integer(value.state, 'progress.state'),
    due: time(value.due, 'progress.due'),
    stability: number(value.stability, 'progress.stability'),
    difficulty: number(value.difficulty, 'progress.difficulty'),
    step: integer(value.step, 'progress.step'),
    reps: integer(value.reps, 'progress.reps'),
    lapses: integer(value.lapses, 'progress.lapses'),
    lastReview: value.lastReview === null || value.lastReview === undefined ? null : time(value.lastReview, 'progress.lastReview'),
    updatedAt: editTime(value.updatedAt, 'progress.updatedAt'),
  }
}

function parseReviewLog(input: unknown): ReviewLogRecord {
  const value = object(input, 'reviewLog')
  return {
    id: id(value.id),
    cardId: id(value.cardId),
    reviewedAt: time(value.reviewedAt, 'reviewLog.reviewedAt'),
    rating: integer(value.rating, 'reviewLog.rating'),
    stateBefore: integer(value.stateBefore, 'reviewLog.stateBefore'),
  }
}

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/

/** IDs are compared as lowercase strings; Swift sends uppercase UUIDs. */
function id(value: unknown): string {
  const text = typeof value === 'string' ? value.toLowerCase() : ''
  if (!UUID.test(text)) throw new InvalidRequestError(`Invalid id: ${String(value)}`)
  return text
}

function object(value: unknown, label: string): Record<string, unknown> {
  if (typeof value !== 'object' || value === null || Array.isArray(value)) {
    throw new InvalidRequestError(`Expected an object for ${label}.`)
  }
  return value as Record<string, unknown>
}

function array(value: unknown, label: string): unknown[] {
  if (value === undefined) return []
  if (!Array.isArray(value)) throw new InvalidRequestError(`Expected a list for ${label}.`)
  return value
}

function string(value: unknown, label: string): string {
  if (typeof value !== 'string') throw new InvalidRequestError(`Expected text for ${label}.`)
  return value
}

function number(value: unknown, label: string): number {
  if (typeof value !== 'number' || !Number.isFinite(value)) throw new InvalidRequestError(`Expected a number for ${label}.`)
  return value
}

function integer(value: unknown, label: string): number {
  return Math.round(number(value, label))
}

/** Milliseconds since 1970; the phone may send fractions. */
function time(value: unknown, label: string): number {
  return Math.round(number(value, label))
}
