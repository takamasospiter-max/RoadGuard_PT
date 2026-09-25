import axios, { AxiosError } from 'axios'

// Shared axios instance for talking to the Django REST API (new-backend/).
// Every call goes through this instead of calling axios directly so the base
// URL, JSON headers, and `withCredentials` (required for cookies to be
// sent/received cross-origin — see CORS_ALLOW_CREDENTIALS in
// new-backend/config/settings.py) are never something a caller can forget.
//
// API_URL is the project's ONE base URL: the server address plus the
// backend's API prefix (settings.API_PREFIX, "api/v1/"). Every request path
// in src/lib/*.ts is relative to it, e.g. '/defects/' → .../api/v1/defects/.
// Override it with VITE_API_URL in .env (see .env.example).
const API_URL = import.meta.env.VITE_API_URL ?? 'http://localhost:8000/api/v1'

export const api = axios.create({
  baseURL: API_URL,
  withCredentials: true,
  headers: { 'Content-Type': 'application/json' },
})

export class ApiError extends Error {
  status: number

  constructor(message: string, status: number) {
    super(message)
    this.status = status
  }
}

// DRF sends errors in two shapes: `{"detail": "..."}` (404, 403, ...) and,
// for a 400 validation failure, `{"field": ["message", ...], ...}`. Both are
// flattened into one readable message for the UI's error banners.
function errorMessage(data: unknown): string {
  if (data && typeof data === 'object') {
    const body = data as Record<string, unknown>
    if (typeof body.detail === 'string') return body.detail
    const messages = Object.entries(body).map(([field, value]) => {
      const text = Array.isArray(value) ? value.join(' ') : String(value)
      return field === 'non_field_errors' ? text : `${field}: ${text}`
    })
    if (messages.length) return messages.join(' ')
  }
  return 'Something went wrong'
}

// Turns every failed request into an ApiError, which is what the pages
// already catch (`err instanceof ApiError`) to show a message.
api.interceptors.response.use(
  (res) => res,
  (err: AxiosError) => {
    if (err.response) {
      return Promise.reject(new ApiError(errorMessage(err.response.data), err.response.status))
    }
    return Promise.reject(new ApiError('Could not reach the server', 0))
  },
)

export async function apiGet<T>(path: string): Promise<T> {
  const res = await api.get<T>(path)
  return res.data
}

export async function apiPost<T>(path: string, body?: unknown): Promise<T> {
  const res = await api.post<T>(path, body)
  return res.data
}

export async function apiPatch<T>(path: string, body: unknown): Promise<T> {
  const res = await api.patch<T>(path, body)
  return res.data
}
