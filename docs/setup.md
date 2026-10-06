# 从零搭建反向 SSH 隧道

## 1. 准备工作

- 一台有公网 IP 的跳板机（本文以 `root@<跳板机IP>` 为例）
- 云 VM 上已生成 SSH keypair：`~/.ssh/id_ed25519`
- 跳板机 `root` 的 `authorized_keys` 里已加入 VM 的公钥（VM → 跳板机免密）

## 2. 准备恢复材料

```bash
# 登录公钥（把所有允许登录的公钥逐行写入）
cat > ~/workspace/.ssh-pinned/song_authorized_keys <<'EOF'
ssh-ed25519 AAAA... user1@example
ssh-ed25519 AAAA... user2@example
EOF
chmod 600 ~/workspace/.ssh-pinned/song_authorized_keys

# 跳板机 host key（IP 会变但 key 不变，pin 住避免每次确认）
ssh-keyscan <跳板机IP> > ~/workspace/.ssh-pinned/jump_known_hosts 2>/dev/null
```

## 3. 准备 .deb 包（apt 不可用时的兜底）

```bash
mkdir -p ~/workspace/.debs
cd ~/workspace/.debs
# 在一台同版本 Ubuntu 上下载（不安装）：
apt download openssh-server openssh-sftp-server
```

把 `.deb` 拷到 VM 的 `~/workspace/.debs/`。

## 4. 修改脚本中的变量

编辑 `restore-after-reboot.sh`，替换：

| 原值 | 改为 |
|------|------|
| `root@8.137.117.134` | 你的跳板机 `user@host` |
| `22022` | 跳板机监听端口（按需） |
| `song` | 登录用户名（按需） |
| `apple_known_hosts` / `lobster_known_hosts` | 你自己的 `*_known_hosts` 文件名 |

## 5. 首次运行

```bash
~/workspace/bin/restore-after-reboot.sh
# 或直接跑项目里的：
./restore-after-reboot.sh
```

首次运行会自动 pin 下 sshd 主机密钥到 `ssh-pinned/sshd_host_keys/`，
保证 VM 重启后 host key 不变，跳板机侧不用重新确认。

## 6. 验证

```bash
# 跳板机上确认隧道端口监听
ssh root@<跳板机IP> 'ss -tln | grep 22022'
# 从跳板机登录 VM
ssh -p 22022 song@127.0.0.1
```

## 7. 设置看门狗（可选）

用 cron / systemd timer 每 15 分钟跑一次 `restore-after-reboot.sh`，
脚本幂等，无操作时静默。按 `watchdog.md` 的报告规则通知。
