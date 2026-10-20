import type { CardRecord, FolderRecord, Library } from '../../shared/protocol.ts'

/** Lookups derived from the library: the folder tree, cards per folder, and counts. */
export interface LibraryIndex {
  folders: Map<string, FolderRecord>
  /** Children of each folder, sorted by name. `null` holds the top-level folders. */
  children: Map<string | null, FolderRecord[]>
  /** Cards directly in each folder, newest first. `null` holds cards without a (live) folder. */
  cardsByFolder: Map<string | null, CardRecord[]>
  /** Cards in each folder including all its subfolders. */
  totalCounts: Map<string, number>
  allCards: CardRecord[]
}

const nameCollator = new Intl.Collator(undefined, { sensitivity: 'base', numeric: true })

export function compareFolderNames(a: FolderRecord, b: FolderRecord): number {
  return nameCollator.compare(a.name, b.name)
}

export function buildIndex(library: Library, hiddenCardIds: ReadonlySet<string>): LibraryIndex {
  const folders = new Map(library.folders.map((folder) => [folder.id, folder]))

  const children = new Map<string | null, FolderRecord[]>()
  for (const folder of library.folders) {
    // A folder whose parent is gone is shown at the top level rather than lost.
    const parent = folder.parentId !== null && folders.has(folder.parentId) ? folder.parentId : null
    let list = children.get(parent)
    if (!list) children.set(parent, (list = []))
    list.push(folder)
  }
  for (const list of children.values()) list.sort(compareFolderNames)

  const allCards = library.cards
    .filter((card) => !hiddenCardIds.has(card.id))
    .sort((a, b) => b.createdAt - a.createdAt)

  const cardsByFolder = new Map<string | null, CardRecord[]>()
  for (const card of allCards) {
    const key = card.folderId !== null && folders.has(card.folderId) ? card.folderId : null
    let list = cardsByFolder.get(key)
    if (!list) cardsByFolder.set(key, (list = []))
    list.push(card)
  }

  const totalCounts = new Map<string, number>()
  const count = (folderId: string, visiting: Set<string>): number => {
    const known = totalCounts.get(folderId)
    if (known !== undefined) return known
    visiting.add(folderId)
    let total = cardsByFolder.get(folderId)?.length ?? 0
    for (const child of children.get(folderId) ?? []) {
      if (!visiting.has(child.id)) total += count(child.id, visiting)
    }
    totalCounts.set(folderId, total)
    return total
  }
  for (const folder of library.folders) count(folder.id, new Set())

  return { folders, children, cardsByFolder, totalCounts, allCards }
}

/** The folder and its ancestors, top-level first. */
export function folderPath(index: LibraryIndex, folderId: string | null): FolderRecord[] {
  const path: FolderRecord[] = []
  const seen = new Set<string>()
  let current = folderId === null ? undefined : index.folders.get(folderId)
  while (current && !seen.has(current.id)) {
    path.unshift(current)
    seen.add(current.id)
    current = current.parentId === null ? undefined : index.folders.get(current.parentId)
  }
  return path
}

export function pathLabel(index: LibraryIndex, folderId: string | null): string {
  const path = folderPath(index, folderId)
  return path.length === 0 ? 'Unfiled' : path.map((folder) => folder.name).join(' › ')
}

/** The folder's id plus the ids of everything nested inside it. */
export function descendantIds(index: LibraryIndex, folderId: string): Set<string> {
  const ids = new Set<string>()
  const stack = [folderId]
  while (stack.length > 0) {
    const id = stack.pop()!
    if (ids.has(id)) continue
    ids.add(id)
    for (const child of index.children.get(id) ?? []) stack.push(child.id)
  }
  return ids
}

/** Cards in the folder and, optionally, all of its subfolders; newest first. */
export function cardsIn(index: LibraryIndex, folderId: string | null, includeSubfolders: boolean): CardRecord[] {
  if (folderId === null || !includeSubfolders) return index.cardsByFolder.get(folderId) ?? []
  const ids = descendantIds(index, folderId)
  return index.allCards.filter((card) => card.folderId !== null && ids.has(card.folderId))
}

/** Every folder in tree order, with its depth, for pickers. */
export function flattenTree(index: LibraryIndex): { folder: FolderRecord; depth: number }[] {
  const rows: { folder: FolderRecord; depth: number }[] = []
  const visit = (parentId: string | null, depth: number, seen: Set<string>) => {
    for (const folder of index.children.get(parentId) ?? []) {
      if (seen.has(folder.id)) continue
      seen.add(folder.id)
      rows.push({ folder, depth })
      visit(folder.id, depth + 1, seen)
    }
  }
  visit(null, 0, new Set())
  return rows
}
