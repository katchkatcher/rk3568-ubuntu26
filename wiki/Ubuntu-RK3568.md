# Ubuntu 26.04.1 на NMS-SM-RK3568 / NMS-SM-EVM

## Назначение

Проект создаёт загрузочный raw-образ Ubuntu Server 26.04.1 ARM64 для платы NMS-SM-RK3568 / NMS-SM-EVM. В качестве userspace используется официальный generic ARM64 preinstalled server image Ubuntu. Загрузка выполняется через Rockchip U-Boot, а ядро, Device Tree, модули ядра и firmware берутся из проверенной сборки Buildroot для этой платы.

Поддерживаются два варианта образа:

- `ubuntu-emmc.img` — для прошивки во встроенную eMMC;
- `ubuntu-sd.img` — образ с отдельным MBR disk ID для SD-карты.

Основной сценарий не требует пересборки Buildroot на машине пользователя. Проверенные бинарные зависимости поставляются отдельным архивом reference assets.

## Как устроены исходные данные

Проект разделяет три группы файлов:

1. **Git-репозиторий** — скрипты, параметры сборки и эта документация.
2. **Reference asset bundle** — бинарные файлы, полученные из проверенного Buildroot и релизного каталога `rk3568-br-release`. Архив публикуется в Releases проекта и распаковывается в `reference/`.
3. **Ubuntu base image** — официальный `ubuntu-26.04.1-preinstalled-server-arm64.img.xz`, который загружается скриптом в `inputs/ubuntu/` и проверяется по SHA256.

### Состав reference assets

Скрипт `import_reference_assets.sh` собирает в `reference/` только то, что требуется Ubuntu image builder:

| Файл в reference bundle | Источник |
|---|---|
| `kernel/Image` | Buildroot `output/images/Image` |
| `kernel/rk3568-inmys-smarc-evm.dtb` | Buildroot `output/images/rk3568-inmys-smarc-evm.dtb` |
| `modules/6.12.61/` | Buildroot `output/target/lib/modules/6.12.61/` |
| `firmware/` | Buildroot `output/target/lib/firmware/`, если каталог существует |
| `boot/u-boot-rockchip.bin` | `rk3568-br-release/u-boot-rockchip.bin` |
| `rockchip/rk3568_ddr_1332MHz_v1.23.bin` | `rk3568-br-release/` |
| `rockchip/rk356x_usbplug_v1.17.bin` | `rk3568-br-release/` |

Из каталога `rk3568-br-release` намеренно не копируются `br_2024.02_rk3568.dd`, `rootfs.ext2`, `mbr.dat` и `burn.sh`: текущая сборка Ubuntu их не использует. Таблица разделов формируется непосредственно скриптом через `sfdisk`; Buildroot rootfs заменяется Ubuntu rootfs.

Важно: сам каталог `rk3568-br-release` не содержит `Image`, DTB и `/lib/modules/6.12.61` согласно составу релизной папки. Для однократного создания reference bundle сопровождающему также нужен соответствующий Buildroot workspace с `output/images` и `output/target`. После публикации архива пользователям эти исходные каталоги уже не требуются.

### Создание и публикация reference bundle (сопровождающий проекта)

На машине, где доступны Buildroot workspace и `rk3568-br-release`:

```bash
./scripts/import_reference_assets.sh "$HOME/work" "$HOME/rk3568-br-release"
./scripts/create_reference_bundle.sh
```

Скрипт проверяет наличие обязательных исходников, копирует их в `reference/` и формирует `reference/SHA256SUMS`. Затем создаётся:

```text
dist/rk3568-ubuntu-reference-assets-v1.tar.gz
dist/rk3568-ubuntu-reference-assets-v1.tar.gz.sha256
```

Загрузите оба файла в GitHub Release. Для следующей версии задайте, например, `REFERENCE_BUNDLE_VERSION=v2 ./scripts/create_reference_bundle.sh`. Если меняются kernel, DTB, U-Boot, loader или модули, создайте новый архив и увеличьте версию bundle в имени файла/Release. Не коммитьте эти бинарники в Git: `reference/` исключён через `.gitignore`.

## Подготовка рабочей машины

Для Ubuntu/Debian host установите инструменты:

```bash
sudo apt update
sudo apt install curl xz-utils util-linux e2fsprogs rsync openssl
```

Для прошивки дополнительно требуется `xrock`, установленный и доступный через `PATH`. Сам `xrock` в репозиторий не включён.

Склонируйте Git-репозиторий и перейдите в его каталог. Все последующие команды запускаются из него; скрипты сами вычисляют корень проекта и не зависят от текущего рабочего каталога.

## Получение Ubuntu и проверка SHA256

Запустите:

```bash
./scripts/download_ubuntu.sh
```

Скрипт загружает официальный `SHA256SUMS` и generic ARM64 preinstalled server image:

```text
https://cdimage.ubuntu.com/ubuntu/releases/26.04.1/release/
ubuntu-26.04.1-preinstalled-server-arm64.img.xz
```

Это образ для ARMv8/AArch64, а не вариант `+raspi`. SHA256 сверяется с официальным манифестом; для текущего файла зафиксировано значение:

```text
189b1aec3eaf9544a51dba4e6ac3f4d5d24fd1031ed0263fa5ea78f1824934c1
```

Готовый файл и загруженный `SHA256SUMS` сохраняются в `inputs/ubuntu/`. Если файл уже загружен, скрипт сначала проверит его и не будет скачивать заново при совпадении контрольной суммы.

## Получение и установка reference bundle

Скачайте `rk3568-ubuntu-reference-assets-v1.tar.gz` из Releases репозитория и выполните:

```bash
./scripts/install_reference_bundle.sh ~/Downloads/rk3568-ubuntu-reference-assets-v1.tar.gz
```

Скрипт при наличии проверяет внешний файл `*.tar.gz.sha256`, затем проверяет структуру архива, распаковывает его во временный каталог, проверяет каждый файл по `reference/SHA256SUMS` и только после успешной проверки помещает данные в `reference/`.

## Сборка образов

Запустите из корня проекта:

```bash
sudo ./scripts/build_images.sh
```

На этапе сборки скрипт:

1. Проверяет Ubuntu base image по SHA256 и проверяет наличие reference assets.
2. Распаковывает базовый Ubuntu image и находит ext4-раздел с root filesystem.
3. Создаёт rootfs размером 8 GiB и копирует в него Ubuntu userspace.
4. Заменяет boot-файлы на Buildroot kernel `Image` и DTB для NMS-SM-RK3568.
5. Устанавливает модули ядра версии `6.12.61` и firmware из reference bundle.
6. Настраивает `extlinux.conf`, `fstab`, hostname, DHCP через `systemd-networkd` и NoCloud cloud-init.
7. Запрашивает пароль для локального пользователя `user`; в образ записывается его хеш, а не пароль в открытом виде.
8. Формирует два raw-образа с разными MBR disk ID.

Результат:

```text
output/ubuntu-emmc.img
output/ubuntu-sd.img
```

Скрипт требует root, поскольку использует loop devices и монтирование файловых систем. Не запускайте несколько сборок параллельно в одном каталоге проекта.

## Разметка и параметры загрузки

Разметка основана на проверенной схеме Buildroot для этой платы:

| Параметр | Значение |
|---|---|
| Таблица разделов | MBR / DOS |
| MBR disk ID eMMC | `0x35680001` |
| MBR disk ID SD | `0x35680002` |
| Запись U-Boot | сектор `64` |
| Начало p1 | сектор `32768` (16 MiB) |
| p1 | 8 GiB, ext4, label `rootfs` |
| p1 PARTUUID eMMC | `35680001-01` |
| p1 PARTUUID SD | `35680002-01` |
| Начало p2 | сразу после p1 |
| p2 | 2 GiB, ext4 |
| p2 label eMMC / SD | `STORE` / `STORE_SD` |
| Точка монтирования p2 | `/opt` |
| Kernel | Buildroot `Image`, Linux `6.12.61` |
| DTB | `rk3568-inmys-smarc-evm.dtb` |
| UART console | `ttyS2`, `1500000` baud |

В `extlinux.conf` используются `earlycon=uart8250,mmio32,0xfe660000`, `console=ttyS2,1500000`, `root=PARTUUID=...`, `rootwait` и NoCloud datasource. U-Boot записывается в raw-образ отдельно от разделов на сектор 64.

## Прошивка eMMC через Maskrom

Перед прошивкой:

- убедитесь, что собран `output/ubuntu-emmc.img`;
- установите `xrock` и проверьте его доступность через `PATH`;
- переведите плату в Maskrom согласно аппаратной инструкции NMS-SM-EVM;
- подключите USB OTG к X10; согласно инструкции платы, USB VBUS должен быть отсоединён, GND оставлен;
- установите перемычку X2 Disable eMMC boot и подайте питание 12 V;
- проверьте, что устройство определяется как Rockchip `2207:350a`.

Запустите:

```bash
sudo ./scripts/flash_emmc.sh
```

Скрипт использует loader-файлы из `reference/rockchip/`, переводит устройство в Maskrom/loader и передаёт образ командой:

```bash
xrock flash write 0 output/ubuntu-emmc.img
```

Перед записью скрипт требует ввести `FLASH`. Это операция полного перезаписывания eMMC. Убедитесь, что подключена именно целевая плата.

SD-образ `output/ubuntu-sd.img` создаётся тем же процессом, но отдельный SD-card flashing workflow в этот набор скриптов пока не включён.

## Первый запуск

После прошивки подключите UART-консоль и питание платы. Ожидаемые параметры UART: `1500000` baud, `ttyS2`.

В образе настроены:

- hostname `nms-sm-rk3568`;
- пользователь `user` с паролем, заданным во время сборки;
- DHCP для Ethernet через `systemd-networkd`;
- SSH, если соответствующий unit присутствует в Ubuntu base image;
- корневой раздел `/` и раздел `STORE`/`STORE_SD`, смонтированный в `/opt`;
- cloud-init NoCloud для начальной настройки пользователя.

Учётная запись `user` сейчас добавляется в `sudo` с `NOPASSWD`. Это настройка для лабораторной отладки; перед промышленным использованием её нужно пересмотреть.

## Результат проверки на плате

По фактически полученному загрузочному логу подтверждены:

- U-Boot обнаруживает `extlinux.conf` и запускает Linux kernel `6.12.61`;
- eMMC определяется как `/dev/mmcblk0`;
- корневой раздел `/dev/mmcblk0p1` монтируется как `/`;
- второй раздел монтируется в `/opt`;
- Ubuntu 26.04.1 доходит до пользовательского пространства и login prompt;
- cloud-init NoCloud обрабатывается, пользователь `user` может войти в систему;
- HDMI-видеовыход на подключённом мониторе работает.

Ограничения/незакрытые проверки:

- установка XFCE и дополнительных desktop-пакетов через APT не была завершена из-за отсутствия сетевого доступа/доступа к пакетным репозиториям; это не проблема HDMI;
- сетевое подключение и доступ в Интернет нужно настраивать/проверять отдельно;
- CAN-интерфейсы требуют отдельной проверки после загрузки модулей;
- `systemd-networkd-wait-online.service` в одном из логов завершался ошибкой, несмотря на то, что система загрузилась до login prompt;
- сообщение U-Boot `bad CRC, using default environment` присутствовало, но не помешало загрузке.

Настройка Интернета, установка GUI-пакетов, настройка CAN и эксплуатационная конфигурация Ubuntu не являются задачами данного image-builder этапа и должны документироваться отдельно.

## Обновление проекта

При обновлении Buildroot kernel/DTB/modules или Rockchip bootloader:

1. Получить соответствующие `output/images` и `output/target` из новой проверенной сборки Buildroot.
2. Обновить артефакты в `rk3568-br-release`, если изменились U-Boot или loader.
3. Запустить `import_reference_assets.sh` с новыми исходными каталогами.
4. Проверить `reference/SHA256SUMS` и собрать новый архив через `create_reference_bundle.sh`.
5. Протестировать новый образ на целевой плате.
6. Опубликовать новый reference bundle в GitHub Release и обновить версию/описание в README и Wiki.

При обновлении Ubuntu версии измените версию, URL и зафиксированный SHA256 в `scripts/download_ubuntu.sh`, а затем проверьте, что rootfs нового образа совместим с используемыми kernel, modules и DTB.

## Безопасность и ограничения

- Не добавляйте в Git base image Ubuntu, reference binaries, готовые raw images и временные файлы.
- Не публикуйте загрузочные логи без проверки: они могут содержать MAC/IP-адреса, host keys и другую информацию конкретной платы.
- Пароль пользователя вводится интерактивно при сборке и сохраняется в образе в виде хеша; не передавайте готовый образ как универсальный, если в нём используется общий пароль.
- Перед прошивкой проверяйте подключённую плату и подтверждение `FLASH`.
- Этот проект рассчитан на конкретную плату и проверенную связку kernel/DTB/modules/U-Boot. Перенос на другую ревизию платы требует отдельной проверки.
