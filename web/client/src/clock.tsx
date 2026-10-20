import { createContext, useContext, useEffect, useState } from 'react'
import type { ReactNode } from 'react'

const NowContext = createContext(Date.now())

/** Provides a shared "now" that ticks, so relative times ("Due in 3d", "2 min ago") stay fresh. */
export function ClockProvider({ children, interval = 15_000 }: { children: ReactNode; interval?: number }) {
  const [now, setNow] = useState(Date.now)
  useEffect(() => {
    const timer = setInterval(() => setNow(Date.now()), interval)
    return () => clearInterval(timer)
  }, [interval])
  return <NowContext.Provider value={now}>{children}</NowContext.Provider>
}

export function useNow(): number {
  return useContext(NowContext)
}

/** A local clock that ticks every second while `active`, for countdowns. */
export function useSecondTicker(active: boolean): number {
  const [now, setNow] = useState(Date.now)
  useEffect(() => {
    if (!active) return
    setNow(Date.now())
    const timer = setInterval(() => setNow(Date.now()), 1000)
    return () => clearInterval(timer)
  }, [active])
  return now
}
