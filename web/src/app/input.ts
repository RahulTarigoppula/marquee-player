// Page-wide input: the keyboard, files dropped anywhere, and files the OS hands an installed
// Lite ("Open with…", file_handlers in the manifest).

export interface KeyboardDeps {
  /** Esc: go exactly one lighting state up. */
  onEscape(): void
  /** A dialog is open: the player keys stay off. */
  blocked(): boolean
  /** The player is showing: let it handle the key. */
  onPlayerKey(e: KeyboardEvent): void
}

export function installKeyboard(d: KeyboardDeps): void {
  document.addEventListener('keydown', (e) => {
    if (e.defaultPrevented) return
    if (e.key === 'Escape') {
      d.onEscape()
      return
    }
    const t = e.target
    const typing =
      (t instanceof HTMLInputElement && !['range', 'checkbox', 'file'].includes(t.type)) ||
      t instanceof HTMLSelectElement ||
      t instanceof HTMLTextAreaElement
    if (typing || d.blocked()) return
    // The volume slider keeps its own arrow keys.
    if (t instanceof HTMLInputElement && t.type === 'range' && e.key.startsWith('Arrow')) return
    d.onPlayerKey(e)
  })
}

/**
 * preventDefault on every dragover/drop: otherwise a film dropped beside the frame makes the
 * browser navigate away to play it.
 */
export function installDrop(onFiles: (files: File[]) => void, setDragging: (on: boolean) => void) {
  let depth = 0
  const carriesFiles = (e: DragEvent) => e.dataTransfer?.types.includes('Files') === true
  window.addEventListener('dragenter', (e) => {
    if (!carriesFiles(e)) return
    depth++
    setDragging(true)
  })
  window.addEventListener('dragover', (e) => {
    e.preventDefault()
    if (e.dataTransfer) e.dataTransfer.dropEffect = carriesFiles(e) ? 'copy' : 'none'
  })
  window.addEventListener('dragleave', () => {
    depth = Math.max(0, depth - 1)
    if (depth === 0) setDragging(false)
  })
  window.addEventListener('drop', (e) => {
    e.preventDefault()
    depth = 0
    setDragging(false)
    const files = [...(e.dataTransfer?.files ?? [])]
    if (files.length > 0) onFiles(files)
  })
}

interface LaunchParamsLike {
  files: readonly FileSystemFileHandle[]
}

export function installLaunchQueue(onFiles: (files: File[]) => void): void {
  const launchQueue = (
    window as unknown as {
      launchQueue?: { setConsumer(cb: (p: LaunchParamsLike) => void): void }
    }
  ).launchQueue
  launchQueue?.setConsumer((p) => {
    void Promise.all(p.files.map((f) => f.getFile())).then((files) => {
      if (files.length > 0) onFiles(files)
    })
  })
}
