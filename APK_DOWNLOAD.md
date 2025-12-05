# Инструкция по скачиванию APK мессенджера Max

## Проблема

Автоматическое скачивание APK из интернета может не работать из-за:

- Изменений в структуре сайтов (APKMirror, APKPure)
- Необходимости авторизации
- Отсутствия приложения на этих сайтах

## Решения

### Вариант 1: Скачать APK вручную (рекомендуется)

1. Найдите APK файл мессенджера Max одним из способов:
   - Скачайте с официального сайта Max (если доступно)
   - Используйте APKMirror: <https://www.apkmirror.com/apk/max-messenger/>
   - Используйте APKPure: <https://apkpure.com/ru.max.messenger/>
   - Попросите кого-то с Android устройством экспортировать APK

2. Сохраните файл как `max-messenger.apk` в директорию `apk/`:

   ```bash
   mkdir -p /Users/a0s/my/max-in-box/apk
   # Скопируйте скачанный APK в эту директорию с именем max-messenger.apk
   ```

3. Запустите скрипт снова - он обнаружит существующий APK и пропустит скачивание

### Вариант 2: Использовать apkeep (требует Google аккаунт)

1. Установите apkeep:

   ```bash
   pip3 install apkeep
   ```

2. Установите переменные окружения с вашими данными Google:

   ```bash
   export GOOGLE_EMAIL="your-email@gmail.com"
   export GOOGLE_PASSWORD="your-password"
   export MAX_PACKAGE_NAME="ru.max.messenger"
   ```

3. Запустите скрипт:

   ```bash
   ./max-in-box.sh
   ```

**Внимание**: Использование apkeep требует ваших учетных данных Google. Используйте на свой риск.

### Вариант 3: Указать точный package name

Если вы знаете точный package name приложения, установите его:

```bash
export MAX_PACKAGE_NAME="ru.max.messenger"  # или другой правильный package name
./max-in-box.sh
```

## Как найти package name

1. Если приложение установлено на Android устройстве:

   ```bash
   adb shell pm list packages | grep max
   ```

2. Посмотрите в URL Google Play Store:
   - Например: `https://play.google.com/store/apps/details?id=ru.max.messenger`
   - Package name будет после `id=`

3. Используйте онлайн сервисы для поиска package name по названию приложения

## Проверка скачанного APK

После скачивания APK, проверьте что файл валидный:

```bash
file apk/max-messenger.apk
# Должно показать: Android package
```

Если файл невалидный, удалите его и попробуйте скачать снова:

```bash
rm apk/max-messenger.apk
```
