#!/usr/bin/env bash
# 重启后恢复脚本（幂等）：VM 重启会清空 /root、/etc、/usr/sbin/sshd、登录用户，
# 只有 $PERSIST_DIR 持久。本脚本从持久目录的恢复材料重建一切。
#
# ===== 配置区：按 docs/setup.md 修改 =====
JUMP_HOST="root@8.137.117.134"     # 跳板机 user@host
TUNNEL_PORT="22022"                # 跳板机监听端口
LOGIN_USER="song"                  # VM 侧登录用户名
SSHD_PORT="2222"                   # VM 侧 sshd 端口（仅 loopback）
SSH_KEY="/home/hatch/.ssh/id_ed25519"
# ======================================
set -u
DEBS_DIR="/home/hatch/workspace/.debs"
PIN_DIR="/home/hatch/workspace/.ssh-pinned"
LOG_PREFIX="[restore-after-reboot]"
did=""

# 1. openssh-server 二进制
if [[ ! -x /usr/sbin/sshd ]]; then
  echo "$LOG_PREFIX 安装 openssh-server .deb ..."
  dpkg -i "$DEBS_DIR"/openssh-server_*.deb "$DEBS_DIR"/openssh-sftp-server_*.deb >/dev/null 2>&1 \
    || { echo "$LOG_PREFIX .deb 安装失败"; exit 1; }
  did="$did sshd-binary"
fi

# 2. /run/sshd 与 nologin
mkdir -p /run/sshd
chmod 755 /run/sshd
rm -f /run/nologin /etc/nologin

# 3. song 用户 + 公钥（公钥是公开材料，存在持久目录）
if ! id $LOGIN_USER >/dev/null 2>&1; then
  echo "$LOG_PREFIX 重建 song 用户 ..."
  useradd -m -s /bin/bash $LOGIN_USER
  did="$did song-user"
fi
install -d -m 700 -o $LOGIN_USER -g $LOGIN_USER /home/$LOGIN_USER/.ssh
install -m 600 -o $LOGIN_USER -g $LOGIN_USER "$PIN_DIR/song_authorized_keys" /home/$LOGIN_USER/.ssh/authorized_keys

# 4. sshd 主机密钥（pin 在持久目录；若无则生成后 pin 下，供下次重启用）
PINKEYS="$PIN_DIR/sshd_host_keys"
if [[ -d "$PINKEYS" ]]; then
  install -d -m 755 /etc/ssh
  for k in ecdsa ed25519 rsa; do
    for suffix in "" ".pub"; do
      f="$PINKEYS/ssh_host_${k}_key$suffix"
      [[ -f "$f" ]] || continue
      mode=600; [[ "$suffix" == ".pub" ]] && mode=644
      install -m "$mode" -o root -g root "$f" "/etc/ssh/ssh_host_${k}_key$suffix"
    done
  done
fi

# 5. sshd 配置（仅监听 127.0.0.1:$SSHD_PORT，禁密码/禁 root）
cat > /etc/ssh/sshd_config <<'EOF'
# Reverse-tunnel endpoint: loopback only (restored by restore-after-reboot.sh)
Port 2222  # 如改端口，同步改脚本顶部 SSHD_PORT
ListenAddress 127.0.0.1
PermitRootLogin no
PasswordAuthentication no
KbdInteractiveAuthentication no
PubkeyAuthentication yes
AuthorizedKeysFile .ssh/authorized_keys
UsePAM yes
X11Forwarding no
PrintMotd no
AcceptEnv LANG LC_*
Subsystem sftp /usr/lib/openssh/sftp-server
EOF

# 5. 启动 sshd（若未监听）
if ! ss -tln 2>/dev/null | grep -q "127.0.0.1:$SSHD_PORT"; then
  echo "$LOG_PREFIX 启动 sshd ..."
  /usr/sbin/sshd || { echo "$LOG_PREFIX sshd 启动失败"; exit 1; }
  sleep 1
  ss -tln 2>/dev/null | grep -q "127.0.0.1:$SSHD_PORT" || { echo "$LOG_PREFIX sshd 未监听 2222"; exit 1; }
  did="$did sshd"
fi

# 5.5 首次运行时 pin 下 sshd 自动生成的密钥，避免下次重启换 key
PINKEYS="$PIN_DIR/sshd_host_keys"
if [[ ! -d "$PINKEYS" ]]; then
  mkdir -p "$PINKEYS"
  cp -p /etc/ssh/ssh_host_* "$PINKEYS"/ 2>/dev/null && chmod 600 "$PINKEYS"/ssh_host_*_key
  did="$did hostkeys-pinned"
fi

# 6. Host keys（pin 在持久目录，复制到 /root/.ssh）
#    apple_known_hosts：Apple DDNS（IP 常变，key 不变）
#    lobster_known_hosts：硅谷龙虾 VPS Tailscale IP
mkdir -p /root/.ssh
chmod 700 /root/.ssh
touch /root/.ssh/known_hosts
chmod 600 /root/.ssh/known_hosts
for pinfile in "$PIN_DIR/apple_known_hosts" "$PIN_DIR/lobster_known_hosts"; do
  [ -f "$pinfile" ] || continue
  while IFS= read -r line; do
    host="${line%% *}"
    if ! ssh-keygen -F "$host" -f /root/.ssh/known_hosts >/dev/null 2>&1; then
      echo "$line" >> /root/.ssh/known_hosts
      did="$did known-hosts($(basename "$pinfile"))"
    fi
  done < "$pinfile"
done

# 7. 反向隧道（ECS:$TUNNEL_PORT -> 本机:2222）
if ! pgrep -f -- "-R $TUNNEL_PORT:127.0.0.1:$SSHD_PORT" >/dev/null; then
  echo "$LOG_PREFIX 重建反向隧道 ..."
  ssh -f -N -i $SSH_KEY -o StrictHostKeyChecking=accept-new \
    -o BatchMode=yes -o ServerAliveInterval=30 -o ServerAliveCountMax=3 \
    -o ExitOnForwardFailure=yes -o ConnectTimeout=15 \
    -R $TUNNEL_PORT:127.0.0.1:$SSHD_PORT $JUMP_HOST || { echo "$LOG_PREFIX 隧道重建失败（可能需用户审批）"; exit 2; }
  sleep 2
  pgrep -f -- "-R $TUNNEL_PORT:127.0.0.1:$SSHD_PORT" >/dev/null || { echo "$LOG_PREFIX 隧道进程未存活"; exit 2; }
  did="$did tunnel"
fi

if [[ -z "$did" ]]; then
  echo "$LOG_PREFIX 一切正常，无需恢复"
else
  echo "$LOG_PREFIX 恢复完成:$did"
fi
