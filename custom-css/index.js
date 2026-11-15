/**
 * Host half of the Custom CSS bundle.
 *
 * The stylesheet lives in this package as a plain file, so the browser half cannot
 * import it: client bundles are built artifacts and the `/plugins/.../assets/` route
 * only answers images. Instead this half publishes the file over the Web server:
 *
 *   GET /custom-css/user.css        -> custom.css, read from disk on every request
 *   GET /custom-css/assets/<path>   -> an image or font kept in the assets/ folder
 *
 * Because every request re-reads the file, saving custom.css needs neither a Host
 * restart nor a bundle rebuild. The browser half polls the first route and replaces
 * its injected <style> when the text changes.
 */
import { readFile, stat } from 'node:fs/promises'
import { dirname, extname, isAbsolute, join, relative } from 'node:path'
import { fileURLToPath } from 'node:url'

export const name = '@local/custom-css'
export const inject = ['webServer']

/** The stylesheet this bundle publishes; point it elsewhere with DSH_CUSTOM_CSS_FILE. */
const CSS_FILE = process.env.DSH_CUSTOM_CSS_FILE
  ? process.env.DSH_CUSTOM_CSS_FILE
  : join(dirname(fileURLToPath(import.meta.url)), 'custom.css')

/** Absolute directory assets are resolved against: an `assets` folder beside the stylesheet. */
const ASSET_ROOT = join(dirname(CSS_FILE), 'assets')

/** URL seats; the browser half requests CSS_ROUTE and nothing else by itself. */
const CSS_ROUTE = '/custom-css/user.css'
const ASSET_ROUTE = '/custom-css/assets'
const STATUS_ROUTE = '/custom-css/status'

const CSS_TYPE = 'text/css; charset=utf-8'

/** Extensions served beside the stylesheet; anything else is refused. */
const MEDIA_TYPES = {
  '.png': 'image/png',
  '.jpg': 'image/jpeg',
  '.jpeg': 'image/jpeg',
  '.gif': 'image/gif',
  '.webp': 'image/webp',
  '.svg': 'image/svg+xml',
  '.ico': 'image/x-icon',
  '.woff': 'font/woff',
  '.woff2': 'font/woff2',
  '.ttf': 'font/ttf',
  '.otf': 'font/otf',
}

/** Per-process counters behind GET /custom-css/status: proof the browser half polls. */
const stats = { cssRequests: 0, assetRequests: 0, lastCssRequestAt: null, lastAssetRequestAt: null }

/** Headers every response carries; the file is re-read, so nothing may be cached. */
function headers(type, file) {
  return {
    'content-type': type,
    'cache-control': 'no-store',
    // Header values are latin-1, so a path outside ASCII is transported encoded.
    'x-custom-css-file': encodeURIComponent(file),
  }
}

export function apply(ctx) {
  ctx.effect(
    () => ctx.webServer.register({
      kind: 'exact',
      path: CSS_ROUTE,
      resource: async () => {
        stats.cssRequests += 1
        stats.lastCssRequestAt = new Date().toISOString()
        let text
        try {
          text = await readFile(CSS_FILE, 'utf8')
        } catch (error) {
          if (error?.code === 'ENOENT') {
            return new Response(`/* custom.css not found: ${CSS_FILE} */`, {
              status: 404,
              headers: headers(CSS_TYPE, CSS_FILE),
            })
          }
          return new Response(`/* custom.css could not be read: ${error?.message ?? error} */`, {
            status: 500,
            headers: headers(CSS_TYPE, CSS_FILE),
          })
        }
        return new Response(text, { status: 200, headers: headers(CSS_TYPE, CSS_FILE) })
      },
    }),
    'custom-css: stylesheet route',
  )

  ctx.effect(
    () => ctx.webServer.register({
      kind: 'prefix',
      path: ASSET_ROUTE,
      resource: async (request) => {
        stats.assetRequests += 1
        stats.lastAssetRequestAt = new Date().toISOString()
        const target = resolveAsset(new URL(request.url).pathname)
        if (target === null) {
          return new Response('/* not an asset of custom.css */', {
            status: 404,
            headers: { 'content-type': CSS_TYPE, 'cache-control': 'no-store' },
          })
        }
        try {
          const bytes = await readFile(target)
          return new Response(bytes, {
            status: 200,
            headers: headers(MEDIA_TYPES[extname(target).toLowerCase()], target),
          })
        } catch {
          return new Response('/* asset not found */', {
            status: 404,
            headers: { 'content-type': CSS_TYPE, 'cache-control': 'no-store' },
          })
        }
      },
    }),
    'custom-css: asset route',
  )

  ctx.effect(
    () => ctx.webServer.register({
      kind: 'exact',
      path: STATUS_ROUTE,
      resource: async () => {
        let bytes = null
        try {
          bytes = (await stat(CSS_FILE)).size
        } catch {
          bytes = null
        }
        const body = JSON.stringify({ file: CSS_FILE, bytes, ...stats }, null, 2)
        return new Response(body, {
          status: 200,
          headers: { 'content-type': 'application/json; charset=utf-8', 'cache-control': 'no-store' },
        })
      },
    }),
    'custom-css: status route',
  )
}

/**
 * Map a request pathname to a file under {@link ASSET_ROOT}.
 * Returns null for a path that escapes the folder or names a refused extension.
 */
function resolveAsset(pathname) {
  if (!pathname.startsWith(ASSET_ROUTE + '/')) return null
  const encoded = pathname.slice(ASSET_ROUTE.length + 1)
  if (encoded === '') return null

  let decoded
  try {
    decoded = decodeURIComponent(encoded)
  } catch {
    return null
  }
  if (decoded.includes('\0')) return null

  const target = join(ASSET_ROOT, decoded)
  const within = relative(ASSET_ROOT, target)
  if (within === '' || within.startsWith('..') || isAbsolute(within)) return null
  if (!MEDIA_TYPES[extname(target).toLowerCase()]) return null
  return target
}
