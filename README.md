# MKS TS35 V2 + BTT Pi / CB1 + KlipperScreen

راه‌اندازی خودکار نمایشگر **MKS TS35 V2** روی **BTT Pi / CB1** برای استفاده با **Klipper + Mainsail + KlipperScreen**.

این repository فایل‌ها و اسکریپت‌های نهایی پروژه را یک‌جا جمع می‌کند تا نصب روی دستگاه‌های بعدی با چند دستور انجام شود.

## سخت‌افزار هدف

- BTT Pi v1.2 + CB1 / Allwinner H616
- MKS TS35 V2، رزولوشن 480×320، کنترلر ST7796S
- تاچ مقاومتی XPT2046 روی SPI
- Klipper + Moonraker + Mainsail
- KlipperScreen با backend X11
- Armbian / Debian با پشتیبانی از DT overlay و framebuffer

> **توجه:** این پروژه بر اساس یک پیکربندی واقعی و تست‌شده برای CB1 تهیه شده است. بخش Device Tree و GPIOها به سخت‌افزار هدف وابسته‌اند و نباید بدون بررسی روی برد دیگری استفاده شوند.

## نصب سریع

روی BTT Pi / CB1 با کاربر معمولی اجرا کنید:

```bash
cd ~
git clone https://github.com/Novin3dp/mks-ts35-btt-pi-klipper-screen.git
cd mks-ts35-btt-pi-klipper-screen
bash install.sh
```

یا به‌صورت یک خط:

```bash
tmp=$(mktemp -d) && git clone --depth 1 https://github.com/Novin3dp/mks-ts35-btt-pi-klipper-screen.git "$tmp/ts35" && bash "$tmp/ts35/install.sh"; rc=$?; rm -rf "$tmp"; exit $rc
```

اسکریپت نصب وابستگی‌ها، Device Tree Overlay، Xorg، KlipperScreen، درایور مجازی تاچ، سرویس‌های systemd و قابلیت Touch Beep را نصب و تنظیم می‌کند و قبل از تغییر فایل‌های موجود backup می‌سازد.

پس از نصب، **یک reboot لازم است** تا overlay فعال شود.

## سیم‌کشی

| MKS TS35 | BTT Pi / CB1 |
|---|---|
| MOSI | Pin 19 / PH7 |
| MISO | Pin 21 / PH8 |
| SCK | Pin 23 / PH6 |
| LCD_CS | Pin 7 / PC7 → SPI1 CS1 |
| LCD_DC | Pin 11 / PC14 |
| LCD_RST | Pin 13 / PC12 |
| T_CS | Pin 12 / PC13 → SPI1 CS2 |
| T_IRQ | Pin 15 / PC10 |
| 5V | Pin 2 یا 4 |
| GND | Pin 6 |

UART0 برای ارتباط با Robin Nano V3 تغییر نمی‌کند:

- Pin 8 / PH0 = UART0 TX
- Pin 10 / PH1 = UART0 RX

### تغذیه

برای جلوگیری از نویز رنگی هنگام لمس، BTT Pi را از **ورودی اختصاصی 12V خود BTT Pi** تغذیه کنید و آن را از رگولاتور 5V مادربرد پرینتر تغذیه نکنید.

در تست اصلی پروژه، تغذیه مستقیم 12V به BTT Pi نویز رنگی را حدود 99٪ کاهش داد.

## بیزر اختیاری

بیزر فعال 5V را می‌توان با یک ترانزیستور NPN از GPIO70 کنترل کرد:

- Pin 35 / PC6 / GPIO70 → مقاومت 1kΩ → Base
- مقاومت 1kΩ بین Base و GND
- Emitter → GND
- Collector → منفی بیزر
- مثبت بیزر → +5V

مقاومت pull-down یک کیلو اهم برای جلوگیری از بیپ تصادفی هنگام boot توصیه می‌شود.

## معماری نرم‌افزار

```text
MKS TS35
 ├── ST7796S LCD ── SPI1 CS1 ── /dev/fb0 ── Xorg/fbdev ── KlipperScreen
 │
 └── XPT2046 Touch ── SPI1 CS2 ── /dev/spidev0.2
                         │
                         └── virtual_touch.py ── uinput ── X11

KlipperScreen Touch Beep
        │
        └── TOGGLE_BEEPER macro
                 │
                 └── Moonraker gcode_store
                          │
                          └── beeper_watcher.py
                                   │
                                   └── beeper_enabled
                                            │
                                            └── virtual_touch.py
```

درایور استاندارد `ads7846` عمداً استفاده نمی‌شود؛ تاچ به‌صورت مستقیم با `spidev` خوانده شده و یک دستگاه ورودی مجازی با `uinput` ساخته می‌شود.

## تنظیمات نهایی تست‌شده

- LCD SPI: **48 MHz**
- Touch SPI: **2 MHz**
- Touch sampling هنگام لمس: حدود **30 Hz**
- Touch IRQ: GPIO74 / PC10
- Beeper: GPIO70 / PC6
- Touch coordinate: swap X/Y در Python
- framebuffer: `/dev/fb0`
- Touch device: `/dev/spidev0.2`

سرعت 48MHz برای LCD بعد از تست پله‌ای انتخاب شد؛ 60MHz روی سخت‌افزار تست‌شده ناپایدار بود.

## بعد از reboot بررسی کنید

```bash
ls /dev/fb0
ls -l /dev/spidev0.2
sudo ls /proc/device-tree/soc/spi@5011000/
```

وضعیت سرویس‌ها:

```bash
systemctl status KlipperScreen --no-pager
systemctl status virtual-touch.service --no-pager
systemctl status beeper-watcher.service --no-pager
```

لاگ تاچ:

```bash
journalctl -u virtual-touch.service -f
```

## حذف

```bash
cd ~/mks-ts35-btt-pi-klipper-screen
bash uninstall.sh
```

این اسکریپت **Klipper و KlipperScreen را حذف نمی‌کند**.

## عیب‌یابی

### صفحه `/dev/fb0` ایجاد نشده

```bash
dmesg | grep -i spi
ls /dev/fb*
sudo cat /boot/armbianEnv.txt
```

بررسی کنید `user_overlays=ts35_cb1` در `armbianEnv.txt` وجود داشته باشد و بعد reboot کنید.

### KlipperScreen بالا نمی‌آید

```bash
sudo systemctl status KlipperScreen --no-pager
sudo journalctl -u KlipperScreen -n 100 --no-pager
```

### تاچ کار نمی‌کند

```bash
ls -l /dev/spidev0.2
sudo systemctl status virtual-touch.service --no-pager
sudo journalctl -u virtual-touch.service -n 100 --no-pager
```

### تاچ درست است ولی تصویر نویز دارد

اولین موردی که باید بررسی شود تغذیه BTT Pi است. از ورودی اختصاصی 12V BTT Pi استفاده کنید.

اگر آرتیفکت در تصویر باقی ماند، سرعت LCD را در overlay کاهش دهید؛ 48MHz مقدار نهایی تست‌شده در پروژه است ولی کیفیت سیم‌کشی می‌تواند روی حاشیه پایداری SPI اثر بگذارد.

## ساختار repository

```text
.
├── install.sh
├── uninstall.sh
├── README.md
├── LICENSE
├── overlay/
│   └── ts35_cb1.dts
├── scripts/
│   ├── virtual_touch.py
│   └── beeper_watcher.py
├── services/
│   ├── virtual-touch.service
│   └── beeper-watcher.service
├── xorg/
│   └── 99-ts35-fbdev.conf
├── klipper/
│   └── toggle_beeper.cfg
├── klipperscreen/
│   └── touch_beep.conf
└── docs/
    └── deployment.md
```

## منبع فنی

این repository بر اساس راهنمای کامل پروژه و تنظیمات نهایی تست‌شده تهیه شده است. جزئیات عیب‌یابی و تصمیم‌های فنی در `docs/deployment.md` نگهداری می‌شود.

## License

MIT — see `LICENSE`.
