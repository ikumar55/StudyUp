import { StrictMode } from 'react'
import { createRoot } from 'react-dom/client'
import { App } from './App.tsx'
import { ClockProvider } from './clock.tsx'
import { ToastProvider } from './toasts.tsx'
import './styles/base.css'
import './styles/layout.css'
import './styles/cards.css'
import './styles/dialogs.css'

createRoot(document.getElementById('root')!).render(
  <StrictMode>
    <ClockProvider>
      <ToastProvider>
        <App />
      </ToastProvider>
    </ClockProvider>
  </StrictMode>,
)
