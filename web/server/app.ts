import { getConnInfo } from '@hono/node-server/conninfo'
import { Hono } from 'hono'
import type { Context } from 'hono'
import type { PairResponse } from '../shared/protocol.ts'
import { parseSyncRequest } from './validate.ts'
import { InvalidRequestError, NotFoundError, Store } from './store.ts'

export interface AppOptions {
  /** Whether a request comes from this Mac. The editor and its API are only served locally;
   *  other devices on the network can only pair and sync. */
  isLocalRequest?: (c: Context) => boolean
}

export function createApp(store: Store, options: AppOptions = {}): Hono {
  const isLocal = options.isLocalRequest ?? isLoopback
  const app = new Hono()

  app.onError((error, c) => {
    if (error instanceof InvalidRequestError) return c.json({ error: error.message }, 400)
    if (error instanceof NotFoundError) return c.json({ error: error.message }, 404)
    console.error(error)
    return c.json({ error: 'Something went wrong on the Mac.' }, 500)
  })

  // MARK: Reachable from the phone

  app.get('/health', (c) => c.json({ ok: true, serverName: store.serverName }))

  app.post('/pair', async (c) => {
    const body = await readJSON(c)
    const token = store.pair(String(body.code ?? ''), String(body.deviceName ?? 'iPhone'))
    if (!token) return c.json({ error: 'That code is wrong or has expired. Get a new one in the web app.' }, 401)
    return c.json({ token, serverName: store.serverName } satisfies PairResponse)
  })

  app.post('/sync', async (c) => {
    const token = c.req.header('Authorization')?.replace(/^Bearer\s+/i, '') ?? ''
    if (!token || !store.authenticate(token)) {
      return c.json({ error: 'This iPhone isn’t paired with this Mac. Pair again from the app.' }, 401)
    }
    return c.json(store.sync(parseSyncRequest(await readJSON(c))))
  })

  // MARK: This Mac only

  app.use('*', async (c, next) => {
    if (!isLocal(c)) return c.json({ error: 'The StudyUp editor is only available on the Mac running it.' }, 403)
    await next()
  })

  app.get('/api/library', (c) => c.json(store.library()))
  app.get('/api/status', (c) => c.json(store.status()))

  app.get('/api/backup', (c) => {
    const date = new Date().toISOString().slice(0, 10)
    c.header('Content-Disposition', `attachment; filename="studyup-backup-${date}.json"`)
    return c.json(store.backup())
  })

  app.post('/api/pairing-code', (c) => c.json(store.createPairingCode()))
  app.delete('/api/devices', (c) => {
    store.forgetDevices()
    return c.body(null, 204)
  })

  app.post('/api/folders', async (c) => {
    const body = await readJSON(c)
    return c.json(store.createFolder(String(body.name ?? ''), optionalID(body.parentId)), 201)
  })

  app.patch('/api/folders/:id', async (c) => {
    const body = await readJSON(c)
    return c.json(store.updateFolder(c.req.param('id'), {
      name: body.name === undefined ? undefined : String(body.name),
      parentId: body.parentId === undefined ? undefined : optionalID(body.parentId),
    }))
  })

  app.delete('/api/folders/:id', (c) => {
    store.deleteFolder(c.req.param('id'))
    return c.body(null, 204)
  })

  app.post('/api/cards', async (c) => {
    const body = await readJSON(c)
    const cards = Array.isArray(body.cards)
      ? body.cards.map((card: { front?: unknown; back?: unknown }) => ({ front: String(card.front ?? ''), back: String(card.back ?? '') }))
      : [{ front: String(body.front ?? ''), back: String(body.back ?? '') }]
    return c.json(store.createCards(String(body.folderId ?? ''), cards), 201)
  })

  app.patch('/api/cards/:id', async (c) => {
    const body = await readJSON(c)
    return c.json(store.updateCard(c.req.param('id'), {
      front: body.front === undefined ? undefined : String(body.front),
      back: body.back === undefined ? undefined : String(body.back),
      folderId: body.folderId === undefined ? undefined : String(body.folderId),
    }))
  })

  app.delete('/api/cards/:id', (c) => {
    store.deleteCard(c.req.param('id'))
    return c.body(null, 204)
  })

  return app
}

async function readJSON(c: Context): Promise<Record<string, any>> {
  try {
    const body = await c.req.json()
    if (typeof body === 'object' && body !== null) return body
  } catch {
    // Fall through to the error below.
  }
  throw new InvalidRequestError('Expected a JSON body.')
}

function optionalID(value: unknown): string | null {
  return value === null || value === undefined || value === '' ? null : String(value)
}

function isLoopback(c: Context): boolean {
  try {
    const address = getConnInfo(c).remote.address
    return address === '127.0.0.1' || address === '::1' || address === '::ffff:127.0.0.1'
  } catch {
    return false
  }
}
