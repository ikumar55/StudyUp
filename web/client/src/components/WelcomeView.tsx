import { modKey } from '../format.ts'
import { PhoneIcon, PlusIcon } from './Icons.tsx'

interface Props {
  hasPhone: boolean
  onNewTopic: () => void
  onPair: () => void
}

/** Shown before any topics exist. */
export function WelcomeView({ hasPhone, onNewTopic, onPair }: Props) {
  return (
    <div className="empty-state welcome">
      <img src="/icon.svg" alt="" width={56} height={56} />
      <p className="empty-title">Write your first cards</p>
      <p className="empty-text">
        Topics hold your cards and can nest as deep as you like, such as <em>OS Fundamentals › Memory</em>.
        Write cards here; study them on your iPhone.
      </p>
      <div className="welcome-actions">
        <button type="button" className="button button-primary button-large" onClick={onNewTopic}>
          <PlusIcon /> New topic
        </button>
        {!hasPhone && (
          <button type="button" className="button button-large" onClick={onPair}>
            <PhoneIcon /> Pair an iPhone
          </button>
        )}
      </div>
      <ol className="welcome-steps">
        <li>Create a topic and give it a name.</li>
        <li>Type a question, press <kbd>Tab</kbd>, type the answer, press <kbd>{modKey}↩</kbd>. Repeat.</li>
        <li>Already have notes? Paste them with <strong>Bulk add</strong>.</li>
      </ol>
    </div>
  )
}
