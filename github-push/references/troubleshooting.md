# GitHub 推送 skill — 机制与排障参考（按需阅读，不常驻上下文）

## 三条分支的机制

### Release（`-Action release`）
- `Compress-Archive` 把目标目录打成 `<Repo>-<Tag>.zip`（临时目录）。
- `POST /repos/{owner}/{repo}/releases`（body: tag_name/name/body）→ 返回 release id；tag 已存在会 422。
- 资产上传：`POST https://uploads.github.com/repos/{owner}/{repo}/releases/{id}/assets?name=<zip>`，Content-Type `application/zip`，body 为 zip 原始字节（PS5.1 用 WebClient.UploadFile 实现，因 Invoke-RestMethod 无 -InFile）。
- 账号识别：`-Owner` 省略时用 token 调 `GET /user` 取 login。

### A. 有 git
- 目录不是仓库则 `git init -b main`（旧版 git 退回 init+checkout），缺 user.name/email 时用 `owner@users.noreply.github.com` 就地补。
- remote 缺失时添加 `https://github.com/<owner>/<repo>.git`。
- 有 token 时把 `https://x-access-token:<token>@github.com` 写入 `%USERPROFILE%\.git-credentials` 并 `git config --global credential.helper store`，避免 URL 明文传 token。
- 首次 push 失败（含认证/仓库不存在）→ 无 token 则转设备码授权 → 建仓 → 重试一次。

### B. 无 git（REST API 直传）
- 建仓：`POST https://api.github.com/user/repos`（409/422=已存在则跳过）。
- 传文件：`PUT /repos/{owner}/{repo}/contents/{path}`，body 为 `{message, content(base64), branch:'main'}`；文件已存在时必须带 `sha`（先 GET 取）。跳过 `.git` 目录与 `.github-token.txt`。
- 单文件 >100MB 会被 API 拒绝（改用 git LFS 或 git 分支）。

### C. 设备码授权（用户口中的“输入验证码”方式）
- 第一步 `POST https://github.com/login/device/code`，body `{client_id, scope:'repo'}` → `{device_code, user_code, verification_uri, expires_in:900, interval:5}`。
- 用户到 `https://github.com/login/device` 输入 `user_code` 并授权。
- 脚本按 interval 轮询 `POST https://github.com/login/oauth/access_token`，body `{client_id, device_code, grant_type:'urn:ietf:params:oauth:grant-type:device_code'}`：
  - 成功返回 `access_token`（gho_ 开头，scope=repo）→ 存 `%USERPROFILE%\.github-token.txt`；
  - `authorization_pending` 继续等；`slow_down` 间隔 +5s；`expired_token`/`access_denied` 失败。
- 所用 `client_id = Iv1.b507a08c87ecfe98` 是 GitHub CLI 的官方 OAuth 应用（公共客户端，设备码流程无需密钥）。若 GitHub 变更导致失败：改用经典 PAT（见下），或自建 OAuth App 替换 client_id。

## 常见问题

- `check` 显示无 git 但用户机器其实装了：git 不在 PATH。可让用户装 git 或用分支 B（API 直传效果等同推送）。
- 401/403：token 无效/过期/权限不足。经典 PAT 需勾 `repo`；细粒度 PAT **不能建仓**，只适合仓库已存在时传文件（Contents: Read and write）。
- 404：仓库不存在且 token 无权建仓，或路径拼错。
- 422：仓库名不合法（需 kebab-case，如 `my-repo`）或已存在同名仓库。
- 设备码授权后仍超时：轮询间隔没跟上 `slow_down`；或用户在未登录状态下输码。
- token 泄漏风险：脚本从不 echo token；`ghp_/gho_` 开头字符串不要写进会被推送的文件；推送完可删除本地 token 文件或到 GitHub Settings 吊销。
- 改脚本丢 BOM 导致中文乱码解析错误：用 SKILL.md 里的补 BOM 命令。

## 备注

- 设备码授权产出的 token 与经典 PAT 用法一致（repo 权限），可长期复用直到吊销。
- API 直传不产生本地 .git 历史；要版本历史请装 git 走分支 A。
