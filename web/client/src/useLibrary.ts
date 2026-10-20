import { useCallback, useEffect, useRef, useState } from 'react'
import type { CardRecord, FolderRecord, Library, ServerStatus } from '../../shared/protocol.ts'
import { api, errorMessage } from './api.ts'
import { compareFolderNames } from './libraryIndex.ts'

const pollInterval = 3000

export interface LibraryState {
  library: Library | null
  status: ServerStatus | null
  /** Set when the first load fails. */
  loadError: string | null
  /** True while the server can't be reached. */
  offline: boolean
  /** Checks for changes now instead of waiting for the next poll. */
  refresh: () => void
  /** Applies records the server returned, ahead of the next refetch. */
  applyFolder: (folder: FolderRecord) => void
  applyCards: (cards: CardRecord[]) => void
  removeCards: (ids: Iterable<string>) => void
  removeFolders: (ids: Iterable<string>) => void
}

/**
 * Loads the library and keeps it current. Polls /api/status and refetches the library whenever its
 * version changes (an edit here, or a sync from the phone). Only `library` is replaced, so text the
 * user is typing, which lives in component state, is never touched.
 */
export function useLibrary(): LibraryState {
  const [library, setLibrary] = useState<Library | null>(null)
  const [status, setStatus] = useState<ServerStatus | null>(null)
  const [loadError, setLoadError] = useState<string | null>(null)
  const [offline, setOffline] = useState(false)

  const loaded = useRef(false)
  const knownVersion = useRef<number | null>(null)
  /** Bumped by every local change, so a library fetch that started before it doesn't undo it. */
  const localChanges = useRef(0)
  const polling = useRef(false)
  const pollAgain = useRef(false)

  const poll = useCallback(async () => {
    if (polling.current) {
      pollAgain.current = true
      return
    }
    polling.current = true
    try {
      do {
        pollAgain.current = false
        const nextStatus = await api.status()
        setStatus(nextStatus)
        setOffline(false)
        if (nextStatus.version === knownVersion.current) continue

        const changesBefore = localChanges.current
        const nextLibrary = await api.library()
        if (changesBefore !== localChanges.current) {
          // A local edit landed meanwhile; fetch again so it's included.
          pollAgain.current = true
          continue
        }
        knownVersion.current = nextStatus.version
        loaded.current = true
        setLibrary(nextLibrary)
        setLoadError(null)
      } while (pollAgain.current)
    } catch (error) {
      setOffline(true)
      if (!loaded.current) setLoadError(errorMessage(error))
    } finally {
      polling.current = false
    }
  }, [])

  useEffect(() => {
    void poll()
    const timer = setInterval(() => {
      if (document.visibilityState === 'visible') void poll()
    }, pollInterval)
    const onFocus = () => void poll()
    window.addEventListener('focus', onFocus)
    document.addEventListener('visibilitychange', onFocus)
    return () => {
      clearInterval(timer)
      window.removeEventListener('focus', onFocus)
      document.removeEventListener('visibilitychange', onFocus)
    }
  }, [poll])

  const refresh = useCallback(() => void poll(), [poll])

  const update = useCallback((change: (library: Library) => Library) => {
    localChanges.current += 1
    setLibrary((current) => (current ? change(current) : current))
    void poll()
  }, [poll])

  const applyFolder = useCallback((folder: FolderRecord) => update((current) => ({
    ...current,
    folders: [...current.folders.filter((f) => f.id !== folder.id), folder].sort(compareFolderNames),
  })), [update])

  const applyCards = useCallback((cards: CardRecord[]) => update((current) => {
    const ids = new Set(cards.map((card) => card.id))
    return { ...current, cards: [...current.cards.filter((card) => !ids.has(card.id)), ...cards] }
  }), [update])

  const removeCards = useCallback((ids: Iterable<string>) => {
    const removed = new Set(ids)
    update((current) => ({ ...current, cards: current.cards.filter((card) => !removed.has(card.id)) }))
  }, [update])

  const removeFolders = useCallback((ids: Iterable<string>) => {
    const removed = new Set(ids)
    update((current) => ({
      folders: current.folders.filter((folder) => !removed.has(folder.id)),
      cards: current.cards.filter((card) => card.folderId === null || !removed.has(card.folderId)),
    }))
  }, [update])

  return { library, status, loadError, offline, refresh, applyFolder, applyCards, removeCards, removeFolders }
}
