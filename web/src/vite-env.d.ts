/// <reference types="vite/client" />

interface ImportMetaEnv {
  readonly VITE_API_BASE?: string
  readonly VITE_APP_VERSION?: string
  readonly VITE_RELEASES_URL?: string
}

interface ImportMeta {
  readonly env: ImportMetaEnv
}
