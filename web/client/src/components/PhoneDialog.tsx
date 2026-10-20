import { useEffect, useRef, useState } from 'react'
import type { ServerStatus } from '../../../shared/protocol.ts'
import { api, errorMessage } from '../api.ts'
import type { PairingCode } from '../api.ts'
import { useNow, useSecondTicker } from '../clock.tsx'
import { countdown, formatDate, timeAgo } from '../format.ts'
import { useToasts } from '../toasts.tsx'
import { Dialog } from './Dialog.tsx'
import { CheckIcon, PhoneIcon } from './Icons.tsx'

interface Props {
  status: ServerStatus | null
  onRefresh: () => void
  onClose: () => void
}

/** Paired iPhones, pairing with a 6-digit code, and unpairing. */
export function PhoneDialog({ status, onRefresh, onClose }: Props) {
  const toasts = useToasts()
  const now = useNow()
  const devices = status?.devices ?? []

  const [code, setCode] = useState<PairingCode | null>(() =>
    status?.pairing && status.pairing.expiresAt > Date.now() ? status.pairing : null,
  )
  const [requesting, setRequesting] = useState(false)
  const [confirmingUnpair, setConfirmingUnpair] = useState(false)
  const [justPaired, setJustPaired] = useState<string | null>(null)
  const devicesWhenCodeShown = useRef(devices.length)

  const tick = useSecondTicker(code !== null)
  const remaining = code ? code.expiresAt - tick : 0
  const expired = code !== null && remaining <= 0

  // The server clears the code once a phone uses it; a new device means pairing worked.
  useEffect(() => {
    if (!code || !status) return
    if (status.devices.length > devicesWhenCodeShown.current && status.pairing?.code !== code.code) {
      const newest = [...status.devices].sort((a, b) => b.createdAt - a.createdAt)[0]
      setJustPaired(newest?.name ?? 'your iPhone')
      setCode(null)
    }
  }, [status, code])

  const requestCode = async () => {
    setRequesting(true)
    setJustPaired(null)
    try {
      devicesWhenCodeShown.current = devices.length
      setCode(await api.createPairingCode())
      onRefresh()
    } catch (error) {
      toasts.error(errorMessage(error))
    } finally {
      setRequesting(false)
    }
  }

  const unpairAll = async () => {
    try {
      await api.forgetDevices()
      setConfirmingUnpair(false)
      toasts.show({ message: 'All iPhones were unpaired.' })
      onRefresh()
    } catch (error) {
      toasts.error(errorMessage(error))
    }
  }

  return (
    <Dialog title="iPhone sync" onClose={onClose} className="dialog-phone">
      {justPaired && (
        <div className="pair-success" role="status">
          <CheckIcon /> Paired with {justPaired}. Cards will sync whenever StudyUp is open on the same Wi‑Fi.
        </div>
      )}

      {code ? (
        <div className="pairing">
          {expired ? (
            <>
              <p className="pairing-expired">This code has expired.</p>
              <button type="button" className="button button-primary" onClick={() => void requestCode()} data-autofocus>
                Get a new code
              </button>
            </>
          ) : (
            <>
              <p className="pairing-instructions">
                In StudyUp on your iPhone: <strong>Settings → Sync with Mac</strong> → enter this code
              </p>
              <div className="pairing-code" aria-label={`Pairing code ${code.code.split('').join(' ')}`}>
                <span>{code.code.slice(0, 3)}</span>
                <span>{code.code.slice(3)}</span>
              </div>
              <p className="pairing-countdown">
                Expires in {countdown(remaining)} · Your iPhone needs to be on the same Wi‑Fi as this Mac.
              </p>
              <button type="button" className="button button-quiet" onClick={() => setCode(null)}>
                Cancel
              </button>
            </>
          )}
        </div>
      ) : (
        <div className="pairing pairing-idle">
          <PhoneIcon width={28} height={28} className="pairing-icon" />
          <p className="pairing-instructions">
            {devices.length === 0
              ? 'Pair your iPhone to study the cards you write here. Edits sync both ways over Wi‑Fi.'
              : 'Pair another iPhone, or re-pair one after reinstalling StudyUp.'}
          </p>
          <button
            type="button"
            className="button button-primary"
            disabled={requesting}
            onClick={() => void requestCode()}
            data-autofocus
          >
            {requesting ? 'Getting a code…' : 'Pair an iPhone'}
          </button>
        </div>
      )}

      <section className="devices" aria-label="Paired iPhones">
        <h3 className="section-label">Paired iPhones</h3>
        {devices.length === 0 ? (
          <p className="devices-empty">No iPhones paired yet.</p>
        ) : (
          <ul className="device-list">
            {devices.map((device, i) => (
              <li key={`${device.name}-${device.createdAt}-${i}`} className="device">
                <PhoneIcon />
                <div className="device-text">
                  <span className="device-name">{device.name}</span>
                  <span className="device-detail">
                    {device.lastSyncAt ? `Last synced ${timeAgo(device.lastSyncAt, now)}` : 'Not synced yet'}
                    {' · '}paired {formatDate(device.createdAt)}
                  </span>
                </div>
              </li>
            ))}
          </ul>
        )}
        {devices.length > 0 && (
          confirmingUnpair ? (
            <div className="unpair-confirm">
              <span>Unpair every iPhone? They stop syncing until you pair them again. Cards on this Mac aren’t affected.</span>
              <div className="unpair-buttons">
                <button type="button" className="button button-small" onClick={() => setConfirmingUnpair(false)}>Cancel</button>
                <button type="button" className="button button-small button-danger" onClick={() => void unpairAll()}>Unpair all</button>
              </div>
            </div>
          ) : (
            <button type="button" className="link-button link-button-danger" onClick={() => setConfirmingUnpair(true)}>
              Unpair all…
            </button>
          )
        )}
      </section>
      {status && <p className="dialog-hint">This Mac appears to your iPhone as “{status.serverName}”.</p>}
    </Dialog>
  )
}
