#!/bin/bash

# Функция для вывода справки
show_help() {
    echo "Использование: $0 [ОПЦИИ] [ПУТЬ]"
    echo "Создает отсортированный по авторам список всех epub книг."
    echo
    echo "Опции:"
    echo "  -h, --help        Показать эту справку"
    echo "  -o, --output FILE Указать выходной файл (по умолчанию: booklist.txt)"
    echo "  -f, --full-path   Включить в список полный путь к файлам"
    echo "  -n, --no-header   Не добавлять заголовки авторов"
    echo "  -t, --title       Извлекать и отображать название книги из метаданных"
    echo "  -d, --duplicates  Обнаруживать и отмечать дубликаты книг"
    echo "  -u, --update      Обновить существующий список (добавить только новые книги)"
    echo "  -D, --dupes-file  Указать файл для сохранения списка дубликатов (по умолчанию: dupes.txt)"
    echo
    echo "По умолчанию используется текущая директория, если ПУТЬ не указан."
    exit 0
}

# Функция для извлечения названия книги из EPUB файла
extract_title_from_epub() {
    local epub_file="$1"
    local title=""
    
    # Находим OPF файл в EPUB
    local container_file=$(unzip -l "$epub_file" 2>/dev/null | grep -o "[^ ]*container.xml" | head -1)
    
    if [[ -n "$container_file" ]]; then
        # Извлекаем путь к OPF файлу из container.xml
        local opf_path=$(unzip -p "$epub_file" "$container_file" 2>/dev/null | grep -o 'full-path="[^"]*"' | head -1 | cut -d'"' -f2)
        
        if [[ -n "$opf_path" ]]; then
            # Извлекаем название из OPF файла
            local extracted_title=$(unzip -p "$epub_file" "$opf_path" 2>/dev/null | grep -o '<dc:title[^>]*>.*</dc:title>' | head -1 | sed -E 's/<dc:title[^>]*>(.*)<\/dc:title>/\1/')
            
            if [[ -n "$extracted_title" ]]; then
                # Удаляем XML-спецсимволы
                title=$(echo "$extracted_title" | sed 's/&lt;/</g; s/&gt;/>/g; s/&amp;/\&/g; s/&quot;/"/g; s/&apos;/'"'"'/g')
            fi
        fi
    fi
    
    echo "$title"
}

# Функция для получения автора из пути к файлу
get_author_from_path() {
    local path="$1"
    local base_dir="$(realpath "$TARGET_DIR")"
    local file_dir="$(dirname "$(realpath "$path")")"
    
    # Удаляем базовый путь из полного пути
    local rel_path="${file_dir#$base_dir/}"
    
    # Если мы в корневой директории или ниже неё
    if [[ -z "$rel_path" ]]; then
        echo "Неизвестный автор"
    else
        # Извлекаем первую часть пути - это должна быть папка автора
        local author=$(echo "$rel_path" | cut -d'/' -f1)
        echo "$author"
    fi
}

# Функция для получения серии из пути к файлу
get_series_from_path() {
    local path="$1"
    local base_dir="$(realpath "$TARGET_DIR")"
    local file_dir="$(dirname "$(realpath "$path")")"
    
    # Удаляем базовый путь из полного пути
    local rel_path="${file_dir#$base_dir/}"
    
    # Проверяем, есть ли в пути хотя бы два уровня (автор/серия)
    if [[ "$rel_path" == */* ]]; then
        # Получаем имя второго уровня - предположительно серия
        local series=$(echo "$rel_path" | cut -d'/' -f2)
        if [[ -n "$series" ]]; then
            echo "$series"
        fi
    fi
}

# Функция для создания уникального идентификатора книги
create_book_id() {
    local author="$1"
    local title="$2"
    # Используем автора и название для создания уникального ID
    # Удаляем пробелы и переводим в нижний регистр
    local author_clean=$(echo "$author" | tr -d ' ' | tr '[:upper:]' '[:lower:]')
    local title_clean=$(echo "$title" | tr -d ' ' | tr '[:upper:]' '[:lower:]')
    echo "${author_clean}_${title_clean}"
}

# Функция для чтения существующего списка книг
read_existing_booklist() {
    local file="$1"
    local ids_file="$2"
    
    if [[ ! -f "$file" ]]; then
        return
    fi
    
    local current_author=""
    local in_book_section=0
    
    while IFS= read -r line; do
        # Если строка начинается с === это заголовок автора
        if [[ "$line" =~ ^===\ (.*)\ ===$ ]]; then
            current_author="${BASH_REMATCH[1]}"
            in_book_section=1
        # Если строка пустая, или начинается с "Всего книг", мы вышли из секции книг
        elif [[ -z "$line" || "$line" =~ ^Всего\ книг:\ [0-9]+$ ]]; then
            in_book_section=0
        # Иначе, если мы внутри секции книг, значит это книга
        elif [[ $in_book_section -eq 1 ]]; then
            # Проверяем, есть ли название в кавычках
            if [[ "$line" =~ ^\"(.*)\"\ -\ (.*) ]]; then
                local title="${BASH_REMATCH[1]}"
                local book_id=$(create_book_id "$current_author" "$title")
                echo "$book_id" >> "$ids_file"
            else
                # Если названия нет, используем имя файла
                local filename=$(basename "$line")
                local book_id=$(create_book_id "$current_author" "$filename")
                echo "$book_id" >> "$ids_file"
            fi
        fi
    done < "$file"
}

# Обработка параметров командной строки
OUTPUT_FILE="booklist.txt"
DUPES_FILE="dupes.txt"
TARGET_DIR="$(pwd)"
FULL_PATH=0
NO_HEADER=0
EXTRACT_TITLE=1
DETECT_DUPES=0
UPDATE_MODE=0

while [[ "$#" -gt 0 ]]; do
    case $1 in
        -h|--help)
            show_help
            ;;
        -o|--output)
            OUTPUT_FILE="$2"
            shift
            ;;
        -f|--full-path)
            FULL_PATH=1
            ;;
        -n|--no-header)
            NO_HEADER=1
            ;;
        -t|--title)
            EXTRACT_TITLE=1
            ;;
        -d|--duplicates)
            DETECT_DUPES=1
            ;;
        -u|--update)
            UPDATE_MODE=1
            ;;
        -D|--dupes-file)
            DUPES_FILE="$2"
            shift
            ;;
        --)
            shift
            break
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

# Начинаем поиск книг
echo "Создание списка epub книг в: $TARGET_DIR"
echo "Результат будет сохранен в: $OUTPUT_FILE"

if [[ $EXTRACT_TITLE -eq 1 ]]; then
    echo "Включено извлечение названий книг из метаданных"
fi

if [[ $DETECT_DUPES -eq 1 ]]; then
    echo "Включено обнаружение дубликатов (будут сохранены в $DUPES_FILE)"
fi

if [[ $UPDATE_MODE -eq 1 ]]; then
    echo "Режим обновления: добавление только новых книг"
fi

# Создаем временные файлы
TMP_FILE=$(mktemp)
TMP_LIST=$(mktemp)
TMP_EXISTING_IDS=$(mktemp)
TMP_DUPES=$(mktemp)

# Для обработки файлов с пробелами
OLDIFS="$IFS"
IFS=$'\n'

# Если включен режим обновления, читаем существующий список книг
if [[ $UPDATE_MODE -eq 1 && -f "$OUTPUT_FILE" ]]; then
    echo "Чтение существующего списка книг: $OUTPUT_FILE"
    read_existing_booklist "$OUTPUT_FILE" "$TMP_EXISTING_IDS"
    echo "Найдено $(wc -l < "$TMP_EXISTING_IDS") книг в существующем списке"
fi

# Находим все epub файлы
echo "Поиск книг во всех подпапках..."
find "$TARGET_DIR" -type f -name "*.epub" > "$TMP_LIST"

# Проверяем, есть ли файлы
if [[ ! -s "$TMP_LIST" ]]; then
    echo "ПРЕДУПРЕЖДЕНИЕ: EPUB файлы не найдены в $TARGET_DIR"
    echo "EPUB книги не найдены в указанной директории." > "$OUTPUT_FILE"
    rm "$TMP_LIST" "$TMP_FILE" "$TMP_EXISTING_IDS" "$TMP_DUPES" 2>/dev/null
    exit 0
fi

# Обрабатываем каждый найденный файл
echo "Обработка файлов..."
total_processed=0
total_files=$(wc -l < "$TMP_LIST")
new_books=0
duplicate_books=0

# Массив для отслеживания уникальных книг в текущем сеансе
declare -A book_ids

while read -r file; do
    # Показываем прогресс
    ((total_processed++))
    if [[ $((total_processed % 10)) -eq 0 || $total_processed -eq $total_files ]]; then
        echo -ne "Обработано $total_processed из $total_files книг\r"
    fi
    
    # Получаем автора и серию из пути
    author=$(get_author_from_path "$file")
    series=$(get_series_from_path "$file")
    filename=$(basename "$file")
    
    # Извлекаем название книги, если включена опция
    book_title=""
    if [[ $EXTRACT_TITLE -eq 1 ]]; then
        book_title=$(extract_title_from_epub "$file")
    fi
    
    # Создаем идентификатор книги для проверки дубликатов
    if [[ -n "$book_title" ]]; then
        book_id=$(create_book_id "$author" "$book_title")
    else
        book_id=$(create_book_id "$author" "$filename")
    fi
    
    # Проверяем, является ли книга дубликатом
    is_duplicate=0
    
    # Проверяем, есть ли книга уже в существующем списке
    if [[ $UPDATE_MODE -eq 1 ]]; then
        if grep -q "^$book_id$" "$TMP_EXISTING_IDS"; then
            is_duplicate=1
        fi
    fi
    
    # Проверяем, не встречался ли такой ID уже в текущем сеансе
    if [[ ${book_ids[$book_id]+_} ]]; then
        is_duplicate=1
        # Сохраняем информацию о дубликате для отчета
        if [[ $DETECT_DUPES -eq 1 ]]; then
            if [[ -n "$book_title" ]]; then
                echo "\"$book_title\" ($author): $file" >> "$TMP_DUPES"
            else
                echo "$filename ($author): $file" >> "$TMP_DUPES"
            fi
            ((duplicate_books++))
        fi
    else
        book_ids[$book_id]=1
        ((new_books++))
    fi
    
    # Пропускаем дубликаты в режиме обновления
    if [[ $UPDATE_MODE -eq 1 && $is_duplicate -eq 1 ]]; then
        continue
    fi
    
    # Определяем путь для вывода
    if [[ $FULL_PATH -eq 1 ]]; then
        if [[ -n "$book_title" ]]; then
            if [[ $DETECT_DUPES -eq 1 && $is_duplicate -eq 1 ]]; then
                book_path="\"$book_title\" - $file [ДУБЛИКАТ]"
            else
                book_path="\"$book_title\" - $file"
            fi
        else
            if [[ $DETECT_DUPES -eq 1 && $is_duplicate -eq 1 ]]; then
                book_path="$file [ДУБЛИКАТ]"
            else
                book_path="$file"
            fi
        fi
    else
        # Формируем строку вывода
        if [[ -n "$book_title" ]]; then
            if [[ -n "$series" ]]; then
                if [[ $DETECT_DUPES -eq 1 && $is_duplicate -eq 1 ]]; then
                    book_path="\"$book_title\" - [$series] $filename [ДУБЛИКАТ]"
                else
                    book_path="\"$book_title\" - [$series] $filename"
                fi
            else
                if [[ $DETECT_DUPES -eq 1 && $is_duplicate -eq 1 ]]; then
                    book_path="\"$book_title\" - $filename [ДУБЛИКАТ]"
                else
                    book_path="\"$book_title\" - $filename"
                fi
            fi
        else
            if [[ -n "$series" ]]; then
                if [[ $DETECT_DUPES -eq 1 && $is_duplicate -eq 1 ]]; then
                    book_path="[$series] $filename [ДУБЛИКАТ]"
                else
                    book_path="[$series] $filename"
                fi
            else
                if [[ $DETECT_DUPES -eq 1 && $is_duplicate -eq 1 ]]; then
                    book_path="$filename [ДУБЛИКАТ]"
                else
                    book_path="$filename"
                fi
            fi
        fi
    fi
    
    # Записываем во временный файл формат: Автор|Путь к книге
    echo "$author|$book_path" >> "$TMP_FILE"
    
done < "$TMP_LIST"

echo -e "\nОбработка файлов завершена."

# Проверяем, есть ли найденные книги
if [[ ! -s "$TMP_FILE" ]]; then
    if [[ $UPDATE_MODE -eq 1 ]]; then
        echo "Новых книг не найдено. Существующий список не изменен."
        rm "$TMP_FILE" "$TMP_LIST" "$TMP_EXISTING_IDS" "$TMP_DUPES" 2>/dev/null
        exit 0
    else
        echo "EPUB книги не найдены в указанной директории."
        echo "EPUB книги не найдены в указанной директории." > "$OUTPUT_FILE"
        rm "$TMP_FILE" "$TMP_LIST" "$TMP_EXISTING_IDS" "$TMP_DUPES" 2>/dev/null
        exit 0
    fi
fi

# Если мы в режиме обновления и у нас есть существующий файл
if [[ $UPDATE_MODE -eq 1 && -f "$OUTPUT_FILE" ]]; then
    # Если нет новых книг, выходим
    if [[ $new_books -eq 0 ]]; then
        echo "Новых книг не найдено. Существующий список не изменен."
        rm "$TMP_FILE" "$TMP_LIST" "$TMP_EXISTING_IDS" "$TMP_DUPES" 2>/dev/null
        exit 0
    fi
    
    # Иначе, создаем временную копию старого файла
    TMP_OLD=$(mktemp)
    cp "$OUTPUT_FILE" "$TMP_OLD"
    
    # Очищаем выходной файл для полной перезаписи
    > "$OUTPUT_FILE"
    
    # Копируем все строки до "Всего книг" из старого файла
    sed '/^Всего книг:/,$d' "$TMP_OLD" > "$OUTPUT_FILE"
    
    # Добавляем пустую строку, если файл не заканчивается пустой строкой
    if [[ -s "$OUTPUT_FILE" && "$(tail -c 1 "$OUTPUT_FILE" | wc -l)" -eq 0 ]]; then
        echo "" >> "$OUTPUT_FILE"
    fi
    
    # Подсчитываем общее количество книг (старые + новые)
    total_old_books=$(grep -v "^===" "$TMP_OLD" | grep -v "^$" | grep -v "^Всего книг:" | wc -l)
    TOTAL_BOOKS=$((total_old_books + new_books))
else
    # Подсчитываем общее количество книг
    TOTAL_BOOKS=$(wc -l < "$TMP_FILE")
    
    # Создаем пустой выходной файл
    > "$OUTPUT_FILE"
fi

# Сортируем результаты
sort "$TMP_FILE" > "${TMP_FILE}.sorted"

# Обрабатываем отсортированные результаты и формируем финальный список
current_author=""
while IFS="|" read -r author book_path; do
    # Если автор изменился и заголовки включены
    if [[ "$current_author" != "$author" && $NO_HEADER -eq 0 ]]; then
        # Добавляем пустую строку между авторами, кроме первого
        if [[ -n "$current_author" ]]; then
            echo "" >> "$OUTPUT_FILE"
        fi
        echo "=== $author ===" >> "$OUTPUT_FILE"
        current_author="$author"
    fi
    
    # Добавляем книгу в список
    echo "$book_path" >> "$OUTPUT_FILE"
done < "${TMP_FILE}.sorted"

# Добавляем информацию о количестве книг в конец файла
echo "" >> "$OUTPUT_FILE"
echo "Всего книг: $TOTAL_BOOKS" >> "$OUTPUT_FILE"

# Если мы в режиме обнаружения дубликатов и есть дубликаты, сохраняем их в отдельный файл
if [[ $DETECT_DUPES -eq 1 && -s "$TMP_DUPES" ]]; then
    echo "Найдено $duplicate_books дубликатов. Сохранение списка в $DUPES_FILE"
    echo "Список дубликатов книг" > "$DUPES_FILE"
    echo "Дата создания: $(date)" >> "$DUPES_FILE"
    echo "" >> "$DUPES_FILE"
    cat "$TMP_DUPES" >> "$DUPES_FILE"
    echo "" >> "$DUPES_FILE"
    echo "Всего дубликатов: $duplicate_books" >> "$DUPES_FILE"
fi

# Восстанавливаем IFS
IFS="$OLDIFS"

# Очистка временных файлов
rm "$TMP_FILE" "${TMP_FILE}.sorted" "$TMP_LIST" "$TMP_EXISTING_IDS" "$TMP_DUPES" "$TMP_OLD" 2>/dev/null

# Выводим итоговую информацию
if [[ $UPDATE_MODE -eq 1 ]]; then
    echo "Добавлено $new_books новых книг в список."
else
    echo "Создан новый список из $TOTAL_BOOKS книг."
fi

if [[ $DETECT_DUPES -eq 1 ]]; then
    echo "Обнаружено $duplicate_books дубликатов."
fi

echo "Список сохранен в $OUTPUT_FILE."
exit 0