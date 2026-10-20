import type { CardRecord, FolderRecord, Library, ServerStatus } from '../../shared/protocol.ts'

/** A failed request, carrying the server's human-readable message. */
export class ApiError extends Error {
  readonly status: number

  constructor(message: string, status: number) {
    super(message)
    this.name = 'ApiError'
    this.status = status
  }
}

export interface CardContent {
  front: string
  back: string
}

export interface PairingCode {
  code: string
  expiresAt: number
}

async function request<T>(method: string, path: string, body?: unknown): Promise<T> {
  let response: Response
  try {
    response = await fetch(path, {
      method,
      headers: body === undefined ? undefined : { 'Content-Type': 'application/json' },
      body: body === undefined ? undefined : JSON.stringify(body),
    })
  } catch {
    throw new ApiError('Can’t reach the StudyUp server. Is it still running?', 0)
  }

  if (response.status === 204) return undefined as T
  const text = await response.text()
  let data: unknown = null
  try {
    data = text ? JSON.parse(text) : null
  } catch {
    // Not JSON; handled below.
  }

  if (!response.ok) {
    const message = isErrorBody(data) ? data.error : `The server returned an error (${response.status}).`
    throw new ApiError(message, response.status)
  }
  return data as T
}

function isErrorBody(data: unknown): data is { error: string } {
  return typeof data === 'object' && data !== null && typeof (data as { error?: unknown }).error === 'string'
}

const id = (value: string) => encodeURIComponent(value)

export const api = {
  library: () => request<Library>('GET', '/api/library'),
  status: () => request<ServerStatus>('GET', '/api/status'),

  createFolder: (name: string, parentId: string | null) =>
    request<FolderRecord>('POST', '/api/folders', { name, parentId }),
  updateFolder: (folderId: string, changes: { name?: string; parentId?: string | null }) =>
    request<FolderRecord>('PATCH', `/api/folders/${id(folderId)}`, changes),
  deleteFolder: (folderId: string) => request<void>('DELETE', `/api/folders/${id(folderId)}`),

  createCards: (folderId: string, cards: CardContent[]) =>
    request<CardRecord[]>('POST', '/api/cards', { folderId, cards }),
  updateCard: (cardId: string, changes: { front?: string; back?: string; folderId?: string }) =>
    request<CardRecord>('PATCH', `/api/cards/${id(cardId)}`, changes),
  deleteCard: (cardId: string) => request<void>('DELETE', `/api/cards/${id(cardId)}`),

  createPairingCode: () => request<PairingCode>('POST', '/api/pairing-code'),
  forgetDevices: () => request<void>('DELETE', '/api/devices'),

  /** Deletes a card even while the page is closing (used to flush pending deletes). */
  deleteCardOnUnload: (cardId: string) => {
    void fetch(`/api/cards/${id(cardId)}`, { method: 'DELETE', keepalive: true }).catch(() => {})
  },

  backupURL: '/api/backup',
}

export function errorMessage(error: unknown): string {
  if (error instanceof Error && error.message) return error.message
  return 'Something went wrong.'
}
