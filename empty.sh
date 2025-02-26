#!/bin/bash

# Функция для вывода справки
show_help() {
    echo "Использование: $0 [ОПЦИИ] [ПУТЬ]"
    echo "Удаляет пустые директории рекурсивно."
    echo
    echo "Опции:"
    echo "  -h, --help        Показать эту справку"
    echo "  -s, --silent      Тихий режим (без вывода сообщений)"
    echo "  -r, --remove-root Удалить корневую директорию, если она пуста"
    echo
    echo "По умолчанию используется текущая директория, если ПУТЬ не указан."
    exit 0
}

# Обработка параметров командной строки
REMOVE_ROOT=0
SILENT=0
TARGET_DIR="$(pwd)"

while [[ "$#" -gt 0 ]]; do
    case $1 in
        -h|--help)
            show_help
            ;;
        -s|--silent)
            SILENT=1
            ;;
        -r|--remove-root)
            REMOVE_ROOT=1
            ;;
        *)
            # Если аргумент не является опцией, считаем его путем
            if [[ -d "$1" ]]; then
                TARGET_DIR="$1"
            else
                echo "Ошибка: '$1' не является директорией."
                exit 1
            fi
            ;;
    esac
    shift
done

# Проверка существования директории
if [[ ! -d "$TARGET_DIR" ]]; then
    echo "Ошибка: Директория '$TARGET_DIR' не существует."
    exit 1
fi

# Для обеспечения корректной работы с пробелами в именах файлов
IFS=$'\n'

# Вывод информационного сообщения, если не включен тихий режим
if [[ $SILENT -eq 0 ]]; then
    echo "Поиск и удаление пустых папок в: $TARGET_DIR"
    if [[ $REMOVE_ROOT -eq 1 ]]; then
        echo "Включено удаление корневой папки, если она пуста."
    fi
fi

# Функция для удаления пустых директорий
remove_empty_dirs() {
    local dir="$1"
    local is_empty=1
    
    # Перебираем все элементы в директории
    for item in "$dir"/*; do
        # Если элемент существует
        if [[ -e "$item" ]]; then
            # Если это директория, рекурсивно проверяем её
            if [[ -d "$item" ]]; then
                # Если директория не пуста после удаления пустых поддиректорий
                if ! remove_empty_dirs "$item"; then
                    is_empty=0
                fi
            else
                # Если найден файл, директория не пуста
                is_empty=0
            fi
        fi
    done
    
    # Если директория пуста и это не корневая директория или разрешено удаление корневой
    if [[ $is_empty -eq 1 ]] && ([[ "$dir" != "$TARGET_DIR" ]] || [[ $REMOVE_ROOT -eq 1 ]]); then
        # Удаляем пустую директорию
        rmdir "$dir" 2>/dev/null
        if [[ $? -eq 0 ]]; then
            if [[ $SILENT -eq 0 ]]; then
                echo "Удалена пустая папка: $dir"
            fi
        else
            # Если удаление не удалось, директория не считается пустой
            is_empty=0
            if [[ $SILENT -eq 0 ]]; then
                echo "Ошибка при удалении папки: $dir"
            fi
        fi
    fi
    
    return $((1 - is_empty))
}

# Запускаем удаление пустых директорий
remove_empty_dirs "$TARGET_DIR"

# Выводим сообщение о завершении, если не включен тихий режим
if [[ $SILENT -eq 0 ]]; then
    echo "Готово!"
fi

exit 0
