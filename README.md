# 📟 netwatchd

**netwatchd** is a lightweight, POSIX-compliant shell daemon for **OpenWrt routers** that monitors both internet connectivity and local LAN devices.  
It delivers **real-time outage and recovery alerts** straight to your **Discord channel** using webhooks.

Built for reliability, minimal resource usage, and zero bloat.

---

## ✨ Features

- **Ultra Lightweight**  
  Written in pure `sh`, using ~**1.2 MB RAM**

- **Dual Connectivity Monitoring**  
  - External internet availability  
  - Local LAN device status

- **Smart Alert Logic**  
  Prevents notification spam when the entire network is offline

- **Discord Webhook Integration**  
  Supports **@mentions** for immediate visibility

- **Automatic Recovery Reports**  
  Calculates and reports total downtime once connectivity is restored

- **Built-in Log Rotation**  
  Prevents logs from consuming router RAM

---

## 🚀 Installation

Run the following command in your OpenWrt router’s terminal.  
The installer is **interactive** and will guide you through setup.

```sh
wget -qO /tmp/install_netwatchd.sh \
"https://raw.githubusercontent.com/panoc/Net-Watch-Discord-Alerts/refs/heads/main/install_netwatchd.sh" \
&& sh /tmp/install_netwatchd.sh
