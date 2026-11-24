# Ubuntu 26.04.1 для NMS-SM-RK3568

Скрипты для подготовки Ubuntu Server 26.04.1 ARM64 на плате NMS-SM-RK3568 / NMS-SM-EVM. Проект использует готовые проверенные бинарные артефакты Buildroot/Rockchip: пересобирать Buildroot пользователю не требуется.

## Быстрый запуск

1. Склонировать репозиторий и установить хостовые инструменты:

   ```bash
   sudo apt update
   sudo apt install curl xz-utils util-linux e2fsprogs rsync openssl
   ```

2. Скачать Ubuntu base image и проверить его SHA256:

   ```bash
   ./scripts/download_ubuntu.sh
   ```

3. Скачать reference asset bundle из Releases этого репозитория и распаковать его в проект:

   ```bash
   ./scripts/install_reference_bundle.sh ~/Downloads/rk3568-ubuntu-reference-assets-v1.tar.gz
   ```

4. Собрать образы:

   ```bash
   sudo ./scripts/build_images.sh
   ```

5. Прошить eMMC (требуется установленный `xrock` и подключённая в Maskrom плата):

   ```bash
   sudo ./scripts/flash_emmc.sh
   ```

Готовые образы появятся в `output/ubuntu-emmc.img` и `output/ubuntu-sd.img`.

## Что публикуется отдельно

- **Git repository:** скрипты, конфигурация и документация.
- **Reference asset bundle:** проверенные U-Boot, Rockchip loader, kernel, DTB и kernel modules. Архив публикуется в GitHub Releases, а не коммитится в Git.
- **Ubuntu base image:** скачивается отдельно официальным скриптом `download_ubuntu.sh`; контрольная сумма сверяется с официальным `SHA256SUMS`.

Сборка reference bundle сопровождающим проекта:

```bash
./scripts/import_reference_assets.sh "$HOME/work" "$HOME/rk3568-br-release"
./scripts/create_reference_bundle.sh
```

Затем файл `dist/rk3568-ubuntu-reference-assets-v1.tar.gz` нужно загрузить в Release репозитория. Подробности и техническая документация находятся в [Wiki-странице](wiki/Ubuntu-RK3568.md).

## Структура

```text
rk3568-ubuntu/
├── README.md
├── .gitignore
├── scripts/
│   ├── download_ubuntu.sh
│   ├── import_reference_assets.sh
│   ├── create_reference_bundle.sh
│   ├── install_reference_bundle.sh
│   ├── build_images.sh
│   └── flash_emmc.sh
├── wiki/Ubuntu-RK3568.md
├── reference/       # локально распакованные эталонные бинарники, не в Git
├── inputs/ubuntu/   # Ubuntu base image, не в Git
├── work/            # временные файлы сборки, не в Git
├── output/          # готовые образы, не в Git
└── dist/            # архив reference bundle, не в Git
```

> Важно: `build_images.sh` и `flash_emmc.sh` работают только с файлами внутри каталога проекта. Внешние пути нужны только сопровождающему при первоначальном создании reference bundle.
