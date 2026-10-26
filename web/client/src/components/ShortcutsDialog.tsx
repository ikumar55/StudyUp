import { modKey } from '../format.ts'
import { Dialog } from './Dialog.tsx'

const groups: { title: string; shortcuts: [string, string][] }[] = [
  {
    title: 'Writing cards',
    shortcuts: [
      ['N', 'Start a new card (focus Question)'],
      [`${modKey}↩`, 'Add the card and start the next one'],
      ['Tab', 'Question → Answer'],
      [`${modKey}B`, 'Bold the selected text (again to undo)'],
    ],
  },
  {
    title: 'Cards',
    shortcuts: [
      ['↑ ↓  or  J K', 'Move between cards'],
      ['↩', 'Edit the focused card'],
      [`${modKey}↩ / Esc`, 'Save / cancel an edit'],
      ['M', 'Move the focused card'],
      ['⌫', 'Delete the focused card (undo from the toast)'],
    ],
  },
  {
    title: 'Topics',
    shortcuts: [
      ['↑ ↓', 'Move between topics'],
      ['← →', 'Collapse / expand'],
      ['↩', 'Rename the topic'],
      [`${modKey}⌫`, 'Delete the topic'],
      ['Right-click', 'More actions'],
    ],
  },
  {
    title: 'Anywhere',
    shortcuts: [
      [`${modKey}K`, 'Search all cards'],
      ['Esc', 'Clear the search'],
      ['?', 'Show this list'],
    ],
  },
]

export function ShortcutsDialog({ onClose }: { onClose: () => void }) {
  return (
    <Dialog title="Keyboard shortcuts" onClose={onClose} className="dialog-shortcuts">
      <div className="shortcut-groups">
        {groups.map((group) => (
          <section key={group.title}>
            <h3 className="section-label">{group.title}</h3>
            <dl className="shortcut-list">
              {group.shortcuts.map(([keys, action]) => (
                <div key={action} className="shortcut">
                  <dt><kbd>{keys}</kbd></dt>
                  <dd>{action}</dd>
                </div>
              ))}
            </dl>
          </section>
        ))}
      </div>
    </Dialog>
  )
}
