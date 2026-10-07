# 网络速度测量步骤

`network_speed.sh` 从 Linux `/proc` 文件系统读取网卡累计收发字节数，显示每个采样区间的平均速率，以及从开始测量到当前时刻的累计平均速率。速率使用十进制 Mbps，即 `1 Mbps = 1,000,000 bit/s`。

以下步骤以 `eth0` 和 1 秒采样间隔为例。

1. 查看可用网卡，并确认目标网卡存在。

   ```bash
   awk -F: 'NR > 2 {gsub(/[[:space:]]/, "", $1); print $1}' /proc/net/dev
   ```

2. 记录开始测量时的接收字节、发送字节和系统运行时间。

   ```bash
   awk '$1 == "eth0:" {print "RX bytes:", $2; print "TX bytes:", $10}' /proc/net/dev
   awk '{print "Uptime seconds:", $1}' /proc/uptime
   ```

3. 等待一个采样区间，再次执行上一步的两个命令。

   ```bash
   sleep 1
   awk '$1 == "eth0:" {print "RX bytes:", $2; print "TX bytes:", $10}' /proc/net/dev
   awk '{print "Uptime seconds:", $1}' /proc/uptime
   ```

4. 将两次读数代入下列命令，计算该区间的平均收发速率。

   ```bash
   awk -v rx1='<第一次RX字节>' -v rx2='<第二次RX字节>' \
       -v tx1='<第一次TX字节>' -v tx2='<第二次TX字节>' \
       -v t1='<第一次运行时间>' -v t2='<第二次运行时间>' \
       'BEGIN {
           printf "RX: %.2f Mbps\n", (rx2-rx1)*8/(t2-t1)/1000000
           printf "TX: %.2f Mbps\n", (tx2-tx1)*8/(t2-t1)/1000000
       }'
   ```

5. 继续定期读取计数。计算累计平均时，始终用当前读数减去第 2 步的开始读数，并用当前运行时间减去开始运行时间；区间平均则使用相邻两次读数。

也可以通过统一入口持续测量。省略参数时默认测量 `eth0`，采样间隔为 1 秒：

```bash
source <(curl -fsSL https://gitee.com/hit_whr/scripts/raw/main/run.sh) network-speed
```

指定网卡和采样间隔，例如每 0.5 秒测量一次 `ens18`：

```bash
source <(curl -fsSL https://gitee.com/hit_whr/scripts/raw/main/run.sh) \
    network-speed ens18 0.5
```

按 `Ctrl+C` 停止测量。若网卡计数器在运行中重置，脚本会提示并从新的计数值重新开始累计测量。
