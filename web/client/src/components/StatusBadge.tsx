import type { Progress } from '../../../shared/protocol.ts'
import { useNow } from '../clock.tsx'
import { cardStatus } from '../format.ts'

export function StatusBadge({ progress }: { progress: Progress | null }) {
  const status = cardStatus(progress, useNow())
  return (
    <span className={`status status-${status.tone}`} title={status.detail}>
      {status.label}
    </span>
  )
}
