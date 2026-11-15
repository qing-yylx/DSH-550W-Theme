# @local/custom-css

把自己的 CSS 注入 DSH Web GUI 的本地插件。改 `custom.css` 保存，约 1 秒后生效——不重启、不刷新、不重新构建。

- 样式文件：`custom.css`（就是这个目录下的文件）
- 图片/字体：放进 `assets/` 子目录，CSS 里写 `url(/custom-css/assets/文件名)`
- 停用：设置 → 插件 → 停用「自定义 CSS」

## 目录

| 文件 | 作用 |
| --- | --- |
| `custom.css` | 你写规则的地方 |
| `assets/` | 壁纸、字体等本地素材（按 URL 文件名即可引用） |
| `index.js` | Host 半边：`GET /custom-css/user.css` 和 `GET /custom-css/assets/*`，每次请求重读磁盘 |
| `client.js` | Browser 半边：注入 `<style data-dsh-custom-css>`，每秒轮询并在文本变化时替换 |
| `package.json` | `dsh.bundle.patch` + `dsh.client` 声明 |
| `cordis.patch.yml` | 把 `custom-css` 条目插进 cordis 配置 |
| `icon.svg` / `locale/` / `docs/` | 插件页的图标、标题与说明 |

详细原理、排查步骤和卸载方式见 [docs/DETAIL.zh.md](docs/DETAIL.zh.md)；英文版见 [docs/DETAIL.md](docs/DETAIL.md)。

## 为什么要有 Host 半边

客户端 bundle 是构建产物，`/plugins/<pkg>/assets/*` 只发图片，所以 CSS 没法当静态资源读。Host 半边把文件挂在 HTTP 路由上，每次请求重新读，浏览器半边就能用普通 `fetch` 拿到最新内容——这样改样式既不需要重建 bundle，也不需要重启 Host。

## 当前样式

`custom.css` 现在做的是「550W 壁纸 + 半透明面板」：

- 壁纸文件：`assets/550w.png`（7680×4320），CSS 里写 `url('/custom-css/assets/550w.png')`
- 壁纸铺在 `html` 画布上，上面叠一层压暗渐变（`rgba(4, 5, 9, 0.62)` → `0.75`）；改这两个 alpha 就能让壁纸更亮或更淡
- 面板颜色改用主题语义变量（`--dsw-alias-bg-base`、`--dsw-alias-bg-layer-1|2|3`、`--dsw-specific-sidebar-fill` 等）的半透明版本，深色与浅色主题各一套

换图只需把新图丢进 `assets/`，再改 `custom.css` 里那一行 `url(...)`。

## 换一个文件

给 DSH 进程设置环境变量 `DSH_CUSTOM_CSS_FILE=<绝对路径>`（重启后生效）。资源路由会自动跟着换到那个文件旁边的 `assets/` 目录。

## 自检

- `http://127.0.0.1:<端口>/custom-css/status`：返回 JSON 就说明 Host 半边在跑；隔几秒再看，`cssRequests` 大约每秒 +1 说明页面里的 `<style>` 正在轮询并生效（端口是当前 GUI 的端口，见窗口地址）。
- `http://127.0.0.1:<端口>/custom-css/user.css`：直接看到你的 CSS 原文。

## 改了 JS 之后

只改 `custom.css` 不需要做任何事。改了 `index.js` / `client.js` 则要让插件重载：设置 → 插件 → 关掉再打开「自定义 CSS」（不必重启 Desktop）。

## 安装到 profile

把本目录放到任意位置（例如 `%USERPROFILE%\dsh-plugins\custom-css`），然后让 profile 认识它：依赖里加一条 `link:` 指向本目录，bundle 列表里加上 `@local/custom-css`，并在 `node_modules/@local/custom-css` 建一个指向本目录的 Junction。改完重载 profile，插件才会进进程。

Windows 上可以直接运行 `install.ps1`（自动完成上面的步骤，改完重启 DSH 即可），卸载用 `uninstall.ps1`。
