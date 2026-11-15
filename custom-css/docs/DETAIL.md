# Custom CSS

Add your own CSS to the DSH Web GUI. The stylesheet is the plain file `custom.css`; the bundle injects its text into the page and re-applies it about a second after you save.

## Using it

1. Open `custom.css` and write your rules (the file ships with templates you can uncomment).
2. Save. The page updates about a second later — no restart and no reload.
3. To turn it off: Settings → Plugins → disable "Custom CSS"; the `<style>` element is removed immediately.

## Where the file is

- Default: `<package dir>/custom.css`.
- Elsewhere: set the environment variable `DSH_CUSTOM_CSS_FILE=<absolute path>` for the DSH process and restart it.

## How it works

- `index.js` (Host) registers two HTTP routes and re-reads the file on every request, so editing CSS never needs a Host restart:
  - `GET /custom-css/user.css` → the text of `custom.css`
  - `GET /custom-css/assets/<path>` → images and fonts from the `assets/` subfolder (png, jpg, gif, webp, svg, ico, woff, woff2, ttf, otf)
  - `GET /custom-css/status` → diagnostics JSON: the file path, its byte size, and per-route request counts and timestamps
- `client.js` (Browser) fetches the route, injects `<style data-dsh-custom-css>`, then polls once a second and swaps the text only when it changed. Each tick re-appends the element to the end of `<head>` so it stays the last stylesheet of the page. Polling pauses while the page is hidden.

Disabling or unloading the bundle removes the element, the timer and the listener (via the `ctx.effect` cleanup).

## Troubleshooting

- Open `http://127.0.0.1:60570/custom-css/status`: JSON means the Host half runs. Re-open it a few seconds later and `cssRequests` climbing by about one per second means the browser half is polling, i.e. the `<style>` is injected. `bytes` is your file's size.
- Open `http://127.0.0.1:60570/custom-css/user.css`:
  - CSS text → the Host half works; look for `[custom-css]` messages in the page console.
  - 404 with `/* custom.css not found: ... */` → wrong path; read the `x-custom-css-file` response header.
  - Nothing at all → the bundle is not loaded; check `dsh.profile.bundles` and `cordis.patch.yml`.
- On success the console prints `[custom-css] N characters loaded from /custom-css/user.css`.
- A rule does nothing: verify the selector exists (DevTools), then try `!important`. This stylesheet is already last, so it wins on equal specificity.

## Uninstalling

1. Settings → Plugins → disable "Custom CSS".
2. To remove it completely: drop `@local/custom-css` from `dsh.profile.bundles`, remove the dependency and the `node_modules/@local/custom-css` link, then reload.
