# 自定义 CSS

给 DSH Web GUI 加一份自己写的 CSS。文件就是 `custom.css`，插件把它的内容注入页面，保存后约 1 秒自动重新应用。

## 怎么用

1. 打开 `custom.css`，写下你想改的规则（文件里有可以直接抄的模板）。
2. 保存。约 1 秒后页面就会变，不需要重启，也不需要刷新。
3. 想临时关掉：设置 → 插件 → 把「自定义 CSS」停用；页面里的 `<style>` 会立即移除。

## 文件去哪了

- 默认：`<插件目录>/custom.css`。
- 想放到别处：给 DSH 进程设置环境变量 `DSH_CUSTOM_CSS_FILE=<绝对路径>`，重启后生效。

## 它是怎么工作的

这个包有两半：

- `index.js`（Host）：注册两个 HTTP 路由。每次请求都重新读文件，所以改 CSS 不需要重启 Host。
  - `GET /custom-css/user.css` → `custom.css` 的原文
  - `GET /custom-css/assets/<path>` → `assets/` 子目录里的图片/字体（png、jpg、gif、webp、svg、ico、woff、woff2、ttf、otf）
  - `GET /custom-css/status` → 诊断 JSON：文件路径、字节数、各路由被请求的次数与最后时间
- `client.js`（Browser）：启动时读一次上面的路由，注入 `<style data-dsh-custom-css>`；之后每秒轮询，文本变了才替换，并且每次都把这个 `<style>` 移到 `<head>` 末尾，保证它是页面里最后一个样式表。页面隐藏时暂停轮询，切回来立刻刷新。

卸载或停用插件时，`<style>`、定时器和事件监听会一起移除（`ctx.effect` 的清理函数）。

## 排查

- 打开 `http://127.0.0.1:60570/custom-css/status`：能返回 JSON 说明 Host 半边在跑；隔几秒再打开，`cssRequests` 每次大约 +1 就说明浏览器半边正在轮询——也就是 `<style>` 已经注入。`bytes` 是你文件的大小。
- 在浏览器地址栏打开 `http://127.0.0.1:60570/custom-css/user.css`：
  - 能看到 CSS 原文 → Host 半边正常，问题在浏览器端，看控制台里 `[custom-css]` 开头的日志。
  - 404 且 body 是 `/* custom.css not found: ... */` → 文件路径不对，看响应头 `x-custom-css-file`。
  - 404 且没有任何路由响应 → 这个 bundle 没被加载，检查 profile 的 `dsh.profile.bundles` 和 `cordis.patch.yml`。
- 打开页面控制台，加载成功会打印 `[custom-css] N characters loaded from /custom-css/user.css`。
- 规则不生效：先确认选择器真的存在（打开开发者工具检查），再考虑加 `!important`；本文件的 `<style>` 已经是最后一个，同等优先级下会赢。

## 卸载

1. 设置 → 插件 → 停用「自定义 CSS」。
2. 彻底删除：从 profile 的 `dsh.profile.bundles` 里去掉 `@local/custom-css`，删掉依赖和 `node_modules/@local/custom-css` 链接，然后重载。
