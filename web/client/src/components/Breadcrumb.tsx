import type { FolderRecord } from '../../../shared/protocol.ts'

/** The path to the current folder; earlier segments are links. */
export function Breadcrumb({ path, onSelect }: { path: FolderRecord[]; onSelect: (id: string) => void }) {
  if (path.length < 2) return null
  return (
    <nav className="breadcrumb" aria-label="Topic path">
      <ol>
        {path.slice(0, -1).map((folder) => (
          <li key={folder.id}>
            <button type="button" className="breadcrumb-link" onClick={() => onSelect(folder.id)}>
              {folder.name}
            </button>
            <span className="breadcrumb-separator" aria-hidden="true">›</span>
          </li>
        ))}
      </ol>
    </nav>
  )
}
