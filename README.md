<div align="center">

<pre>
   ██████╗ ██╗  ██╗      ███╗   ███╗ ██████╗ ██████╗ 
  ██╔════╝ ╚██╗██╔╝      ████╗ ████║██╔═══██╗██╔══██╗
  ██║  ███╗ ╚███╔╝  ████╗██╔████╔██║██║   ██║██║  ██║
  ██║   ██║ ██╔██╗  ╚═══╝██║╚██╔╝██║██║   ██║██║  ██║
  ╚██████╔╝██╔╝ ██╗      ██║ ╚═╝ ██║╚██████╔╝██████╔╝
   ╚═════╝ ╚═╝  ╚═╝      ╚═╝     ╚═╝ ╚═════╝ ╚═════╝ 
</pre>

**Gaming Server Optimization Framework**

![Banner](https://raw.githubusercontent.com/Dnt3e/Gx-Mod/refs/heads/main/Gx-Mod.png)

![Ubuntu](https://img.shields.io/badge/Ubuntu-22%2B-E95420?style=flat-square&logo=ubuntu&logoColor=white)
![Bash](https://img.shields.io/badge/Bash-5.0+-4EAA25?style=flat-square&logo=gnubash&logoColor=white)
![License](https://img.shields.io/badge/License-MIT-blue?style=flat-square)
![Version](https://img.shields.io/badge/Version-1.0.0-cyan?style=flat-square)
![Author](https://img.shields.io/badge/Author-D3nte-purple?style=flat-square)

</div>

---

> 🇮🇷 [فارسی](#-فارسی) &nbsp;|&nbsp; 🇬🇧 [English](#-english)

---

## 🇮🇷 فارسی

<div dir="rtl">

### Gx-Mod چیست؟

Gx-Mod یک فریمورک بهینه‌سازی سرور گیمینگ برای اوبونتو نسخه ۲۲ به بالا هست که با یک اسکریپت bash سروری رو به صورت هوشمند تنظیم می‌کنه — از یه VPS ارزون ۱ گیگی تا یه سرور ددیکیت قدرتمند.

هدفش اینه که **تاخیر** کمتر بشه، **جیتر** پایین بیاد، و **پهنای باند** پایدار بمونه. بدون وعده‌های توخالی، بدون تنظیمات خطرناک.

---

### ✨ قابلیت‌ها

- **شناسایی خودکار سخت‌افزار** — مقدار RAM، تعداد هسته CPU، نوع دیسک (NVMe/SSD/HDD)، نوع مجازی‌سازی (KVM، OpenVZ و...)
- **تشخیص RTT** — چند تست ping به سرورهای مختلف می‌زنه و میانگین تاخیر رو حساب می‌کنه
- **۴ حالت بهینه‌سازی** — از حالت خودکار تا تنظیمات تخصصی برای ایران و بازی‌های رقابتی
- **بنچمارک قبل و بعد** — نتایج واقعی رو نشون می‌ده، نه اعداد ساختگی
- **پشتیبان‌گیری و بازیابی کامل** — قبل از هر تغییری بکاپ می‌گیره، با یه دستور برمی‌گرده
- **سرویس systemd** — بعد از ریبوت سرور، تنظیمات خودکار اعمال می‌شن
- **رابط رنگی و تمیز** — منوی ساده با رنگ‌بندی واضح در ترمینال

---

### 🚀 نصب سریع

</div>

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/Dnt3e/Gx-Mod/main/Gx-Mod.sh)
```

<div dir="rtl">

---

### 🎯 حالت‌های بهینه‌سازی

| توضیح | مناسب برای | حالت |
|-------|-----------|------|
| RTT رو اندازه می‌گیره و بهترین پروفایل رو انتخاب می‌کنه | همه سرورها | **Auto-Detect** |
| تنظیمات ایمن و متعادل، مناسب اکثر سرورها | VPS معمولی | **Balanced** |
| بهینه برای مسیرهای ناپایدار و تاخیر بالای ۵۰ms | سرورهای ایران | **Iran High RTT** |
| کمترین تاخیر ممکن برای بازی‌های رقابتی | ددیکیت قوی | **Ultra FPS** |

---

### 📊 خروجی بنچمارک

</div>

```
Metric               Before       After        Difference
RTT (ms)             7.67         5.00         2.67ms
Jitter (ms)          2.75         0.36         2.39ms
Packet Loss (%)      0            0            0.0%
Retransmits          0            0            0
```

<div dir="rtl">

---

### ⚙️ چه چیزی تغییر می‌کنه؟

- الگوریتم کنترل ازدحام **BBR** فعال می‌شه
- صف شبکه روی **fq** تنظیم می‌شه
- بافرهای TCP متناسب با RAM سرور تنظیم می‌شن
- **swappiness** روی ۱۰ تنظیم می‌شه
- scheduler دیسک بر اساس نوع دیسک انتخاب می‌شه
- تنظیمات NIC بر اساس حالت انتخابی اعمال می‌شن

---

### 📋 پیش‌نیازها

- اوبونتو نسخه ۲۲ به بالا
- دسترسی root
- اتصال اینترنت (برای نصب وابستگی‌ها)

---

### 🔒 امنیت و پایداری

Gx-Mod **هیچ تنظیم ناامنی** اعمال نمی‌کنه. تمام مقادیر در محدوده استاندارد لینوکس هستن. اگه سخت‌افزار ضعیف باشه، به حالت Balanced برمی‌گرده. بنچمارک‌ها واقعی هستن — اگه بهبودی نباشه، صادقانه گزارش می‌ده.

</div>

---

## 🇬🇧 English

### What is Gx-Mod?

Gx-Mod is an adaptive gaming server optimization framework for Ubuntu 22+. It intelligently tunes your server's network stack, CPU, memory, and disk scheduler — whether you're running a budget 1GB VPS or a high-end dedicated server.

The goal is simple: **lower latency**, **less jitter**, **stable bandwidth**. No snake oil, no unsafe tweaks.

---

### ✨ Features

- **Hardware auto-detection** — RAM, CPU cores, disk type (NVMe/SSD/HDD), virtualization (KVM, OpenVZ, etc.)
- **RTT detection** — pings multiple targets, calculates average latency and jitter
- **4 optimization modes** — from fully automatic to specialized profiles for high-RTT and competitive gaming
- **Before/After benchmarking** — real measured results, no fake numbers
- **Full backup & restore** — backs up all settings before changes, one command to revert
- **Systemd service** — settings persist automatically after reboot
- **Clean colored UI** — simple terminal menu with clear visual feedback

---

### 🚀 Quick Install

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/Dnt3e/Gx-Mod/main/Gx-Mod.sh)
```

---

### 🎯 Optimization Modes

| Mode | Best For | Description |
|------|----------|-------------|
| **Auto-Detect** | Any server | Measures RTT and picks the optimal profile automatically |
| **Balanced** | Standard VPS | Safe, well-rounded settings suitable for most servers |
| **Iran High RTT** | Iran-hosted servers | Tuned for unstable routing and latency above 50ms |
| **Ultra FPS** | Powerful dedicated | Minimum possible latency for competitive gaming |

---

### 📊 Benchmark Output

```
Metric               Before       After        Difference
RTT (ms)             7.67         5.00         2.67ms
Jitter (ms)          2.75         0.36         2.39ms
Packet Loss (%)      0            0            0.0%
Retransmits          0            0            0
```

---

### ⚙️ What Gets Tuned?

- **BBR** congestion control enabled
- Network qdisc set to **fq**
- TCP buffers scaled to server RAM
- **swappiness** set to 10
- Disk I/O scheduler selected based on disk type
- NIC interrupt coalescing adjusted per mode

---

### 📋 Requirements

- Ubuntu 22+
- Root access
- Internet connection (for dependency installation)

---

### 🔒 Safety

Gx-Mod applies **no unsafe values**. All parameters stay within standard Linux ranges. On low-spec hardware, it automatically falls back to Balanced mode. Benchmarks are real — if there's no improvement, it says so.

---

### 📁 File Locations

| Path | Purpose |
|------|---------|
| `/etc/gx-mod/` | Configuration directory |
| `/etc/sysctl.d/99-gx-mod.conf` | Applied sysctl parameters |
| `/var/log/gx-mod.log` | Operation log |
| `/var/log/gx-mod-benchmark.log` | Benchmark results |
| `/etc/gx-mod/backup/` | Backup of original settings |

---

<div align="center">

Made with ❤️ by **[D3nte](https://github.com/Dnt3e)**

</div>
