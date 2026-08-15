---
name: github-push
description: 把本地文件/文件夹推送到用户的 GitHub 仓库。自动条件分流：有 git 走 git push；没有 git 走 REST API 建仓+base64 直传；没有凭证时自动发起设备码授权（浏览器输入验证码即可，与 gh 登录同款），全程不做无谓的环境搜索。统一入口 scripts/push-github.ps1。
whenToUse: 用户要求推送到 GitHub、上传文件/文件夹到 GitHub 仓库、新建 GitHub 仓库或分享代码到 GitHub 时使用。
---

# GitHub 推送自动化

入口脚本 `scripts/push-github.ps1`（与本 SKILL.md 同目录）。**决策树由脚本自动完成，不要自行搜索环境**：
1. `-Action check` 一条命令报告 git/gh/token 状态与预计分支；
2. 有 git → 本地 init/commit/远程 push（凭证不足时自动转设备码）；
3. 无 git → GitHub REST API 建仓 + base64 上传文件；
4. 无 token → **设备码授权**：脚本输出形如 `ABCD-1234` 的验证码和 `https://github.com/login/device`，用户浏览器输入授权，脚本轮询拿到 token 自动继续。

## 用法（pwsh 工具；每个新进程先执行第一句）

```powershell
$s = Join-Path $env:DSH_HOME 'skills\github-push\scripts\push-github.ps1'
Set-ExecutionPolicy -Scope Process Bypass -Force

& $s -Action check
& $s -Action push -Path 'G:\项目目录' -Repo 'repo-name' -Visibility public   # 推整个目录
& $s -Action push -Path '单个文件.txt' -Repo 'repo-name'                     # 推单个文件
& $s -Action release -Path 'G:\项目目录' -Repo 'repo-name' -Tag 'v1.0.0' -Body '变更说明'   # 打 zip 发 Release
```

- **设备码流程会阻塞最长 15 分钟**：需要授权时用 `run_in_background` 跑推送，把脚本输出的验证码和网址立即告诉用户；用户授权后脚本自动继续，不必干预。
- token 优先级：`-TokenFile` 参数 → `$env:GH_PAT` → 工作目录 `.github-token.txt` → `%USERPROFILE%\.github-token.txt`。设备码成功后自动存到 `%USERPROFILE%\.github-token.txt`，下次直接复用。
- `-Owner` 可省略：脚本用 token 调 `GET /user` 自动识别账号；推他人/组织仓库时显式传 `-Owner`。
- `-Action release`：把 `-Path` 目录打成 `<Repo>-<Tag>.zip`，创建 Release（tag 取自 main）并上传 zip 资产；tag 已存在会 422，需换新版本号。
- 改过 push-github.ps1 后若报乱码解析错误：脚本必须带 UTF-8 BOM。补 BOM：`$p=$s; $c=[IO.File]::ReadAllText($p,[Text.UTF8Encoding]::new($false)); [IO.File]::WriteAllText($p,$c,[Text.UTF8Encoding]::new($true))`
- 排障细节：`references/troubleshooting.md`（设备码机制、PAT 创建、常见错误码）。
