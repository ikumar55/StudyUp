// Browser-side image helpers. The reference syntax itself is in shared/images.ts.

export { imageIDs, imageSnippet } from '../../shared/images.ts'

/** Where the browser loads an image reference from. */
export function imageURL(reference: string): string | null {
  const match = /^image:([0-9a-fA-F-]{36})$/.exec(reference)
  return match ? `/api/images/${match[1].toLowerCase()}` : null
}

/** Longest side kept for stored images: sharp on a Retina phone, without multi-megabyte files. */
const MAX_DIMENSION = 2000

/**
 * Prepares a pasted or dropped image for upload: large images (such as Retina screenshots) are scaled
 * down and re-encoded as WebP, which keeps text in screenshots crisp at a fraction of the PNG size.
 * Small images, and GIFs (which may be animated), are kept as they are.
 */
export async function prepareImage(file: Blob): Promise<Blob> {
  if (file.type === 'image/gif') return file
  let bitmap: ImageBitmap
  try {
    bitmap = await createImageBitmap(file)
  } catch {
    throw new Error('That file couldn’t be read as an image.')
  }
  const scale = Math.min(1, MAX_DIMENSION / Math.max(bitmap.width, bitmap.height))
  const width = Math.round(bitmap.width * scale)
  const height = Math.round(bitmap.height * scale)
  const canvas = document.createElement('canvas')
  canvas.width = width
  canvas.height = height
  canvas.getContext('2d')!.drawImage(bitmap, 0, 0, width, height)
  bitmap.close()
  const encoded = await new Promise<Blob | null>((resolve) => canvas.toBlob(resolve, 'image/webp', 0.9))
  // Keep the original when re-encoding doesn't help (e.g. a small, already-compressed JPEG).
  if (!encoded || (scale === 1 && encoded.size >= file.size && isSupported(file.type))) return file
  return encoded
}

function isSupported(type: string): boolean {
  return ['image/png', 'image/jpeg', 'image/webp', 'image/gif'].includes(type)
}

/** The image files carried by a paste or drop, if any. */
export function imageFiles(data: DataTransfer | null): File[] {
  if (!data) return []
  return [...data.files].filter((file) => file.type.startsWith('image/'))
}
