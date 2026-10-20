import { flattenTree, pathLabel } from '../libraryIndex.ts'
import type { LibraryIndex } from '../libraryIndex.ts'

interface Props {
  index: LibraryIndex
  value: string
  onChange: (folderId: string) => void
  id?: string
}

/** A native select listing every topic by its full path, in tree order. */
export function FolderSelect({ index, value, onChange, id }: Props) {
  return (
    <select id={id} className="select" value={value} onChange={(event) => onChange(event.target.value)}>
      {flattenTree(index).map(({ folder }) => (
        <option key={folder.id} value={folder.id}>{pathLabel(index, folder.id)}</option>
      ))}
    </select>
  )
}
