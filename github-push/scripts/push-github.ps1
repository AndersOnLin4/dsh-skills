# GitHub 推送自动化脚本（条件分流：git / REST API / 设备码授权；release 打包发布）
# 用法见同目录 SKILL.md；token 优先从 -TokenFile/$env:GH_PAT/工作区/.github-token.txt/用户目录/.github-token.txt 读取

param(
    [ValidateSet('check','push','release')]
    [string]$Action = 'push',
    [string]$Owner = '',
    [string]$Repo = '',
    [string]$Path = '.',
    [ValidateSet('public','private')]
    [string]$Visibility = 'public',
    [string]$Message = 'update via dsh github-push skill',
    [string]$Tag = '',
    [string]$Body = '',
    [string]$TokenFile = ''
)
$ErrorActionPreference = 'Stop'

function Find-Git {
    $g = Get-Command git -ErrorAction SilentlyContinue
    if ($g) { return $g.Source }
    return $null
}

function Get-Token {
    if ($env:GH_PAT -and $env:GH_PAT.Length -ge 20) { return $env:GH_PAT }
    $cands = @()
    if ($TokenFile) { $cands += $TokenFile }
    $cands += (Join-Path (Get-Location).Path '.github-token.txt')
    $cands += (Join-Path $env:USERPROFILE '.github-token.txt')
    foreach ($f in $cands) {
        if (Test-Path -LiteralPath $f) {
            $t = (Get-Content -LiteralPath $f -Raw -ErrorAction SilentlyContinue).Trim()
            if ($t -and $t.Length -ge 20) { return $t }
        }
    }
    return $null
}

function New-Headers($token) {
    $h = @{ 'User-Agent' = 'dsh-github-push'; 'Accept' = 'application/vnd.github+json' }
    if ($token) { $h['Authorization'] = "Bearer $token" }
    return $h
}

function Get-Api($uri, $token) {
    try { return Invoke-RestMethod -Uri $uri -Headers (New-Headers $token) -TimeoutSec 15 }
    catch { return $null }
}

function Resolve-Owner($token) {
    if ($Owner) { return $Owner }
    if ($token) {
        $u = Get-Api 'https://api.github.com/user' $token
        if ($u -and $u.login) { return $u.login }
    }
    throw '需要 -Owner 参数（未提供且无法从 token 自动识别账号）'
}

function Start-DeviceFlow {
    # 设备码授权：与 gh auth login 同款流程（公共 OAuth 客户端，无需密钥）
    $clientId = 'Iv1.b507a08c87ecfe98'
    $body = @{ client_id = $clientId; scope = 'repo' } | ConvertTo-Json
    $dc = $null
    try {
        $dc = Invoke-RestMethod -Uri 'https://github.com/login/device/code' -Method Post -Headers (New-Headers $null) -ContentType 'application/json' -Body $body -TimeoutSec 20
    } catch {
        throw "设备码申请失败: $($_.Exception.Message)（检查网络/代理；仍不行就用经典 PAT：https://github.com/settings/tokens/new 勾选 repo 后写入 .github-token.txt）"
    }
    Write-Output ''
    Write-Output '=========== GitHub 授权（设备码） ==========='
    Write-Output "请在浏览器打开: $($dc.verification_uri)"
    Write-Output "输入验证码:        $($dc.user_code)"
    Write-Output '授权完成后脚本自动继续（最长等待15分钟）'
    Write-Output '============================================='
    $deadline = (Get-Date).AddSeconds([Math]::Min(900, [int]$dc.expires_in))
    $interval = [int]$dc.interval
    $pollBody = @{ client_id = $clientId; device_code = $dc.device_code; grant_type = 'urn:ietf:params:oauth:grant-type:device_code' } | ConvertTo-Json
    while ((Get-Date) -lt $deadline) {
        Start-Sleep -Seconds $interval
        try {
            $r = Invoke-RestMethod -Uri 'https://github.com/login/oauth/access_token' -Method Post -Headers (New-Headers $null) -ContentType 'application/json' -Body $pollBody -TimeoutSec 20
        } catch { continue }
        if ($r.access_token) {
            $file = Join-Path $env:USERPROFILE '.github-token.txt'
            Set-Content -LiteralPath $file -Value $r.access_token -Encoding ASCII
            Write-Output "授权成功，token 已保存至 $file（下次推送直接复用）"
            return $r.access_token
        }
        if ($r.error -eq 'slow_down') { $interval += 5 }
        if ($r.error -in @('expired_token','access_denied')) { throw "授权失败或超时: $($r.error)" }
    }
    throw '等待授权超时（15分钟），请重新运行'
}

function Ensure-Repo($owner, $repo, $visibility, $token) {
    $r = Get-Api "https://api.github.com/repos/$owner/$repo" $token
    if ($r) { Write-Output "仓库已存在: $($r.html_url)"; return }
    $body = @{ name = $repo; private = ($visibility -eq 'private'); description = 'uploaded via dsh github-push skill'; auto_init = $false } | ConvertTo-Json
    $r = Invoke-RestMethod -Uri 'https://api.github.com/user/repos' -Method Post -Headers (New-Headers $token) -ContentType 'application/json' -Body $body -TimeoutSec 20
    Write-Output "仓库已创建: $($r.html_url)"
}

function Get-UploadFiles($path) {
    $full = [System.IO.Path]::GetFullPath((Resolve-Path -LiteralPath $path -ErrorAction Stop).Path)
    if (Test-Path -LiteralPath $full -PathType Leaf) { return ,@($full) }
    $files = @()
    Get-ChildItem -LiteralPath $full -Recurse -File -ErrorAction SilentlyContinue | Where-Object {
        $_.FullName -notmatch '\\\.git\\' -and $_.Name -ne '.github-token.txt'
    } | ForEach-Object { $files += $_.FullName }
    return $files
}

function Upload-ViaApi($owner, $repo, $path, $token) {
    $files = Get-UploadFiles $path
    $isFile = Test-Path -LiteralPath $path -PathType Leaf
    $rootDir = [System.IO.Path]::GetFullPath((Resolve-Path -LiteralPath $path).Path)
    if ($isFile) { $rootDir = Split-Path $rootDir }
    foreach ($f in $files) {
        $rel = $f.Substring($rootDir.Length).TrimStart('\').Replace('\', '/')
        $content = [Convert]::ToBase64String([System.IO.File]::ReadAllBytes($f))
        $uri = "https://api.github.com/repos/$owner/$repo/contents/$rel"
        $existing = Get-Api $uri $token
        $body = @{ message = $Message; content = $content; branch = 'main' }
        if ($existing) { $body.sha = $existing.sha }
        Invoke-RestMethod -Uri $uri -Method Put -Headers (New-Headers $token) -ContentType 'application/json' -Body ($body | ConvertTo-Json) -TimeoutSec 25 | Out-Null
        Write-Output "已上传: $rel"
    }
}

function Push-ViaGit($owner, $repo, $path, $token, $gitCmd) {
    $stage = $path
    $isFile = Test-Path -LiteralPath $path -PathType Leaf
    if ($isFile) {
        $stage = Join-Path $env:TEMP ("dsh-gh-" + [guid]::NewGuid().ToString('N').Substring(0, 8))
        New-Item -ItemType Directory -Force -Path $stage | Out-Null
        Copy-Item -LiteralPath $path -Destination (Join-Path $stage (Split-Path $path -Leaf))
    }
    $cwd = (Get-Location).Path
    try {
        Set-Location -LiteralPath $stage
        if (-not (Test-Path '.git')) {
            & $gitCmd init -b main 2>$null
            if ($LASTEXITCODE -ne 0) { & $gitCmd init | Out-Null; & $gitCmd checkout -b main 2>$null | Out-Null }
        }
        if (-not (& $gitCmd config user.name 2>$null)) { & $gitCmd config user.name $owner | Out-Null }
        if (-not (& $gitCmd config user.email 2>$null)) { & $gitCmd config user.email "$owner@users.noreply.github.com" | Out-Null }
        & $gitCmd add -A | Out-Null
        & $gitCmd commit -m $Message 2>$null | Out-Null
        if (-not (& $gitCmd remote get-url origin 2>$null)) {
            & $gitCmd remote add origin "https://github.com/$owner/$repo.git" | Out-Null
        }
        if ($token) {
            $credFile = Join-Path $env:USERPROFILE '.git-credentials'
            $keep = @()
            if (Test-Path -LiteralPath $credFile) { $keep = Get-Content -LiteralPath $credFile | Where-Object { $_ -notmatch 'github\.com' } }
            ($keep + "https://x-access-token:$token@github.com") | Set-Content -LiteralPath $credFile -Encoding ASCII
            & $gitCmd config --global credential.helper store | Out-Null
        }
        & $gitCmd push -u origin main
        if ($LASTEXITCODE -ne 0) { throw "git push 失败（exit $LASTEXITCODE）" }
        Write-Output "已推送: https://github.com/$owner/$repo"
    } finally {
        Set-Location $cwd
    }
}

switch ($Action) {
    'check' {
        $g = Find-Git
        $gh = Get-Command gh -ErrorAction SilentlyContinue
        $tk = Get-Token
        Write-Output "git:   $(if ($g) { $g } else { '未安装' })"
        Write-Output "gh:    $(if ($gh) { '已安装' } else { '未安装' })"
        Write-Output "token: $(if ($tk) { '已就绪' } else { '未找到（推送时将走设备码授权）' })"
        Write-Output "分支:  $(if ($g) { 'git push' } else { 'REST API 直传' }) + $(if ($tk) { '复用现有凭证' } else { '设备码授权' })"
    }
    'push' {
        if (-not $Repo) { throw '需要 -Repo 参数（仓库名）' }
        if (-not (Test-Path -LiteralPath $Path)) { throw "路径不存在: $Path" }
        $gitCmd = Find-Git
        $token = Get-Token
        if ($gitCmd) {
            Write-Output "检测到 git: $gitCmd"
            if (-not $token -and -not $Owner) {
                Write-Output '无凭证且未指定账号，先走设备码授权...'
                $token = Start-DeviceFlow
                $Owner = Resolve-Owner $token
            } elseif (-not $Owner) {
                $Owner = Resolve-Owner $token
            }
            $pushed = $false
            try {
                if ($token) { Ensure-Repo $Owner $Repo $Visibility $token }
                Push-ViaGit $Owner $Repo $Path $token $gitCmd
                $pushed = $true
            } catch {
                Write-Output "首次推送失败: $($_.Exception.Message)"
            }
            if (-not $pushed) {
                if (-not $token) { Write-Output '未发现凭证，启动设备码授权...'; $token = Start-DeviceFlow; $Owner = Resolve-Owner $token }
                Ensure-Repo $Owner $Repo $Visibility $token
                Push-ViaGit $Owner $Repo $Path $token $gitCmd
            }
        } else {
            Write-Output '未检测到 git，走 REST API 直传'
            if (-not $token) { Write-Output '未发现凭证，启动设备码授权...'; $token = Start-DeviceFlow }
            $Owner = Resolve-Owner $token
            Ensure-Repo $Owner $Repo $Visibility $token
            Upload-ViaApi $Owner $Repo $Path $token
            Write-Output "完成: https://github.com/$Owner/$Repo"
        }
    }
    'release' {
        if (-not $Repo) { throw '需要 -Repo 参数（仓库名）' }
        if (-not $Tag) { throw '需要 -Tag 参数（如 v1.0.0）' }
        if (-not (Test-Path -LiteralPath $Path)) { throw "路径不存在: $Path" }
        $token = Get-Token
        if (-not $token) { Write-Output '未发现凭证，启动设备码授权...'; $token = Start-DeviceFlow }
        $Owner = Resolve-Owner $token
        Ensure-Repo $Owner $Repo $Visibility $token
        # 打版本压缩包
        $zipName = "$Repo-$Tag.zip"
        $zipPath = Join-Path $env:TEMP $zipName
        if (Test-Path -LiteralPath $zipPath) { Remove-Item -LiteralPath $zipPath -Force }
        Compress-Archive -Path (Join-Path $Path '*') -DestinationPath $zipPath -CompressionLevel Optimal
        Write-Output "压缩包: $zipPath"
        # 建 Release（tag 自动取自 main 分支）
        $relBody = @{ tag_name = $Tag; name = $Tag; body = $Body; draft = $false; prerelease = $false } | ConvertTo-Json
        $rel = Invoke-RestMethod -Uri "https://api.github.com/repos/$Owner/$Repo/releases" -Method Post -Headers (New-Headers $token) -ContentType 'application/json' -Body $relBody -TimeoutSec 20
        # 上传 zip 资产（PS5.1 无 -InFile，用 WebClient）
        $upUrl = "https://uploads.github.com/repos/$Owner/$Repo/releases/$($rel.id)/assets?name=$zipName"
        $wc = New-Object System.Net.WebClient
        $wc.Headers.Add('Authorization', "Bearer $token")
        $wc.Headers.Add('User-Agent', 'dsh-github-push')
        $wc.Headers.Add('Accept', 'application/vnd.github+json')
        $wc.Headers.Add('Content-Type', 'application/zip')
        try { $null = $wc.UploadFile($upUrl, 'POST', $zipPath) } catch { throw "资产上传失败: $($_.Exception.Message)" }
        Write-Output "Release 已发布: $($rel.html_url)"
    }
}
