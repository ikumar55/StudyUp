import { existsSync, mkdirSync, readdirSync, readFileSync, renameSync, statSync, unlinkSync, writeFileSync } from 'node:fs'
import { join } from 'node:path'
import { InvalidRequestError } from './store.ts'

/** Image file types accepted, identified by their leading bytes rather than a claimed Content-Type. */
const TYPES = [
  { mime: 'image/png', ext: 'png', matches: (b: Uint8Array) => startsWith(b, [0x89, 0x50, 0x4e, 0x47]) },
  { mime: 'image/jpeg', ext: 'jpg', matches: (b: Uint8Array) => startsWith(b, [0xff, 0xd8, 0xff]) },
  { mime: 'image/gif', ext: 'gif', matches: (b: Uint8Array) => startsWith(b, [0x47, 0x49, 0x46, 0x38]) },
  {
    mime: 'image/webp', ext: 'webp',
    matches: (b: Uint8Array) => startsWith(b, [0x52, 0x49, 0x46, 0x46]) && String.fromCharCode(...b.slice(8, 12)) === 'WEBP',
  },
] as const

export const MAX_IMAGE_BYTES = 15 * 1024 * 1024
const ID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/

/** Image files referenced from card text as `![](image:<id>)`. An image never changes once saved,
 *  so syncing images is only ever "send the ones the other side is missing". */
export class ImageStore {
  readonly directory: string

  constructor(directory: string) {
    mkdirSync(directory, { recursive: true })
    this.directory = directory
  }

  /** Saves an image under `id`. Saving an id that already exists does nothing. */
  save(id: string, bytes: Uint8Array): void {
    const imageID = normalizeID(id)
    if (bytes.length === 0) throw new InvalidRequestError('The image is empty.')
    if (bytes.length > MAX_IMAGE_BYTES) throw new InvalidRequestError('Images must be smaller than 15 MB.')
    const type = TYPES.find((candidate) => candidate.matches(bytes))
    if (!type) throw new InvalidRequestError('Only PNG, JPEG, GIF and WebP images are supported.')
    if (this.#path(imageID)) return
    const path = join(this.directory, `${imageID}.${type.ext}`)
    // Write then rename, so a half-written file is never served.
    writeFileSync(`${path}.partial`, bytes)
    renameSync(`${path}.partial`, path)
  }

  read(id: string): { bytes: Buffer; mime: string } | undefined {
    if (!ID.test(id.toLowerCase())) return undefined
    const path = this.#path(id.toLowerCase())
    if (!path) return undefined
    const type = TYPES.find((candidate) => path.endsWith(`.${candidate.ext}`))!
    return { bytes: readFileSync(path), mime: type.mime }
  }

  /** The ids among `ids` that this store doesn't have. */
  missing(ids: string[]): string[] {
    return [...new Set(ids.map((id) => id.toLowerCase()))].filter((id) => ID.test(id) && !this.#path(id))
  }

  /** Deletes images no card refers to. Recent ones are kept, since an image is uploaded as soon as
   *  it's pasted, before its card is saved. Returns how many were removed. */
  removeUnused(referenced: Set<string>, now = Date.now(), keepNewerThan = 7 * 86_400_000): number {
    let removed = 0
    for (const file of readdirSync(this.directory)) {
      const id = file.split('.')[0]
      if (!ID.test(id) || referenced.has(id) || file.endsWith('.partial')) continue
      const path = join(this.directory, file)
      if (now - statSync(path).mtimeMs < keepNewerThan) continue
      unlinkSync(path)
      removed += 1
    }
    return removed
  }

  #path(id: string): string | undefined {
    for (const type of TYPES) {
      const path = join(this.directory, `${id}.${type.ext}`)
      if (existsSync(path)) return path
    }
    return undefined
  }
}

function normalizeID(id: string): string {
  const lower = id.toLowerCase()
  if (!ID.test(lower)) throw new InvalidRequestError(`Invalid image id: ${id}`)
  return lower
}

function startsWith(bytes: Uint8Array, prefix: number[]): boolean {
  return prefix.every((value, index) => bytes[index] === value)
}
