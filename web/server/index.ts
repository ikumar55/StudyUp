import { serve } from '@hono/node-server'
import { serveStatic } from '@hono/node-server/serve-static'
import { execFileSync, spawn } from 'node:child_process'
import { existsSync } from 'node:fs'
import { dirname, join, relative } from 'node:path'
import { fileURLToPath } from 'node:url'
import { createApp } from './app.ts'
import { imageIDs } from '../shared/images.ts'
import { defaultDatabasePath, defaultImagesDirectory, openDatabase } from './db.ts'
import { ImageStore } from './images.ts'
import { Store } from './store.ts'

const port = Number(process.env.PORT ?? 8787)
const computerName = macSetting('ComputerName') ?? 'Mac'
const store = new Store(openDatabase(), computerName)
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

advertiseOnNetwork()

/** Announces the server over Bonjour so the phone can find it, using macOS's built-in dns-sd. */
function advertiseOnNetwork(): void {
  const hostName = macSetting('LocalHostName')
  // The phone builds http://host:port from these, since Bonjour browse results don't include a port.
  const txt = [`path=/`, `name=${computerName}`, `port=${port}`, ...(hostName ? [`host=${hostName}.local`] : [])]
  const advert = spawn('dns-sd', ['-R', `StudyUp on ${computerName}`, '_studyup._tcp', 'local', String(port), ...txt], {
    stdio: 'ignore',
  })
  advert.on('error', (error) => console.warn(`Couldn’t advertise on the network: ${error.message}`))
  const stop = () => advert.kill()
  process.on('exit', stop)
  for (const signal of ['SIGINT', 'SIGTERM'] as const) {
    process.on(signal, () => {
      stop()
      process.exit(0)
    })
  }
}

function macSetting(name: string): string | undefined {
  try {
    return execFileSync('scutil', ['--get', name], { encoding: 'utf8' }).trim() || undefined
  } catch {
    return undefined
  }
}
