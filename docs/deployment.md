# Deployment notes

این فایل منطق و تصمیم‌های فنی نسخه‌ی نهایی پروژه را ثبت می‌کند تا نصب‌های بعدی با همان پیکربندی تکرار شوند.

## 1. Display

MKS TS35 V2 از ST7796S با framebuffer `fb_st7796s` استفاده می‌کند. نمایشگر روی SPI1 CS1 و تاچ XPT2046 روی همان باس، SPI1 CS2، قرار دارد.

در overlay نهایی:

- LCD: 48 MHz
- Touch: 2 MHz
- LCD reset: PC12
- LCD DC: PC14
- Touch IRQ: PC10
- Touch CS: PC13

سرعت LCD از 12.5MHz به 40MHz و سپس 48MHz افزایش داده شد. 48MHz پایدار بود و 60MHz روی سخت‌افزار تست‌شده ناپایدار شد.

## 2. Why spidev instead of ads7846

درایور `ads7846` در build مورد استفاده برای این پروژه لمس‌ها را به‌صورت قابل‌اعتماد تشخیص نمی‌داد. پس node تاچ با `linux,spidev` تعریف شد و خواندن XPT2046 مستقیماً از Python انجام می‌شود.

`virtual_touch.py` یک `uinput` device با نام `ADS7846 Touchscreen` می‌سازد تا لایه‌ی X11/KlipperScreen آن را به‌عنوان touchscreen ببیند.

## 3. Idle/active touch loop

در حالت idle، اسکریپت روی GPIO74 منتظر IRQ می‌ماند و SPI را poll نمی‌کند. هنگام لمس، X/Y/Z از SPI خوانده می‌شوند و حدود 30Hz گزارش می‌شوند.

X/Y عمداً در Python جابه‌جا شده‌اند تا جهت صفحه مطابق پنل تست‌شده باشد.

## 4. Beeper

GPIO70 / PC6 برای بیزر فعال 5V انتخاب شده است. برای جلوگیری از حالت شناور هنگام boot، مقاومت pull-down یک کیلو اهم در مدار پایه‌ی ترانزیستور توصیه می‌شود.

بیزر مستقیماً توسط MCU کلیپر کنترل نمی‌شود. این طراحی عمداً ساده نگه داشته شده است:

1. Klipper macro فقط `RESPOND MSG="BEEPER_TOGGLE_EVENT"` می‌فرستد.
2. `beeper_watcher.py` پیام جدید Moonraker را تشخیص می‌دهد.
3. watcher فایل `beeper_enabled` را بین 0 و 1 تغییر می‌دهد.
4. `virtual_touch.py` وضعیت فایل را هر یک ثانیه می‌خواند.

## 5. KlipperScreen menu

بلوک منوی سفارشی باید بالای marker خودکار KlipperScreen قرار بگیرد:

```ini
[menu __main more beeper_toggle]
name: Touch Beep
icon: notifications
method: printer.gcode.script
params: {"script":"TOGGLE_BEEPER"}
```

نصب‌کننده این بلوک را قبل از marker قرار می‌دهد تا در بازنویسی بخش auto-generated حذف نشود.

## 6. Power

در تست پروژه، تغذیه BTT Pi از مسیر رگولاتور Robin Nano باعث نویز رنگی گذرا هنگام لمس شد. تغذیه مستقیم 12V به ورودی اختصاصی BTT Pi این مشکل را حدود 99٪ کاهش داد.

بنابراین در deploymentهای بعدی، تغذیه مستقل BTT Pi توصیه می‌شود.

## 7. Recovery

نصب‌کننده قبل از تغییر فایل‌های زیر backup می‌سازد:

- `/boot/armbianEnv.txt`
- `/etc/X11/xorg.conf.d/99-ts35-fbdev.conf`
- `printer.cfg`
- `KlipperScreen.conf`

Backupها در `~/novin3dp-ts35-backups/<timestamp>/` قرار می‌گیرند.

## 8. Important platform assumptions

این پروژه برای CB1/BTT Pi با Allwinner H616 و محیط Armbian/Debian که در راهنمای اصلی پروژه آزمایش شده است نوشته شده است. اگر kernel، DTB، pinmux یا مسیر SPI روی یک image دیگر متفاوت باشد، قبل از استفاده‌ی production باید overlay و device paths مجدداً بررسی شوند.

## 9. Manual validation

پس از reboot:

```bash
ls -l /dev/fb0 /dev/spidev0.2
sudo ls /proc/device-tree/soc/spi@5011000/
dmesg | grep -i spi
systemctl status KlipperScreen --no-pager
systemctl status virtual-touch.service --no-pager
systemctl status beeper-watcher.service --no-pager
```

در صورت مشاهده‌ی مشکل، ابتدا لاگ‌های systemd و `dmesg` را بررسی کنید و سپس سراغ تغییر SPI frequency بروید.
