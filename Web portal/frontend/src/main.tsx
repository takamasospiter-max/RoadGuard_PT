import { QueryClient, QueryClientProvider } from '@tanstack/react-query'
// Leaflet's own stylesheets — required for the map (base) and the marker
// clustering plugin (cluster bubbles) to render/position correctly.
import 'leaflet/dist/leaflet.css'
import 'leaflet.markercluster/dist/MarkerCluster.css'
import 'leaflet.markercluster/dist/MarkerCluster.Default.css'
import { StrictMode } from 'react'
import { createRoot } from 'react-dom/client'
import { BrowserRouter } from 'react-router-dom'
import App from './App.tsx'
import { AuthProvider } from './context/AuthContext.tsx'
import './index.css'

// TanStack Query client — every page now reads/writes the real backend
// through this (see src/lib/*.ts). DataContext, which used to hold mock
// defects/users/authorities in memory, has been fully retired — nothing
// reads mock data anymore.
const queryClient = new QueryClient()

// App entry point. QueryClientProvider and BrowserRouter wrap everything,
// then AuthProvider so App (and every page inside it) can call useAuth().
createRoot(document.getElementById('root')!).render(
  <StrictMode>
    <QueryClientProvider client={queryClient}>
      <BrowserRouter>
        <AuthProvider>
          <App />
        </AuthProvider>
      </BrowserRouter>
    </QueryClientProvider>
  </StrictMode>,
)
