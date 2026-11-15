/**
 * Browser half of the Custom CSS bundle.
 *
 * The Host half serves the stylesheet at /custom-css/user.css. This half injects the
 * text into a single <style data-dsh-custom-css> element, then polls the route once a
 * second and swaps the text when the file changes — so saving custom.css updates the
 * GUI without a reload, a rebuild or a restart.
 *
 * The element is re-appended to the end of <head> on every tick: the app injects its
 * own styles after boot, and only the last stylesheet of equal specificity wins.
 * Everything is registered as one ctx.effect, so disabling or unloading the bundle
 * removes the stylesheet, the timer and the listener.
 */
window.__ModuleLoader__.load({
  id: '@local/custom-css',
  factory() {
    const STYLESHEET_URL = '/custom-css/user.css'
    const POLL_INTERVAL_MS = 1000

    return {
      apply(ctx) {
        ctx.effect(() => {
          let disposed = false
          let warned = false
          let announced = false
          let lastText = null
          let timer = null
          let inFlight = false

          const parent = () => document.head || document.documentElement

          const style = document.createElement('style')
          style.setAttribute('data-dsh-custom-css', '')
          parent()?.appendChild(style)

          function placeLast() {
            const target = parent()
            if (!target) return
            if (target.lastElementChild !== style) target.appendChild(style)
          }

          function commit(text) {
            lastText = text
            if (style.textContent !== text) style.textContent = text
            if (text.trim() !== '') placeLast()
            if (!announced) {
              announced = true
              console.info(`[custom-css] ${text.length} characters loaded from ${STYLESHEET_URL}`)
            }
          }

          async function refresh() {
            if (disposed || inFlight) return
            inFlight = true
            try {
              const response = await fetch(STYLESHEET_URL, { cache: 'no-store' })
              if (!response.ok) {
                if (!warned) {
                  warned = true
                  console.warn(
                    `[custom-css] ${STYLESHEET_URL} answered HTTP ${response.status}; `
                    + 'is the @local/custom-css bundle loaded and enabled?',
                  )
                }
                return
              }
              warned = false
              const text = await response.text()
              if (disposed) return
              if (text !== lastText) commit(text)
              else placeLast()
            } catch (error) {
              if (!warned) {
                warned = true
                console.warn(`[custom-css] could not read ${STYLESHEET_URL}`, error)
              }
            } finally {
              inFlight = false
            }
          }

          function start() {
            if (timer !== null) return
            timer = window.setInterval(() => {
              if (!document.hidden) refresh()
            }, POLL_INTERVAL_MS)
          }

          function stop() {
            if (timer === null) return
            window.clearInterval(timer)
            timer = null
          }

          const onVisibilityChange = () => {
            if (document.hidden) stop()
            else {
              start()
              refresh()
            }
          }

          document.addEventListener('visibilitychange', onVisibilityChange)
          refresh()
          start()

          return () => {
            disposed = true
            document.removeEventListener('visibilitychange', onVisibilityChange)
            stop()
            style.remove()
          }
        }, 'custom-css: stylesheet')
      },
    }
  },
})
