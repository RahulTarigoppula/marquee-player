// The ticket office sign-in (§4.5): underline-only inputs; the JWT is sealed at rest and the
// password is never kept — the field is cleared the moment the request is made.
import { h } from './dom'

export interface SignInOptions {
  /** Resolves to null on success, or one plain sentence on failure. */
  onSubmit(username: string, password: string, sessionOnly: boolean): Promise<string | null>
  onSignOut(): void
  onClose(): void
}

export interface SignInView {
  el: HTMLElement
  open(signedInAs: string | null): void
  close(): void
  readonly isOpen: boolean
}

export function signIn(o: SignInOptions, strip: HTMLElement): SignInView {
  const user = h('input', {
    class: 'field',
    name: 'username',
    autocomplete: 'username',
    required: true,
    'aria-label': 'OpenSubtitles username',
  })
  const pass = h('input', {
    class: 'field',
    name: 'password',
    type: 'password',
    autocomplete: 'current-password',
    required: true,
    'aria-label': 'Password',
  })
  const sessionOnly = h('input', { type: 'checkbox', name: 'session-only' })
  const err = h('p', { class: 'office__err', role: 'status' })
  const submit = h('button', { class: 'btn', type: 'submit' }, 'Sign in')
  const who = h('p', { class: 'sentence' })
  const out = h('button', { class: 'linkbtn', type: 'button' }, 'Sign out')
  const close = h('button', { class: 'linkbtn', type: 'button' }, 'Back to the house')

  const form = h(
    'form',
    { class: 'office__card', 'aria-labelledby': 'office-title' },
    h('h2', { class: 'office__title', id: 'office-title' }, 'Ticket office'),
    h(
      'p',
      { class: 'sentence' },
      'Sign in with your free OpenSubtitles account to download subtitles here.',
    ),
    who,
    h('div', { class: 'searchwrap' }, user),
    h('div', { class: 'searchwrap' }, pass),
    h(
      'label',
      { class: 'check' },
      sessionOnly,
      'This session only — never write the ticket to this device',
    ),
    err,
    h('div', { class: 'office__row' }, submit, out, close),
    strip,
  )
  const el = h(
    'section',
    {
      class: 'office',
      hidden: true,
      role: 'dialog',
      'aria-modal': 'true',
      'aria-labelledby': 'office-title',
    },
    form,
  )

  form.addEventListener('submit', async (e) => {
    e.preventDefault()
    const password = pass.value
    pass.value = '' // the password is never kept
    submit.disabled = true
    err.textContent = ''
    const sentence = await o.onSubmit(user.value.trim(), password, sessionOnly.checked)
    submit.disabled = false
    err.textContent = sentence ?? ''
    for (const w of form.querySelectorAll('.searchwrap'))
      w.classList.toggle('is-bad', sentence !== null)
  })
  out.addEventListener('click', o.onSignOut)
  close.addEventListener('click', o.onClose)
  el.addEventListener('keydown', (e) => {
    if (e.key === 'Escape') {
      e.stopPropagation()
      o.onClose()
    }
  })

  return {
    el,
    get isOpen() {
      return !el.hidden
    },
    open(signedInAs) {
      el.hidden = false
      who.textContent = signedInAs ? `Signed in as ${signedInAs}.` : ''
      out.hidden = signedInAs === null
      err.textContent = ''
      user.focus()
    },
    close() {
      el.hidden = true
    },
  }
}
