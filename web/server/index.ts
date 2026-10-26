import { serve } from '@hono/node-server'
import { serveStatic } from '@hono/node-server/serve-static'
import { execFileSync, spawn } from 'node:child_process'
import type { ChildProcess } from 'node:child_process'
import { existsSync } from 'node:fs'
import { dirname, join, relative } from 'node:path'
import { fileURLToPath } from 'node:url'
import { createApp } from './app.ts'
import { imageIDs } from '../shared/images.ts'
import { backUpDatabase } from './backups.ts'
import { defaultBackupsDirectory, defaultDatabasePath, defaultImagesDirectory, openDatabase } from './db.ts'
import { ImageStore } from './images.ts'
import { Store } from './store.ts'

const port = Number(process.env.PORT ?? 8787)
const computerName = macSetting('ComputerName') ?? 'Mac'
const db = openDatabase()
const store = new Store(db, computerName)
const images = new ImageStore(defaultImagesDirectory())
const app = createApp(store, images)

// Clean up images no card uses anymore: at startup, then twice a day.
const removeUnusedImages = () => {
  const referenced = new Set(store.library().cards.flatMap((card) => [...imageIDs(card.front), ...imageIDs(card.back)]))
  const removed = images.removeUnused(referenced)
  if (removed > 0) console.log(`Removed ${removed} unused image${removed === 1 ? '' : 's'}`)
}
removeUnusedImages()
setInterval(removeUnusedImages, 12 * 3_600_000).unref()

// A snapshot of the database once a day (checked hourly, since the Mac may sleep through midnight).
const backUp = () => {
  try {
    const path = backUpDatabase(db, defaultBackupsDirectory())
    if (path) console.log(`Backed up the database to ${path}`)
    store.checkpoint()
  } catch (error) {
    console.error('Couldn’t back up the database:', error)
  }
}
backUp()
setInterval(backUp, 3_600_000).unref()

// The built web UI (npm run build). During development Vite serves it instead.
const clientDir = join(dirname(fileURLToPath(import.meta.url)), '..', 'client', 'dist')
if (existsSync(clientDir)) {
  const root = relative(process.cwd(), clientDir) || '.'
  app.use('/*', serveStatic({ root }))
  app.get('*', serveStatic({ root, path: 'index.html' }))
}

// Listen on all interfaces so the phone can reach /pair and /sync over Wi-Fi.
serve({ fetch: app.fetch, port, hostname: '::' }, () => {
  console.log(`StudyUp is running at http://localhost:${port}`)
  console.log(`Database: ${defaultDatabasePath()}`)
})

const advert = advertiseOnNetwork()

// launchd stops the service with SIGTERM. Closing the database folds its write-ahead log back into
// studyup.db, so the file is complete on its own.
process.on('exit', () => advert.kill())
for (const signal of ['SIGINT', 'SIGTERM'] as const) {
  process.on(signal, () => {
    db.close()
    process.exit(0)
  })
}

/** Announces the server over Bonjour so the phone can find it, using macOS's built-in dns-sd. */
function advertiseOnNetwork(): ChildProcess {
  const hostName = macSetting('LocalHostName')
  // The phone builds http://host:port from these, since Bonjour browse results don't include a port.
  const txt = [`path=/`, `name=${computerName}`, `port=${port}`, ...(hostName ? [`host=${hostName}.local`] : [])]
  const advert = spawn('dns-sd', ['-R', `StudyUp on ${computerName}`, '_studyup._tcp', 'local', String(port), ...txt], {
    stdio: 'ignore',
  })
  advert.on('error', (error) => console.warn(`Couldn’t advertise on the network: ${error.message}`))
  return advert
}

function macSetting(name: string): string | undefined {
  try {
    return execFileSync('scutil', ['--get', name], { encoding: 'utf8' }).trim() || undefined
  } catch {
    return undefined
  }
}
