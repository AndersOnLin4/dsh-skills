# doubao-skill

A [DeepSeek Harness (DSH)](https://github.com/deepseek-ai) skill that drives the local **Doubao desktop client** (Doubao.exe) entirely through Windows UI Automation — no mouse, no keyboard focus stealing, no API key.

You can open a new chat, switch between 快速 / 专家 / 工作任务 modes, send messages, upload file/image attachments, and read replies, all from one PowerShell script, while the human keeps working normally on the same machine.

## Install

1. Make sure the Doubao desktop client is installed, running, and logged in.
2. Copy the `doubao` folder into a skills root of your DSH installation:
   - user-level (all projects): `<dshHome>\skills\` — i.e. `G:\harness\dsh-home\skills\` (typical) or `~/.dsh/skills`
   - project-level: `<project>\.dsh\skills\` or `<project>\.agents\skills\`
3. That's it. The skill is discovered automatically; no restart needed in most setups.

## Usage (inside DSH, via the pwsh tool)

```powershell
$s = Join-Path $env:DSH_HOME 'skills\doubao\scripts\doubao.ps1'   # or <skill-dir>\scripts\doubao.ps1
Set-ExecutionPolicy -Scope Process Bypass -Force

& $s -Action status                                        # window title / current mode / input content
& $s -Action newchat                                       # start a new chat
& $s -Action mode -Mode 快速                                # 快速 | 专家 | 工作任务 Auto | 工作任务 Turbo | 工作任务 Pro
& $s -Action send -Text '你好' -WaitSec 30 -MaxLines 10     # send and wait for the reply to finish
& $s -Action send -Text '描述这张图' -Files 'C:\a.png','C:\b.txt' -WaitSec 40   # send with attachments
& $s -Action send -Text '...' -NewChat                     # new chat, then send
& $s -Action attach -Files 'C:\x.pdf'                      # attach only
& $s -Action read -MaxLines 15                             # read the last 15 lines of the conversation
& $s -Action wait -WaitSec 60                              # wait until generation finishes
```

See `doubao/SKILL.md` for the skill body and `doubao/references/troubleshooting.md` for mechanism details and troubleshooting.

## How it works

- Locates the Doubao main window by **process name** (`Doubao`), so the install path doesn't matter.
- Wakes the Chromium accessibility tree with `WM_GETOBJECT`, then drives the UI with UIA patterns only (`InvokePattern`, `ValuePattern`, `ExpandCollapsePattern`) — the physical cursor is never moved.
- File uploads go through the native open dialog via `WM_SETTEXT` + `BM_CLICK` message injection.
- Reply completion is detected by polling the message-area text for stability.

## Notes

- This path is equivalent to the human operating the app: your Doubao account quota applies as usual; no API key is consumed.
- Requires Windows with PowerShell (5.1+ or 7+); tested with the Doubao Windows desktop client on a 200%-scaled display.
- UI strings (mode names, menu items) may change when Doubao updates; see `references/troubleshooting.md` if a step stops working.

## License

MIT — see [LICENSE](LICENSE).
