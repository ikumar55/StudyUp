/** What the main pane shows: a folder id, or cards whose folder no longer exists. */
export type Selection = string | typeof unfiled | null

export const unfiled = 'unfiled' as const

/** An inline folder-name field in the sidebar. */
export type FolderEdit =
  | { mode: 'create'; parentId: string | null }
  | { mode: 'rename'; id: string }

/** Folder operations the sidebar and folder view can trigger. */
export interface FolderActions {
  select: (id: Selection) => void
  startCreate: (parentId: string | null) => void
  startRename: (id: string) => void
  cancelEdit: () => void
  /** Resolves to false if the server refused (the field stays open). */
  commitCreate: (parentId: string | null, name: string) => Promise<boolean>
  commitRename: (id: string, name: string) => Promise<boolean>
  requestMove: (id: string) => void
  requestDelete: (id: string) => void
  moveFolder: (id: string, parentId: string | null) => void
  moveCard: (cardId: string, folderId: string) => void
}

/** Card operations used by the card list and search results. */
export interface CardActions {
  save: (cardId: string, front: string, back: string) => Promise<boolean>
  remove: (cardId: string) => void
  requestMove: (cardId: string) => void
  /** Makes a studied card due now ("I feel shaky on this"). */
  reviewToday: (cardId: string) => void
  /** Starts a card over as new ("I've forgotten this"). */
  resetProgress: (cardId: string) => void
}
