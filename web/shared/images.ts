// Images live in card text as `![](image:<id>)`, the same syntax on the Mac and the iPhone
// (StudyUp/Content/ImageStore.swift). The files are stored and synced separately.

const REFERENCE = /!\[[^\]]*\]\(image:([0-9a-fA-F-]{36})\)/g

export function imageSnippet(id: string): string {
  return `![](image:${id})`
}

/** The ids of the images a card's text refers to. */
export function imageIDs(text: string): string[] {
  return [...text.matchAll(REFERENCE)].map((match) => match[1].toLowerCase())
}
