import { useEffect, useMemo, useRef } from 'react'
import { api, errorMessage } from './api.ts'
import type { CardContent } from './api.ts'
import { plural } from './format.ts'
import { descendantIds, folderPath } from './libraryIndex.ts'
import type { LibraryIndex } from './libraryIndex.ts'
import { useToasts } from './toasts.tsx'
import type { CardActions, FolderActions, FolderEdit, Selection } from './types.ts'
import type { LibraryState } from './useLibrary.ts'

/** View state the actions read and change; owned by App. */
export interface ActionContext {
  lib: LibraryState
  index: LibraryIndex | null
  selected: Selection
  select: (id: Selection) => void
  setEdit: (edit: FolderEdit | null) => void
  expand: (id: string) => void
  /** Cards hidden while their delete can still be undone. */
  setPendingDeletes: (update: (current: Set<string>) => Set<string>) => void
  openMoveFolder: (id: string) => void
  openDeleteFolder: (id: string) => void
  openMoveCard: (id: string) => void
  focusQuestion: () => void
}

export interface Actions {
  folder: FolderActions
  card: CardActions
  addCard: (folderId: string, front: string, back: string) => Promise<boolean>
  importCards: (folderId: string, cards: CardContent[]) => Promise<boolean>
  deleteFolder: (id: string) => Promise<void>
}

/**
 * Every edit: calls the API, applies the server's response locally, and reports errors as toasts.
 * The returned object is stable, so memoized rows don't re-render when unrelated state changes.
 */
export function useActions(context: ActionContext): Actions {
  const toasts = useToasts()
  const latest = useRef(context)
  latest.current = context
  /** Card ids whose delete is waiting for the undo toast to expire. */
  const pending = useRef(new Set<string>())

  // Deletes still waiting for their undo toast are sent if the page closes.
  useEffect(() => {
    const flush = () => {
      for (const id of pending.current) api.deleteCardOnUnload(id)
      pending.current.clear()
    }
    window.addEventListener('pagehide', flush)
    return () => window.removeEventListener('pagehide', flush)
  }, [])

  return useMemo<Actions>(() => {
    const ctx = () => latest.current
    const name = (folderId: string | null) =>
      (folderId && ctx().index?.folders.get(folderId)?.name) || 'that topic'

    const fail = (error: unknown) => {
      toasts.error(errorMessage(error))
      return false
    }

    const unhide = (cardId: string) =>
      ctx().setPendingDeletes((current) => {
        const next = new Set(current)
        next.delete(cardId)
        return next
      })

    const commitDelete = async (cardId: string) => {
      if (!pending.current.delete(cardId)) return
      try {
        await api.deleteCard(cardId)
        ctx().lib.removeCards([cardId])
      } catch (error) {
        fail(error)
      } finally {
        unhide(cardId)
      }
    }

    const moveCard = async (cardId: string, folderId: string, undoable = true) => {
      const card = ctx().index?.allCards.find((c) => c.id === cardId)
      if (!card || card.folderId === folderId) return
      const from = card.folderId
      try {
        const updated = await api.updateCard(cardId, { folderId })
        ctx().lib.applyCards([updated])
        toasts.show({
          message: `Moved to ${name(folderId)}`,
          action: undoable && from ? { label: 'Undo', run: () => void moveCard(cardId, from, false) } : undefined,
        })
      } catch (error) {
        fail(error)
      }
    }

    const folder: FolderActions = {
      select: (id) => ctx().select(id),
      startCreate: (parentId) => {
        if (parentId) ctx().expand(parentId)
        ctx().setEdit({ mode: 'create', parentId })
      },
      startRename: (id) => ctx().setEdit({ mode: 'rename', id }),
      cancelEdit: () => ctx().setEdit(null),
      commitCreate: async (parentId, folderName) => {
        try {
          const created = await api.createFolder(folderName, parentId)
          ctx().lib.applyFolder(created)
          ctx().setEdit(null)
          ctx().select(created.id)
          // A new topic is usually followed by its first card.
          requestAnimationFrame(() => ctx().focusQuestion())
          return true
        } catch (error) {
          return fail(error)
        }
      },
      commitRename: async (id, folderName) => {
        try {
          ctx().lib.applyFolder(await api.updateFolder(id, { name: folderName }))
          ctx().setEdit(null)
          requestAnimationFrame(() => document.querySelector<HTMLElement>(`[data-folder-id="${id}"]`)?.focus())
          return true
        } catch (error) {
          return fail(error)
        }
      },
      requestMove: (id) => ctx().openMoveFolder(id),
      requestDelete: (id) => ctx().openDeleteFolder(id),
      moveFolder: async (id, parentId) => {
        const current = ctx().index?.folders.get(id)
        if (!current || current.parentId === parentId || id === parentId) return
        try {
          const updated = await api.updateFolder(id, { parentId })
          ctx().lib.applyFolder(updated)
          if (parentId) ctx().expand(parentId)
          toasts.show({ message: parentId ? `Moved ${updated.name} into ${name(parentId)}` : `Moved ${updated.name} to the top level` })
        } catch (error) {
          fail(error)
        }
      },
      moveCard: (cardId, folderId) => void moveCard(cardId, folderId),
    }

    const card: CardActions = {
      save: async (cardId, front, back) => {
        try {
          ctx().lib.applyCards([await api.updateCard(cardId, { front, back })])
          return true
        } catch (error) {
          return fail(error)
        }
      },
      remove: (cardId) => {
        if (pending.current.has(cardId)) return
        pending.current.add(cardId)
        ctx().setPendingDeletes((current) => new Set(current).add(cardId))
        toasts.show({
          message: 'Card deleted',
          duration: 6000,
          action: {
            label: 'Undo',
            run: () => {
              pending.current.delete(cardId)
              unhide(cardId)
            },
          },
          onExpire: () => void commitDelete(cardId),
        })
      },
      requestMove: (cardId) => ctx().openMoveCard(cardId),
    }

    return {
      folder,
      card,
      addCard: async (folderId, front, back) => {
        try {
          ctx().lib.applyCards(await api.createCards(folderId, [{ front, back }]))
          return true
        } catch (error) {
          return fail(error)
        }
      },
      importCards: async (folderId, cards) => {
        try {
          const created = await api.createCards(folderId, cards)
          ctx().lib.applyCards(created)
          ctx().select(folderId)
          toasts.show({ message: `Added ${plural(created.length, 'card')} to ${name(folderId)}`, kind: 'success' })
          return true
        } catch (error) {
          return fail(error)
        }
      },
      deleteFolder: async (id) => {
        const index = ctx().index
        if (!index) return
        const removed = descendantIds(index, id)
        const cardCount = index.totalCounts.get(id) ?? 0
        const folderName = name(id)
        const parent = folderPath(index, id).at(-2)?.id ?? null
        try {
          await api.deleteFolder(id)
          ctx().lib.removeFolders(removed)
          const selected = ctx().selected
          if (typeof selected === 'string' && removed.has(selected)) ctx().select(parent)
          toasts.show({ message: `Deleted ${folderName}${cardCount > 0 ? ` and ${plural(cardCount, 'card')}` : ''}` })
        } catch (error) {
          fail(error)
        }
      },
    }
  }, [toasts])
}
