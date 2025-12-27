# 🚀 netwatchdta (v1.3.6)
**Universal Network Monitoring for OpenWrt & Linux**

**netwatchdta** is a lightweight, high-performance network monitor designed to track the uptime of local devices, remote servers, and internet connectivity.

It features a unique **"Hybrid Execution Engine"** that combines **Parallel Scanning** (for instant outage detection) with **Queued Notifications** (to prevent RAM saturation on low-end routers).

---

## 🌟 Key Features
* **Universal Compatibility:** Runs on OpenWrt (Ash) and Standard Linux (Bash/Systemd).
* **Hybrid Engine (v1.3.6+):**
    * **Scanning:** Always runs in **Parallel** for millisecond-precision detection.
    * **Notifications:** Uses a **Smart Lock Queue** on low-RAM devices to send alerts sequentially, capping RAM usage.
* **Dual-Stack Alerts:** Native support for **Discord** (Webhooks) and **Telegram** (Bot API).
* **Resource Efficient:** Uses as little as **400KB RAM** at idle on OpenWrt.
* **Hardware Locked Encryption:** Credentials are encrypted via OpenSSL AES-256 and locked to your specific CPU/MAC address.
* **Resilience:** Buffers alerts to disk during internet outages and flushes them when connectivity is restored.

---

## 📊 Performance & Resource Analysis
*Detailed analysis of RAM and Storage usage for v1.3.6.*

### 1. 💾 Storage Requirements
| Component | Size | Notes |
| :--- | :--- | :--- |
| **Core Script & Configs** | **~50 KB** | Ultra-lightweight footprint. |
| **Dependencies (OpenWrt)** | **~1.4 MB** | `openssl-util`, `ca-bundle`, `uclient-fetch` (often pre-installed). |
| **Dependencies (Linux)** | **~3.0 MB** | Standard `curl`, `openssl`, `ca-certificates`. |

### 2. 🧠 RAM Usage (Real-World Scenarios)

#### **A. Idle State**
*Background monitoring waiting for next cycle.*
* **OpenWrt:** ~0.4 MB
* **Linux:** ~3.5 MB

#### **B. Scanning Phase (Parallel Mode)**
*Usage scales with the number of monitored devices. Duration: ~1 second.*
*Formula: `(Shell Overhead + Ping Overhead) x Device Count`*

| Target Count | OpenWrt RAM Spike | Linux RAM Spike |
| :--- | :--- | :--- |
| **1 Device** | ~0.4 MB | ~3.0 MB |
| **10 Devices** | ~4.0 MB | ~30.0 MB |
| **50 Devices** | ~20.0 MB | ~150.0 MB |

#### **C. Notification Phase (1 Event)**
*One device goes down. Script sends alerts to **BOTH** Discord and Telegram.*
*Note: Alerts are sent sequentially (one after another) to save RAM, so usage does not double.*

| OS & Tool | Peak RAM Usage |
| :--- | :--- |
| **OpenWrt + `uclient-fetch`** | **~0.6 MB** |
| **OpenWrt + `curl`** | **~2.5 MB** |
| **Linux + `curl`** | **~5.0 MB** |

#### **D. Mass Failure Phase (50 Events)**
*Scenario: 50 devices go offline instantly. Alerts sent to Discord AND Telegram.*

| System Mode | Behavior | Total Peak RAM (OpenWrt) |
| :--- | :--- | :--- |
| **Method 1 (High RAM)** | **Instant Parallel:** Sends 50 alerts at once. | **~125 MB** (Risk of Crash) |
| **Method 2 (Low RAM)** | **Smart Queue:** Alerts wait in line. Sends 1 by 1. | **~23 MB** 🟢 **(Safe Limit)** |

> **Analytic Verdict:** By using the Smart Queue (Method 2), **netwatchdta** ensures that even a 128MB router never exceeds ~23MB RAM usage during a catastrophic network failure, while still detecting the outage instantly.

---

## 📈 Hardware Selection Guide

<details>
<summary><strong>Click to expand: Safe Device Limits Table</strong></summary>

### **Method 1: Standard Parallel Mode**
*Auto-enabled for devices with **>256MB RAM**. Simultaneous scanning & instant notifications.*

| Chipset Tier | Example Devices | 50 Events (RAM/CPU) | Est. Safe Max Events |
| :--- | :--- | :--- | :--- |
| **Legacy / Low Power** | Ubiquiti ER-X, Xiaomi 4A | **💀 CRITICAL (~125 MB)** | **~10 - 15 Events** |
| **Mid-Range** | Pi Zero 2, Flint 2 | **High Spike (~150 MB)** | **~30 - 40 Events** |
| **High-End (x86)** | N100, Pi 5, NanoPi R6S | **Low Load** | **200+ Events** |

### **Method 2: Queued Notification Mode**
*Auto-enabled for devices with **<256MB RAM**. Parallel scanning (fast detection) + Serialized notifications (RAM safety).*

| Chipset Tier | Example Devices | Behavior during 50 Events | Recommended? |
| :--- | :--- | :--- | :--- |
| **Legacy / Low Power** | **Ubiquiti ER-X, R6220** | **CPU:** 100% Spike (Scan)<br>**RAM:** ~23 MB (Safe) | **✅ YES** |
| **Mid-Range** | **Pi Zero 2, Pi 3/4** | **CPU:** Moderate Spike<br>**RAM:** ~45 MB (Very Safe) | **✅ YES** |
| **High-End** | **N100, Pi 5** | **CPU:** Negligible<br>**RAM:** Negligible | **❌ Unnecessary** |

</details>

<br>

<details>
<summary><strong>Click to expand: Quick Decision Matrix</strong></summary>

### 🎯 Quick Decision Matrix
*Choose the right hardware based on your intended usage.*

| If your goal is... | Recommended Hardware Tier | Execution Mode | Best Device Options |
| :--- | :--- | :--- | :--- |
| **Just Monitoring**<br>*(Dedicated "Watchdog")* | **Low-End / Legacy**<br>*(Zero Cost)* | **Method 2**<br>*(Auto-Selected)* | Old Routers (128MB RAM), Travel Routers, Pi Zero |
| **Monitoring + Network Services**<br>*(AdGuard, VPN Client)* | **Mid-Range SBC**<br>*(Balanced)* | **Method 1**<br>*(Standard)* | Raspberry Pi 3/4, NanoPi R4S, Flint 2 |
| **Heavy Multitasking**<br>*(Gigabit Routing, NAS)* | **High-End x86 / ARM**<br>*(Performance)* | **Method 1**<br>*(Standard)* | NanoPi R6S, Intel N100, Raspberry Pi 5 |

</details>

---

## 📂 File Structure
**netwatchdta** creates the following files during installation.

### 1. Installation Directory
**Location:** `/opt/netwatchdta/` (Linux) or `/root/netwatchdta/` (OpenWrt).

| File Name | Description |
| :--- | :--- |
| `netwatchdta.sh` | The core logic script (the engine). |
| `settings.conf` | Main configuration file for user settings. |
| `device_ips.conf` | List of local IPs to monitor. |
| `remote_ips.conf` | List of remote IPs to monitor. |
| `.vault.enc` | Encrypted credential store (Discord/Telegram tokens). |
| `nwdta_silent_buffer` | Temporary buffer for alerts held during silent hours. |
| `nwdta_offline_buffer` | Temporary buffer for alerts held during Internet outages. |

### 2. Temporary & Log Files
**Location:** `/tmp/netwatchdta/`
*(Note: These are created in RAM to prevent flash storage wear on routers)*

| File Name | Description |
| :--- | :--- |
| `nwdta_uptime.log` | The main event log (Service started, alerts sent, etc). |
| `nwdta_ping.log` | Detailed ping log (Only if `PING_LOG_ENABLE=YES`). |
| `nwdta_net_status` | Stores current internet status (`UP` or `DOWN`). |
| `*_d`, `*_c`, `*_t` | Various tracking files for timeout/failure counts. |

---

## 🛠️ Commands

### **OpenWrt (Procd)**
```bash
/etc/init.d/netwatchdta start       # Start Service
/etc/init.d/netwatchdta stop        # Stop Service
/etc/init.d/netwatchdta check       # Check Status & PID
/etc/init.d/netwatchdta logs        # View Live Logs
/etc/init.d/netwatchdta edit        # Interactive Config Editor
/etc/init.d/netwatchdta credentials # Update Discord/Telegram Keys safely
/etc/init.d/netwatchdta purge       # Uninstall
