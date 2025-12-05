# Max in Jail

<table>
<tr>
<td width="80">
<img src="logo.png" width="64" alt="Logo">
</td>
<td>

**Безопасная установка мессенджера Max на macOS через эмулятор Android**

Если у вас нет подходящего телефона для установки Max — теперь это не проблема. Одной командой вы можете безопасно установить его в эмуляторе.

</td>
</tr>
</table>

![Screenshot](screnshoot.png)

## Быстрый старт

### Вариант 1: Запуск одной командой

Скопируйте команду в терминал и запустите:

```bash
curl -fsSL https://raw.githubusercontent.com/a0s/max-in-jail/main/max-in-jail.sh | bash
```

### Вариант 2: Локальный запуск

Склонируйте репозиторий и запускайте локально:

```bash
git clone https://github.com/a0s/max-in-jail.git
cd max-in-jail
./max-in-jail.sh
```

## Использование

По умолчанию скрипт запускает эмулятор в фоновом режиме и завершается. Эмулятор продолжает работать.

Справка:

```bash
./max-in-jail.sh --help
```

Вывод:

```
Usage: ./max-in-jail.sh [OPTIONS]

Options:
  --attach     Run in foreground mode (follow logs, Ctrl+C stops emulator)
  --uninstall  Remove all data created by script
  -h, --help   Show this help message

By default, script runs in background mode:
  - Script exits, emulator keeps running
  - To stop emulator later, use: adb emu kill
```

## Системные требования

✅ Гарантированно работает на **Apple M2 Max**
✅ Скорее всего работает на всех **M-чипах**
⚠️ **Intel чипы** — под вопросом
