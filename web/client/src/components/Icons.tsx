// Small stroke icons drawn at 16px; they take the current text color.

import type { ReactNode, SVGProps } from 'react'

function Icon({ children, ...props }: SVGProps<SVGSVGElement> & { children: ReactNode }) {
  return (
    <svg
      width="16"
      height="16"
      viewBox="0 0 16 16"
      fill="none"
      stroke="currentColor"
      strokeWidth="1.5"
      strokeLinecap="round"
      strokeLinejoin="round"
      aria-hidden="true"
      focusable="false"
      {...props}
    >
      {children}
    </svg>
  )
}

type P = SVGProps<SVGSVGElement>

export const ChevronIcon = (p: P) => <Icon {...p}><path d="M6 4l4 4-4 4" /></Icon>
export const PlusIcon = (p: P) => <Icon {...p}><path d="M8 3v10M3 8h10" /></Icon>
export const MoreIcon = (p: P) => (
  <Icon {...p} fill="currentColor" stroke="none">
    <circle cx="3.5" cy="8" r="1.25" /><circle cx="8" cy="8" r="1.25" /><circle cx="12.5" cy="8" r="1.25" />
  </Icon>
)
export const SearchIcon = (p: P) => <Icon {...p}><circle cx="7" cy="7" r="4.25" /><path d="M10.25 10.25L13.5 13.5" /></Icon>
export const FolderIcon = (p: P) => (
  <Icon {...p}><path d="M2 4.5A1.5 1.5 0 0 1 3.5 3h2.6l1.4 1.5h5A1.5 1.5 0 0 1 14 6v5.5a1.5 1.5 0 0 1-1.5 1.5h-9A1.5 1.5 0 0 1 2 11.5z" /></Icon>
)
export const PhoneIcon = (p: P) => <Icon {...p}><rect x="4.5" y="1.75" width="7" height="12.5" rx="1.75" /><path d="M7 12h2" /></Icon>
export const DownloadIcon = (p: P) => <Icon {...p}><path d="M8 2.5v7.5M4.75 7L8 10.25 11.25 7M3 13.25h10" /></Icon>
export const EditIcon = (p: P) => <Icon {...p}><path d="M10.5 2.75l2.75 2.75L6 12.75H3.25V10z" /></Icon>
export const TrashIcon = (p: P) => (
  <Icon {...p}><path d="M2.75 4.25h10.5M6.25 4.25V2.75h3.5v1.5M4 4.25l.6 8.6a1 1 0 0 0 1 .9h4.8a1 1 0 0 0 1-.9l.6-8.6" /></Icon>
)
export const MoveIcon = (p: P) => (
  <Icon {...p}><path d="M2 4.5A1.5 1.5 0 0 1 3.5 3h2.6l1.4 1.5h5A1.5 1.5 0 0 1 14 6v5.5a1.5 1.5 0 0 1-1.5 1.5h-9A1.5 1.5 0 0 1 2 11.5z" /><path d="M6 9h4M8.5 7.5L10 9l-1.5 1.5" /></Icon>
)
export const GripIcon = (p: P) => (
  <Icon {...p} fill="currentColor" stroke="none">
    <circle cx="6" cy="4" r="1" /><circle cx="10" cy="4" r="1" /><circle cx="6" cy="8" r="1" />
    <circle cx="10" cy="8" r="1" /><circle cx="6" cy="12" r="1" /><circle cx="10" cy="12" r="1" />
  </Icon>
)
export const CheckIcon = (p: P) => <Icon {...p}><path d="M3.5 8.5l3 3 6-7" /></Icon>
export const CloseIcon = (p: P) => <Icon {...p}><path d="M4 4l8 8M12 4l-8 8" /></Icon>
export const ImageIcon = (p: P) => (
  <Icon {...p}><rect x="2.5" y="3" width="11" height="10" rx="1.5" /><circle cx="6" cy="6.5" r="1" /><path d="M3 12l3.5-3.5 2.5 2.5 2-2 2.5 2.5" /></Icon>
)
export const RefreshIcon = (p: P) => (
  <Icon {...p}><path d="M12.5 5.5A5 5 0 1 0 13 9" /><path d="M13 2.5v3h-3" /></Icon>
)
export const KeyboardIcon = (p: P) => (
  <Icon {...p}><rect x="1.75" y="4" width="12.5" height="8" rx="1.5" /><path d="M4.5 6.75h.01M7 6.75h.01M9.5 6.75h.01M12 6.75h.01M5 9.5h6" /></Icon>
)
