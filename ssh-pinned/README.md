# ssh-pinned 目录说明

本目录存放恢复脚本需要的"pin 住"的材料。**真实密钥不进 git 仓库**，
这里只有模板。按 `docs/setup.md` 在本地生成真实文件。

| 文件 | 说明 | 模板 |
|------|------|------|
| `song_authorized_keys` | 登录用户的公钥（每行一个） | `song_authorized_keys.example` |
| `jump_known_hosts` | 跳板机 host key（`ssh-keyscan` 获取） | `jump_known_hosts.example` |
| `sshd_host_keys/` | sshd 主机密钥（首次运行脚本自动 pin） | —（本地生成，不提交） |

`sshd_host_keys/` 已在 `.gitignore` 中忽略。
