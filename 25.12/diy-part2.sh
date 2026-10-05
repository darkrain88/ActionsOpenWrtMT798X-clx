#!/bin/bash
#
# https://github.com/P3TERX/Actions-OpenWrt
# File name: diy-part2.sh
# Description: OpenWrt DIY script part 2 (After Update feeds)
#

echo "=========================================="
echo "执行自定义优化脚本 (diy-part2.sh)"
echo "=========================================="

# ---------------------------------------------------------
# libxcrypt 专项救治 (极致精简版)
# ---------------------------------------------------------
XCRYPT_MK="feeds/packages/libs/libxcrypt/Makefile"
if [ -f "$XCRYPT_MK" ]; then
    echo ">>> 正在硬化 libxcrypt 编译参数..."
    
    # 1. 强制禁用 werror (兼容多种等号写法)
    # 作用：防止编译器因为一些琐碎的警告而罢工
    sed -i 's/CONFIGURE_ARGS[ \t]*+=[ \t]*/&--disable-werror /' "$XCRYPT_MK"

    # 2. 注入 -fcommon (核心修复)
    # 作用：解决 gen-des-tables.o 报错的真凶（允许多重定义变量）
    # 使用 TARGET_CFLAGS 注入，如果还报 host 错，我们会同时注入给 HOST_CFLAGS
    sed -i 's/TARGET_CFLAGS[ \t]*+=[ \t]*/&-fcommon /' "$XCRYPT_MK"
    
    # 3. 额外保险：针对宿主机编译工具的补丁
    # 因为 gen-des-tables 是在你的电脑上跑的，有时候需要这一行
    # sed -i 's/HOST_CFLAGS[ \t]*+=[ \t]*/&-fcommon /' "$XCRYPT_MK" 2>/dev/null || true

    echo "✅ libxcrypt 参数注入完成。"
fi

# 5.1 Tailscale -> VPN 
TS_DIR=$(find feeds package -type d -name "luci-app-tailscale-community" 2>/dev/null | head -n 1)

if [ -n "$TS_DIR" ]; then
    echo ">>> 发现 Tailscale 插件目录: $TS_DIR"
    # 1. 替换菜单路径定义
    find "$TS_DIR" -type f -name "*.json" -exec sed -i 's|admin/services/tailscale|admin/vpn/tailscale|g' {} +
    # 2. 替换父级分类定义
    find "$TS_DIR" -type f -name "*.json" -exec sed -i 's/"parent": "luci.services"/"parent": "luci.vpn"/g' {} +
    echo "✅ Tailscale 菜单已移动到 VPN"
else
    # 备用逻辑：如果 feed 名改了，全盘搜索 package/feeds 内部
    TS_FILES=$(grep -rl "admin/services/tailscale" package/feeds 2>/dev/null)
    if [ -n "$TS_FILES" ]; then
        echo "$TS_FILES" | xargs sed -i 's|admin/services/tailscale|admin/vpn/tailscale|g'
        echo "$TS_FILES" | xargs sed -i 's/"parent": "luci.services"/"parent": "luci.vpn"/g'
        echo "✅ Tailscale 菜单(全盘搜索模式)已移动"
    fi
fi

# 5.2 KSMBD -> NAS (只在 ksmbd 目录下改)
# 自动定位 ksmbd 插件的物理目录，通常在 feeds/luci 下
KSMBD_DIR=$(find feeds/luci -type d -name "luci-app-ksmbd" | head -n 1)
if [ -n "$KSMBD_DIR" ]; then
    find "$KSMBD_DIR" -type f -exec sed -i 's|admin/services/ksmbd|admin/nas/ksmbd|g' {} +
    find "$KSMBD_DIR" -type f -exec sed -i 's/"parent": "luci.services"/"parent": "luci.nas"/g' {} +
    echo "✅ KSMBD 菜单已移动"
fi

# 5.3 OpenList2 -> NAS (自动定位并精准修改)
OPENLIST2_DIR=$(find feeds package -type d -name "luci-app-openlist2" | head -n 1)
if [ -n "$OPENLIST2_DIR" ]; then
    # 修改菜单路径：从 services 变更为 nas
    find "$OPENLIST2_DIR" -type f -exec sed -i 's|admin/services/openlist2|admin/nas/openlist2|g' {} +
    # 修改 JSON 父级定义 (如果存在 parent 字段)
    find "$OPENLIST2_DIR" -type f -exec sed -i 's/"parent": "luci.services"/"parent": "luci.nas"/g' {} +
    echo "✅ OpenList2 菜单已移动到 NAS"
fi

# 修复Rust本地编译LLVM
RUST_FILE="feeds/packages/lang/rust/Makefile"

if [ -f "$RUST_FILE" ]; then
  sed -i 's/download-ci-llvm=true/download-ci-llvm=false/g' "$RUST_FILE"
  echo "✅ Rust 已设置为本地编译 LLVM"
else
  RUST_FILE=$(find feeds/ -type f -name "Makefile" -path "*/lang/rust/*" | head -1)
  if [ -n "$RUST_FILE" ]; then
    sed -i 's/download-ci-llvm=true/download-ci-llvm=false/g' "$RUST_FILE"
    echo "✅ Rust 已设置为本地编译 LLVM (路径: $RUST_FILE)"
  else
    echo "⚠️ 未找到 Rust Makefile，跳过"
  fi
fi

MAKEFILE="feeds/packages/utils/dockerd/Makefile"
   if [ ! -f "$MAKEFILE" ]; then
       echo "ERROR: dockerd Makefile not found: $MAKEFILE"; exit 1
   fi
          echo "========== DEPENDS (before) =========="
          sed -n '/define Package\/dockerd$/,/^endef/p' "$MAKEFILE"

          # 1) 整行删除（覆盖 +IPV6: 条件前缀、iptables 全部变体、续行反斜杠）
          sed -i -E \
            -e '/^[[:space:]]*\+(IPV6:)?(iptables|ip6tables|iptables-mod-[a-z0-9-]+|ip6tables-mod-[a-z0-9-]+|kmod-ipt-[a-z0-9-]+)[[:space:]]*\\?[[:space:]]*$/d' \
            "$MAKEFILE"
          # 2) 兜底：同一行混排多个依赖时逐个剔除
          sed -i -E \
            -e 's/\+(IPV6:)?(iptables|ip6tables|iptables-mod-[a-z0-9-]+|ip6tables-mod-[a-z0-9-]+|kmod-ipt-[a-z0-9-]+)([[:space:]]+|$)/ /g' \
            "$MAKEFILE"

          echo "========== DEPENDS (after) =========="
          sed -n '/define Package\/dockerd$/,/^endef/p' "$MAKEFILE"

          # 3) 双向校验：iptables 系依赖清零，必要依赖未被误删
          if grep -Eq '\+(IPV6:)?(iptables|ip6tables|kmod-ipt-)' "$MAKEFILE"; then
            echo "ERROR: iptables dependencies still present"; exit 1
          fi
          for dep in containerd kmod-veth tini uci-firewall kmod-nf-ipvs; do
            grep -q "+${dep}" "$MAKEFILE" \
              || { echo "ERROR: ${dep} was accidentally removed"; exit 1; }
          done
          echo "dockerd iptables dependencies removed OK."

mkdir -p files/etc/docker files/etc/uci-defaults
         # dockerd >=29 支持 firewall-backend=nftables（原生 nftables 管理规则）
          # dockerd <29 不支持该 key（会被拒启），降级为仅 iptables:false + fw4 NAT
          if grep -Eq '^PKG_VERSION:=29\.' \
               feeds/packages/utils/dockerd/Makefile; then
            cat > files/etc/docker/daemon.json <<'EOF'
          {
            "iptables": false,
            "ip6tables": false,
            "firewall-backend": "nftables",
            "data-root": "/opt/docker",
              "registry-mirrors": [
              "https://docker.1ms.run" ,
              "https://docker.xuanyuan.me" ,
              "https://docker.m.daocloud.io" ,
              "https://docker.1panel.live" ,
              "https://dockerproxy.net"
            ]
          }
          EOF
          else
            cat > files/etc/docker/daemon.json <<'EOF'
          {
            "iptables": false,
            "ip6tables": false,
            "data-root": "/opt/docker",
              "registry-mirrors": [
              "https://docker.1ms.run" ,
              "https://docker.xuanyuan.me" ,
              "https://docker.m.daocloud.io" ,
              "https://docker.1panel.live" ,
              "https://dockerproxy.net"
            ]
          }
          EOF
          fi
          cat files/etc/docker/daemon.json

          # init 脚本只认 /tmp/dockerd/daemon.json（由 UCI 生成）。
          # 设置 alt_config_file 后，init 直接软链我们的文件，
          # 并跳过 UCI 配置生成与 iptables 规则注入。
          cat > files/etc/uci-defaults/99-dockerd-nftables <<'EOF'
          #!/bin/sh
          [ -f /etc/config/dockerd ] || touch /etc/config/dockerd
          uci -q get dockerd.globals >/dev/null || uci -q set dockerd.globals=globals
          uci -q set dockerd.globals.alt_config_file='/etc/docker/daemon.json'
          uci -q set dockerd.globals.iptables='0'
          uci -q set dockerd.globals.ip6tables='0'
          uci -q commit dockerd

          # iptables=false 时 dockerd 不做 NAT，由 fw4 的 docker zone 负责
          # （预建并开 masq，dockerd init 的 uciadd 检测到已存在不会覆盖）
          if ! uci -q get firewall.docker >/dev/null; then
            uci -q add firewall zone >/dev/null
            uci -q rename firewall.@zone[-1]='docker'
            uci -q set firewall.docker.name='docker'
            uci -q set firewall.docker.input='ACCEPT'
            uci -q set firewall.docker.output='ACCEPT'
            uci -q set firewall.docker.forward='ACCEPT'
            uci -q set firewall.docker.masq='1'
            uci -q add_list firewall.docker.network='docker'
            uci -q commit firewall
          fi
          exit 0
          EOF
          chmod +x files/etc/uci-defaults/99-dockerd-nftables
          echo "daemon.json + uci-defaults generated."
   mkdir -p files/usr/bin files/etc/hotplug.d/block files/etc/uci-defaults

          # ---- 1) 挂载/卸载辅助脚本 ----
          cat > files/usr/bin/mount-opt <<'EOF'
          #!/bin/sh
          # 将第一个未挂载的 USB/SD 分区挂载到 /opt
          MOUNT_POINT="/opt"

          do_mount() {
            local dev
            mkdir -p "$MOUNT_POINT"
            # /opt 已被占用则不重复挂
            grep -qs " ${MOUNT_POINT} " /proc/mounts && return 0
            for dev in /dev/sd[a-z][0-9]* /dev/mmcblk[0-9]p[0-9]*; do
              [ -b "$dev" ] || continue
              grep -qs "^${dev} " /proc/mounts && continue
              logger -t mount-opt "mounting ${dev} -> ${MOUNT_POINT}"
              mount -o rw,noatime "$dev" "$MOUNT_POINT" && return 0
            done
            return 1
          }

          do_umount() {
            local dev="${1}"
            grep -qs "^${dev} ${MOUNT_POINT} " /proc/mounts && umount "$MOUNT_POINT"
          }

          case "$1" in
            mount)  do_mount ;;
            umount) do_umount "$2" ;;
            *) echo "usage: $0 mount|umount [dev]" ;;
          esac
          EOF
          chmod +x files/usr/bin/mount-opt

          # ---- 2) hotplug: 开机冷插拔 + 运行期热插拔 ----
          cat > files/etc/hotplug.d/block/40-mount-opt <<'EOF'
          case "$ACTION" in
            add)
              case "$DEVNAME" in
                sd[a-z][0-9]*|mmcblk[0-9]p[0-9]*)
                  # 后台执行避免阻塞 hotplug 队列; 等 1s 让设备节点就绪
                  ( sleep 1; /usr/bin/mount-opt mount ) &
                  ;;
              esac
              ;;
            remove)
              case "$DEVNAME" in
                sd[a-z][0-9]*|mmcblk[0-9]p[0-9]*)
                  /usr/bin/mount-opt umount "/dev/$DEVNAME"
                  ;;
              esac
              ;;
          esac
          EOF

          # ---- 3) 首次开机: 禁用 blockd, 并提前完成挂载 ----
          cat > files/etc/uci-defaults/99-mount-opt <<'EOF'
          # blockd 会把 U 盘自动挂到 /mnt/sda1, 与 /opt 冲突, 禁用之
          [ -x /etc/init.d/blockd ] && /etc/init.d/blockd disable

          mkdir -p /opt

          # S10 时 kmodloader 已加载 usb-storage, 稍等设备枚举后挂载
          (
            n=0
            while [ "$n" -lt 10 ] && ! /usr/bin/mount-opt mount; do
              sleep 1
              n=$((n+1))
            done
          ) &

          exit 0
          EOF
          chmod +x files/etc/uci-defaults/99-mount-opt
                INIT="feeds/packages/utils/dockerd/files/dockerd.init"
          test -f "$INIT"
          python3 - <<'PY'
          from pathlib import Path
          p = Path("feeds/packages/utils/dockerd/files/dockerd.init")
          s = p.read_text()
          wait = """start_service() {
          \t# wait for /opt (USB auto-mount), max 15s; skip if no USB disk
          \tlocal n=0
          \twhile [ "$n" -lt 15 ]; do
          \t\tgrep -qs " /opt " /proc/mounts && break
          \t\tls /dev/sd*[0-9] >/dev/null 2>&1 || break
          \t\tsleep 1
          \t\tn=$((n+1))
          \tdone
          """
          if "wait for /opt" not in s:
              assert "start_service() {" in s, "anchor not found, upstream changed!"
              s = s.replace("start_service() {", wait, 1)
              p.write_text(s)
          PY
          grep -n "wait for /opt" "$INIT"

mkdir -p files/etc/sysctl.d
cat > files/etc/sysctl.d/99-mt7986a-optimize.conf << 'SYSCTL'
# --- 1. 队列与拥塞控制 (低延迟核心) ---
# 使用 fq_codel 队列，这是目前降低延迟的神器
net.core.default_qdisc = fq_codel
# 使用 BBR 拥塞控制算法，利用 2.5G 高带宽
net.ipv4.tcp_congestion_control = bbr
# --- 2. TCP 行为优化 ---
# 优先考虑低延迟
net.ipv4.tcp_low_latency = 1
# 关闭自动软木塞，减少小包发送延迟 (保持关闭以保证游戏响应)
net.ipv4.tcp_autocorking = 0
# 加快连接回收
net.ipv4.tcp_fin_timeout = 15
net.ipv4.tcp_tw_reuse = 1
net.ipv4.tcp_slow_start_after_idle = 0
# 开启 TCP Fast Open
net.ipv4.tcp_fastopen = 3
# 更好的 MTU 处理 (避免PPPoE环境下的MTU黑洞)
net.ipv4.tcp_mtu_probing = 1
# 防止 TCP 队列延迟过大 (适配 2.5G 高吞吐)
net.ipv4.tcp_limit_output_bytes = 1048576
# --- 3. 内存缓冲区调整 (适配 2GB RAM + 2.5G 网络) ---
# 将上限提升至 16MB，确保高带宽下载不卡顿，同时 fq_codel 会负责抑制延迟
net.core.rmem_max = 16777216
net.core.wmem_max = 16777216
# 调整默认值，适中即可
net.core.rmem_default = 262144
net.core.wmem_default = 262144
# TCP 缓冲区：最小值 -> 默认值 -> 最大值
net.ipv4.tcp_rmem = 4096 87380 16777216
net.ipv4.tcp_wmem = 4096 65536 16777216
# TCP 内存压力控制 (单位：页)
# 适配 2GB 内存，给予 TCP 充足的内存空间
net.ipv4.tcp_mem = 32768 65536 131072
# --- 4. 监听与连接队列 ---
net.core.somaxconn = 1024
net.ipv4.tcp_max_syn_backlog = 1024
# --- 5. UDP 精细化分配 (游戏/语音保命优化) ---
# 普通UDP（视频流/DNS）：30秒释放，腾出槽位，防止 conntrack 表满
net.netfilter.nf_conntrack_udp_timeout = 30
# 游戏UDP流（王者/语音）：必须180秒！防止局内掉线重连
net.netfilter.nf_conntrack_udp_timeout_stream = 180
# 连接追踪表上限 (大内存路由器建议调大，避免表满丢包)
net.netfilter.nf_conntrack_max = 262144
# --- 6. IPv6 专项优化 ---
# 邻居表大小优化 (防止 2.5G 高负载下表满卡顿)
net.ipv6.neigh.default.gc_thresh1 = 1024
net.ipv6.neigh.default.gc_thresh2 = 2048
net.ipv6.neigh.default.gc_thresh3 = 4096
# 限制单接口 IPv6 地址数量，节省 CPU
net.ipv6.conf.all.max_addresses = 2
SYSCTL



# 修改默认 IP (192.168.30.1)
sed -i 's/192.168.1.1/192.168.2.1/g' package/base-files/files/bin/config_generate
sed -i 's/ImmortalWrt/JWRT/g' package/base-files/files/bin/config_generate
#sed -i 's/hostname='.*'/hostname='JWRT'/g' package/base-files/files/bin/config_generate

#CFG_FILE="./package/base-files/files/bin/config_generate"
#修改默认IP地址
#sed -i "s/192\.168\.[0-9]*\.[0-9]*/$WRT_IP/g" $CFG_FILE
#修改默认主机名
#sed -i "s/hostname='.*'/hostname='$WRT_NAME'/g" $CFG_FILE

# change APP Version
# sed -i 's/0.47.075/0.47.088/g' package/feeds/luci/luci-app-openclash/Makefile

echo "✅ SSH2 配置完成。"
