import assert from 'node:assert/strict'
import { randomUUID } from 'node:crypto'
import { existsSync, mkdtempSync, readdirSync, statSync, utimesSync, writeFileSync } from 'node:fs'
import { tmpdir } from 'node:os'
import { join } from 'node:path'
import { beforeEach, describe, test } from 'node:test'
import { DatabaseSync } from 'node:sqlite'
import type { CardRecord, FolderRecord, Progress, SyncRequest, SyncResponse } from '../../shared/protocol.ts'
import { createApp } from '../app.ts'
import { BACKUPS_KEPT, backUpDatabase } from '../backups.ts'
import { openDatabase } from '../db.ts'
import { ImageStore } from '../images.ts'
import { Store } from '../store.ts'
import { MAX_CLOCK_AHEAD } from '../validate.ts'

let store: Store
let local = true
let app: ReturnType<typeof createApp>

beforeEach(() => {
  store = new Store(openDatabase(':memory:'), 'Test Mac')
  local = true
  app = createApp(store, new ImageStore(mkdtempSync(join(tmpdir(), 'studyup-images-'))), { isLocalRequest: () => local })
})

async function call(method: string, path: string, body?: unknown, token?: string) {
  const headers: Record<string, string> = { 'Content-Type': 'application/json' }
  if (token) headers.Authorization = `Bearer ${token}`
  const response = await app.request(path, { method, headers, body: body === undefined ? undefined : JSON.stringify(body) })
  const text = await response.text()
  return { status: response.status, body: text ? JSON.parse(text) : null }
}

async function pairedToken(): Promise<string> {
  const { code } = store.createPairingCode()
  local = false
  const { body } = await call('POST', '/pair', { code, deviceName: 'Test iPhone' })
  return body.token
}

async function sync(token: string, request: Partial<SyncRequest>): Promise<SyncResponse> {
  const { status, body } = await call('POST', '/sync', { cursor: 0, folders: [], cards: [], reviewLogs: [], ...request }, token)
  assert.equal(status, 200, JSON.stringify(body))
  return body
}

function folder(overrides: Partial<FolderRecord> = {}): FolderRecord {
  return { id: randomUUID(), name: 'OS', parentId: null, createdAt: 1000, updatedAt: 1000, deleted: false, ...overrides }
}

function card(folderId: string, overrides: Partial<CardRecord> = {}): CardRecord {
  return {
    id: randomUUID(), folderId, front: 'Q', back: 'A', createdAt: 1000, updatedAt: 1000,
    deleted: false, progress: null, ...overrides,
  }
}

function progress(overrides: Partial<Progress> = {}): Progress {
  return {
    state: 2, due: 5000, stability: 3.2, difficulty: 5.1, step: 0, reps: 2, lapses: 0,
    lastReview: 2000, updatedAt: 2000, ...overrides,
  }
}

describe('web UI API', () => {
  test('creates folders and cards and lists them', async () => {
    const created = await call('POST', '/api/folders', { name: '  OS Fundamentals ' })
    assert.equal(created.status, 201)
    assert.equal(created.body.name, 'OS Fundamentals')

    const bulk = await call('POST', '/api/cards', {
      folderId: created.body.id,
      cards: [{ front: 'Q1', back: 'A1' }, { front: 'Q2', back: 'A2' }],
    })
    assert.equal(bulk.body.length, 2)

    const { body } = await call('GET', '/api/library')
    assert.equal(body.folders.length, 1)
    assert.deepEqual(body.cards.map((c: CardRecord) => c.front), ['Q1', 'Q2'])
  })

  test('rejects empty text and unknown folders', async () => {
    assert.equal((await call('POST', '/api/folders', { name: '   ' })).status, 400)
    assert.equal((await call('POST', '/api/cards', { folderId: randomUUID(), front: 'Q', back: 'A' })).status, 404)
  })

  test('refuses to move a folder inside itself', async () => {
    const parent = store.createFolder('Parent', null)
    const child = store.createFolder('Child', parent.id)
    const { status } = await call('PATCH', `/api/folders/${parent.id}`, { parentId: child.id })
    assert.equal(status, 400)
  })

  test('deleting a folder deletes everything inside it', async () => {
    const parent = store.createFolder('Parent', null)
    const child = store.createFolder('Child', parent.id)
    store.createCards(child.id, [{ front: 'Q', back: 'A' }])
    await call('DELETE', `/api/folders/${parent.id}`)
    const { body } = await call('GET', '/api/library')
    assert.equal(body.folders.length, 0)
    assert.equal(body.cards.length, 0)
  })

  test('deleting a folder in the editor removes even cards newer than the delete', () => {
    // E.g. a bulk import moments before the delete, or a phone whose clock runs ahead.
    const folder = store.createFolder('Imported', null, 1000)
    store.createCards(folder.id, [{ front: 'Q1', back: 'A1' }, { front: 'Q2', back: 'A2' }], 5000)
    store.deleteFolder(folder.id, 2000)
    assert.equal(store.library().cards.length, 0)
  })

  test('review today and reset change a studied card’s progress, newest first', async () => {
    const token = await pairedToken()
    const os = folder()
    const studied = card(os.id, { progress: progress({ due: 9_000_000_000_000, reps: 5, updatedAt: 2000 }) })
    const { cursor } = await sync(token, { folders: [os], cards: [studied] })
    local = true

    const due = await call('POST', `/api/cards/${studied.id}/progress`, { action: 'review-today' })
    assert.equal(due.status, 200)
    assert.ok(due.body.progress.due <= Date.now())
    assert.equal(due.body.progress.reps, 5)

    const reset = await call('POST', `/api/cards/${studied.id}/progress`, { action: 'reset' })
    assert.equal(reset.body.progress.state, 0)
    assert.equal(reset.body.progress.reps, 0)

    // The phone gets the reset on its next sync.
    local = false
    const response = await sync(token, { cursor })
    assert.equal(response.cards.find((c) => c.id === studied.id)?.progress?.state, 0)
  })

  test('progress actions need a studied card and a known action', async () => {
    const created = store.createFolder('OS', null)
    const [fresh] = store.createCards(created.id, [{ front: 'Q', back: 'A' }])
    assert.equal((await call('POST', `/api/cards/${fresh.id}/progress`, { action: 'reset' })).status, 400)
    assert.equal((await call('POST', `/api/cards/${fresh.id}/progress`, { action: 'explode' })).status, 400)
  })

  test('is only available on this Mac', async () => {
    local = false
    assert.equal((await call('GET', '/api/library')).status, 403)
    assert.equal((await call('GET', '/health')).status, 200)
  })

  test('refuses requests addressed to another name for this Mac (DNS rebinding)', async () => {
    const response = await app.request('http://evil.example:8787/api/library')
    assert.equal(response.status, 403)
    assert.equal((await app.request('http://127.0.0.1:8787/api/library')).status, 200)
  })

  test('refuses changes sent by a page on another site', async () => {
    const post = (origin: string) => app.request('http://localhost:8787/api/folders', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json', Origin: origin },
      body: JSON.stringify({ name: 'Sneaky', parentId: null }),
    })
    assert.equal((await post('https://evil.example')).status, 403)
    assert.equal((await post('null')).status, 403)
    assert.equal((await post('http://localhost:5173')).status, 201)
  })

  test('only accepts JSON bodies', async () => {
    const response = await app.request('/api/folders', {
      method: 'POST', headers: { 'Content-Type': 'text/plain' }, body: JSON.stringify({ name: 'Sneaky', parentId: null }),
    })
    assert.equal(response.status, 400)
    assert.equal(store.library().folders.length, 0)
  })

  test('refuses oversized requests, even ones sent without a length', async () => {
    local = false
    const big = 'x'.repeat(100_000)
    const withLength = await app.request('/pair', {
      method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ code: big }),
    })
    assert.equal(withLength.status, 413)
    const stream = new ReadableStream({
      start(controller) {
        controller.enqueue(new TextEncoder().encode(JSON.stringify({ code: big })))
        controller.close()
      },
    })
    const chunked = await app.request('/pair', {
      method: 'POST', headers: { 'Content-Type': 'application/json' }, body: stream, duplex: 'half',
    } as RequestInit)
    assert.equal(chunked.status, 413)
  })
})

describe('pairing', () => {
  test('a valid code gives a token that unlocks sync', async () => {
    const token = await pairedToken()
    assert.ok(token.length > 20)
    await sync(token, {})
    local = true
    assert.equal((await call('GET', '/api/status')).body.devices[0].name, 'Test iPhone')
  })

  test('sync without a valid token is refused', async () => {
    local = false
    assert.equal((await call('POST', '/sync', { cursor: 0 }, 'nope')).status, 401)
  })

  test('codes are single-use', async () => {
    const { code } = store.createPairingCode()
    assert.ok(store.pair(code, 'iPhone'))
    assert.equal(store.pair(code, 'iPhone'), null)
  })

  test('too many wrong guesses burn the code', () => {
    const { code } = store.createPairingCode()
    const wrong = code === '000000' ? '111111' : '000000'
    for (let i = 0; i < 5; i++) assert.equal(store.pair(wrong, 'iPhone'), null)
    assert.equal(store.pair(code, 'iPhone'), null)
  })

  test('codes expire', () => {
    const { code, expiresAt } = store.createPairingCode(0)
    assert.equal(store.pair(code, 'iPhone', expiresAt + 1), null)
  })
})

describe('sync', () => {
  test('first sync uploads the phone library and returns nothing it already has', async () => {
    const token = await pairedToken()
    const os = folder()
    const memory = folder({ name: 'Memory', parentId: os.id })
    const pageFault = card(memory.id, { progress: progress() })
    const response = await sync(token, { folders: [os, memory], cards: [pageFault] })

    assert.deepEqual(response.folders, [])
    assert.deepEqual(response.cards, [])
    assert.ok(response.cursor > 0)
    assert.deepEqual(store.card(pageFault.id), pageFault)
  })

  test('accepts uppercase UUIDs from Swift and stores them lowercase', async () => {
    const token = await pairedToken()
    const os = folder()
    await sync(token, { folders: [{ ...os, id: os.id.toUpperCase() }] })
    assert.equal(store.folder(os.id)?.name, 'OS')
  })

  test('returns cards written on the Mac since the last sync', async () => {
    const token = await pairedToken()
    const os = store.createFolder('OS', null)
    const first = await sync(token, {})
    assert.equal(first.folders.length, 1)

    const [added] = store.createCards(os.id, [{ front: 'What is a TLB?', back: 'A cache of page translations' }])
    const second = await sync(token, { cursor: first.cursor })
    assert.deepEqual(second.folders, [])
    assert.deepEqual(second.cards.map((c) => c.id), [added.id])

    const third = await sync(token, { cursor: second.cursor })
    assert.deepEqual(third.cards, [])
  })

  test('the newest content edit wins', async () => {
    const token = await pairedToken()
    const os = folder()
    const shared = card(os.id, { front: 'Original', updatedAt: 1000 })
    const { cursor } = await sync(token, { folders: [os], cards: [shared] })

    // The Mac edits at t=3000; the phone's edit at t=2000 is older and loses.
    store.updateCard(shared.id, { front: 'Edited on Mac' }, 3000)
    const response = await sync(token, { cursor, cards: [{ ...shared, front: 'Edited on phone', updatedAt: 2000 }] })
    assert.equal(store.card(shared.id)?.front, 'Edited on Mac')
    assert.equal(response.cards[0].front, 'Edited on Mac')

    // A newer phone edit wins.
    await sync(token, { cursor: response.cursor, cards: [{ ...shared, front: 'Edited on phone again', updatedAt: 4000 }] })
    assert.equal(store.card(shared.id)?.front, 'Edited on phone again')
  })

  test('phone progress is kept even when the Mac wins the content', async () => {
    const token = await pairedToken()
    const os = folder()
    const shared = card(os.id)
    const { cursor } = await sync(token, { folders: [os], cards: [shared] })

    store.updateCard(shared.id, { back: 'Better answer' }, 5000)
    const studied = { ...shared, progress: progress({ updatedAt: 4000 }) }
    const response = await sync(token, { cursor, cards: [studied] })

    const merged = store.card(shared.id)!
    assert.equal(merged.back, 'Better answer')
    assert.deepEqual(merged.progress, studied.progress)
    assert.deepEqual(response.cards[0], merged)
  })

  test('a folder deleted on the phone removes its contents on the Mac', async () => {
    const token = await pairedToken()
    const os = folder()
    const memory = folder({ name: 'Memory', parentId: os.id })
    const { cursor } = await sync(token, { folders: [os, memory] })
    const [macCard] = store.createCards(memory.id, [{ front: 'Q', back: 'A' }], 1500)

    const response = await sync(token, { cursor, folders: [{ ...os, deleted: true, updatedAt: 2000 }] })
    assert.equal(store.library().folders.length, 0)
    assert.equal(store.card(macCard.id)?.deleted, true)
    // The phone hears about the cascaded deletes it didn't send.
    assert.ok(response.folders.some((f) => f.id === memory.id && f.deleted))
  })

  test('cards edited after a folder was deleted elsewhere survive', async () => {
    const token = await pairedToken()
    const os = folder()
    const { cursor } = await sync(token, { folders: [os] })
    const [recent] = store.createCards(os.id, [{ front: 'Q', back: 'A' }], 3000)
    await sync(token, { cursor, folders: [{ ...os, deleted: true, updatedAt: 2000 }] })
    assert.equal(store.card(recent.id)?.deleted, false)
  })

  test('review logs are stored once and restored on a first sync', async () => {
    const token = await pairedToken()
    const os = folder()
    const studied = card(os.id)
    const log = { id: randomUUID(), cardId: studied.id, reviewedAt: 2000, rating: 3, stateBefore: 0 }
    await sync(token, { folders: [os], cards: [studied], reviewLogs: [log, log] })
    assert.equal(store.backup().reviewLogs.length, 1)

    // A reinstalled app starts over at cursor 0 and gets everything back.
    const restore = await sync(token, { cursor: 0 })
    assert.equal(restore.folders.length, 1)
    assert.equal(restore.cards.length, 1)
    assert.deepEqual(restore.reviewLogs, [log])
  })

  test('a card or folder deleted on the phone keeps its text on the Mac', async () => {
    const token = await pairedToken()
    const os = folder()
    const kept = card(os.id, { front: 'What is a TLB?', back: 'A cache' })
    const { cursor } = await sync(token, { folders: [os], cards: [kept] })

    // Deletes from the phone carry no text. The phone already deleted them, so they don't go back.
    const cardDeleted = await sync(token, {
      cursor, cards: [{ ...kept, folderId: null, front: '', back: '', deleted: true, updatedAt: 2000 }],
    })
    assert.deepEqual(store.card(kept.id), { ...kept, deleted: true, updatedAt: 2000 })
    assert.deepEqual(cardDeleted.cards, [])

    const folderDeleted = await sync(token, {
      cursor: cardDeleted.cursor, folders: [{ ...os, name: '', parentId: null, deleted: true, updatedAt: 3000 }],
    })
    assert.equal(store.folder(os.id)?.name, 'OS')
    assert.equal(store.folder(os.id)?.deleted, true)
    assert.deepEqual(folderDeleted.folders, [])
  })

  test('edit times far in the future are capped at a day ahead', async () => {
    const token = await pairedToken()
    const os = folder({ updatedAt: Date.UTC(2100, 0, 1) })
    const studied = card(os.id, { updatedAt: Date.UTC(2100, 0, 1), progress: progress({ updatedAt: Date.UTC(2100, 0, 1) }) })
    const before = Date.now()
    await sync(token, { folders: [os], cards: [studied] })
    const limit = Date.now() + MAX_CLOCK_AHEAD
    assert.ok(store.folder(os.id)!.updatedAt <= limit && store.folder(os.id)!.updatedAt >= before + MAX_CLOCK_AHEAD)
    assert.ok(store.card(studied.id)!.updatedAt <= limit)
    assert.ok(store.card(studied.id)!.progress!.updatedAt <= limit)
    // So an edit made on the Mac in two days still wins.
    store.updateCard(studied.id, { front: 'Later' }, Date.now() + 2 * MAX_CLOCK_AHEAD)
    await sync(token, { cursor: 0, cards: [studied] })
    assert.equal(store.card(studied.id)?.front, 'Later')
  })

  test('the database id stays the same until the database is replaced', async () => {
    const token = await pairedToken()
    const first = await sync(token, { folders: [folder()] })
    const second = await sync(token, { cursor: first.cursor })
    assert.equal(second.databaseId, first.databaseId)

    // A phone that has seen more changes than this database has means the database was replaced
    // (e.g. by an older copy), so the id changes and the phone knows to send everything again.
    const replaced = await sync(token, { cursor: first.cursor + 1000 })
    assert.notEqual(replaced.databaseId, first.databaseId)
    assert.equal((await sync(token, { cursor: replaced.cursor })).databaseId, replaced.databaseId)
  })

  test('an edit that loses on the Mac goes back to the phone, even if the phone saw it before', async () => {
    const token = await pairedToken()
    const os = folder()
    const edited = card(os.id)
    const { cursor } = await sync(token, { folders: [os], cards: [edited] })
    store.updateCard(edited.id, { front: 'Edited on the Mac' }, 5000)
    store.updateFolder(os.id, { name: 'Renamed on the Mac' }, 5000)
    const received = await sync(token, { cursor })
    assert.equal(received.cards[0]?.front, 'Edited on the Mac')

    // The phone edits both afterwards, but its clock is behind, so its edits are older and lose.
    const response = await sync(token, {
      cursor: received.cursor,
      folders: [{ ...os, name: 'Renamed on the phone', updatedAt: 4000 }],
      cards: [{ ...edited, front: 'Edited on the phone', updatedAt: 4000 }],
    })
    assert.equal(store.card(edited.id)?.front, 'Edited on the Mac')
    assert.deepEqual(response.cards.map((c) => c.front), ['Edited on the Mac'])
    assert.deepEqual(response.folders.map((f) => f.name), ['Renamed on the Mac'])

    // Sending what the Mac already has changes nothing and gets nothing back.
    const same = await sync(token, { cursor: response.cursor, folders: [store.folder(os.id)!], cards: [store.card(edited.id)!] })
    assert.deepEqual(same.cards, [])
    assert.deepEqual(same.folders, [])
  })

  test('a delete that loses to a newer Mac edit brings the card back to the phone', async () => {
    const token = await pairedToken()
    const os = folder()
    const kept = card(os.id)
    const { cursor } = await sync(token, { folders: [os], cards: [kept] })
    store.updateCard(kept.id, { front: 'Edited on the Mac' }, 5000)
    const received = await sync(token, { cursor })
    const response = await sync(token, {
      cursor: received.cursor, cards: [{ ...kept, front: '', back: '', folderId: null, deleted: true, updatedAt: 4000 }],
    })
    assert.equal(store.card(kept.id)?.deleted, false)
    assert.deepEqual(response.cards.map((c) => [c.front, c.deleted]), [['Edited on the Mac', false]])
  })

  test('rejects malformed records', async () => {
    const token = await pairedToken()
    const { status } = await call('POST', '/sync', { cursor: 0, cards: [{ id: 'not-a-uuid' }] }, token)
    assert.equal(status, 400)
  })
})

describe('images', () => {
  // The smallest valid PNG header is enough for type detection.
  const png = new Uint8Array([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a, 1, 2, 3])

  async function send(method: string, path: string, bytes: Uint8Array<ArrayBuffer>, token?: string) {
    const headers: Record<string, string> = { 'Content-Type': 'image/png' }
    if (token) headers.Authorization = `Bearer ${token}`
    return app.request(path, { method, headers, body: bytes })
  }

  test('the editor uploads an image and reads it back', async () => {
    const upload = await send('POST', '/api/images', png)
    assert.equal(upload.status, 201)
    const { id } = await upload.json()
    const image = await app.request(`/api/images/${id}`)
    assert.equal(image.status, 200)
    assert.equal(image.headers.get('Content-Type'), 'image/png')
    assert.deepEqual(new Uint8Array(await image.arrayBuffer()), png)
  })

  test('rejects files that aren’t images, whatever they claim to be', async () => {
    const upload = await send('POST', '/api/images', new TextEncoder().encode('<html>not an image</html>'))
    assert.equal(upload.status, 400)
  })

  test('a paired phone learns what the Mac is missing, uploads it, and downloads it', async () => {
    const token = await pairedToken()
    const id = randomUUID()
    const missing = await call('POST', '/images/missing', { ids: [id.toUpperCase()] }, token)
    assert.deepEqual(missing.body, { missing: [id] })

    assert.equal((await send('PUT', `/images/${id}`, png, token)).status, 204)
    assert.deepEqual((await call('POST', '/images/missing', { ids: [id] }, token)).body, { missing: [] })

    const download = await app.request(`/images/${id}`, { headers: { Authorization: `Bearer ${token}` } })
    assert.deepEqual(new Uint8Array(await download.arrayBuffer()), png)
  })

  test('the backup includes the images cards use', async () => {
    const { id } = await (await send('POST', '/api/images', png)).json()
    const folder = store.createFolder('OS', null)
    store.createCards(folder.id, [{ front: 'Q', back: `![](image:${id})` }])
    const backup = (await call('GET', '/api/backup')).body
    assert.deepEqual(Object.keys(backup.images), [id])
    assert.deepEqual(new Uint8Array(Buffer.from(backup.images[id].base64, 'base64')), png)
  })

  test('unused images are removed once they’re a week old', () => {
    const imageStore = new ImageStore(mkdtempSync(join(tmpdir(), 'studyup-images-')))
    const used = randomUUID()
    const recent = randomUUID()
    const old = randomUUID()
    for (const id of [used, recent, old]) imageStore.save(id, png)
    const eightDaysAgo = (Date.now() - 8 * 86_400_000) / 1000
    utimesSync(join(imageStore.directory, `${used}.png`), eightDaysAgo, eightDaysAgo)
    utimesSync(join(imageStore.directory, `${old}.png`), eightDaysAgo, eightDaysAgo)

    assert.equal(imageStore.removeUnused(new Set([used])), 1)
    assert.ok(imageStore.read(used))
    assert.ok(imageStore.read(recent), 'pasted recently, maybe into a card not saved yet')
    assert.equal(imageStore.read(old), undefined)
  })

  test('phone image routes need the pairing token', async () => {
    local = false
    const id = randomUUID()
    assert.equal((await send('PUT', `/images/${id}`, png)).status, 401)
    assert.equal((await app.request(`/images/${id}`)).status, 401)
    assert.equal((await app.request(`/api/images/${id}`)).status, 403)
  })
})

describe('backups', () => {
  const directory = () => mkdtempSync(join(tmpdir(), 'studyup-backups-'))

  test('saves one snapshot a day that opens as a complete database', () => {
    const dir = directory()
    store.createFolder('OS', null)
    const path = backUpDatabase(openDatabase(':memory:'), dir, new Date(2026, 9, 26, 9))
    assert.ok(path?.endsWith('studyup-2026-10-26.db'))
    assert.equal(backUpDatabase(openDatabase(':memory:'), dir, new Date(2026, 9, 26, 18)), null)

    const db = openDatabase(join(dir, 'source.db'))
    new Store(db).createFolder('Memory', null)
    const snapshot = backUpDatabase(db, dir, new Date(2026, 9, 27))!
    const copy = new DatabaseSync(snapshot, { readOnly: true })
    assert.equal(copy.prepare('SELECT name FROM folders').get()?.name, 'Memory')
  })

  test('keeps only the newest snapshots', () => {
    const dir = directory()
    for (let day = 1; day <= 20; day++) writeFileSync(join(dir, `studyup-2026-09-${String(day).padStart(2, '0')}.db`), '')
    writeFileSync(join(dir, 'notes.txt'), 'not a backup')
    backUpDatabase(openDatabase(':memory:'), dir, new Date(2026, 9, 26))
    const kept = readdirSync(dir).filter((name) => name.endsWith('.db')).sort()
    assert.equal(kept.length, BACKUPS_KEPT)
    assert.equal(kept.at(-1), 'studyup-2026-10-26.db')
    assert.ok(existsSync(join(dir, 'notes.txt')))
  })

  test('a checkpoint empties the write-ahead log into the database file', () => {
    const path = join(directory(), 'studyup.db')
    const fileStore = new Store(openDatabase(path))
    fileStore.createFolder('OS', null)
    assert.ok(statSync(`${path}-wal`).size > 0)
    fileStore.checkpoint()
    assert.equal(statSync(`${path}-wal`).size, 0)
  })
})
