#!/usr/bin/env python3
# -*- coding: utf-8 -*-

import os
import sys
import shutil
import zipfile
import xml.etree.ElementTree as ET
import re
from pathlib import Path


def format_author_name(author_name):
    """
    Форматирует имя автора, перемещая фамилию в начало.
    Например: "Иван Петров" -> "Петров Иван"
    """
    if not author_name or author_name == 'Unknown Author':
        return 'Unknown Author'
    
    # Разделяем имя на части
    parts = author_name.split()
    
    # Если имя состоит из одного слова, возвращаем его как есть
    if len(parts) == 1:
        return author_name
    
    # Предполагаем, что последнее слово - фамилия, перемещаем её в начало
    # Формат: Фамилия Имя [Отчество]
    return f"{parts[-1]} {' '.join(parts[:-1])}"

def extract_metadata_from_epub(epub_path):
    """
    Извлекает метаданные из epub файла.
    Возвращает словарь с автором, названием и серией.
    """
    metadata = {
        'author': 'Unknown Author',
        'title': 'Unknown Title',
        'series': None,
        'series_index': None
    }
    
    try:
        with zipfile.ZipFile(epub_path, 'r') as zip_ref:
            # Ищем OPF файл
            container_path = None
            for file_name in zip_ref.namelist():
                if file_name.endswith('container.xml'):
                    container_path = file_name
                    break
            
            if container_path is None:
                return metadata
            
            # Извлекаем путь к OPF файлу из container.xml
            container_data = zip_ref.read(container_path)
            container_root = ET.fromstring(container_data)
            ns = {'ns': 'urn:oasis:names:tc:opendocument:xmlns:container'}
            opf_path = container_root.find('.//ns:rootfile', ns).get('full-path')
            
            # Определяем базовый путь для относительных ссылок в OPF
            opf_dir = os.path.dirname(opf_path)
            if opf_dir:
                opf_dir = opf_dir + '/'
            
            # Извлекаем метаданные из OPF файла
            opf_data = zip_ref.read(opf_path)
            opf_root = ET.fromstring(opf_data)
            
            # Находим автора и название в метаданных
            dc_ns = {'dc': 'http://purl.org/dc/elements/1.1/'}
            
            # Получаем автора
            author_elem = opf_root.find('.//dc:creator', dc_ns)
            if author_elem is not None and author_elem.text:
                original_author = author_elem.text.strip()
                # Форматируем имя автора, перемещая фамилию в начало
                metadata['author'] = format_author_name(original_author)
            
            # Получаем название
            title_elem = opf_root.find('.//dc:title', dc_ns)
            if title_elem is not None and title_elem.text:
                metadata['title'] = title_elem.text.strip()
            
            # Ищем информацию о серии
            # Сначала проверим метаданные calibre
            meta_tags = opf_root.findall('.//{http://www.idpf.org/2007/opf}meta')
            for meta in meta_tags:
                name = meta.get('name')
                content = meta.get('content')
                
                if name == 'calibre:series' and content:
                    metadata['series'] = content.strip()
                elif name == 'calibre:series_index' and content:
                    try:
                        metadata['series_index'] = float(content.strip())
                    except ValueError:
                        metadata['series_index'] = 0
            
            # Если серия не найдена в метаданных calibre, поищем в dc:subject
            if metadata['series'] is None:
                subjects = opf_root.findall('.//dc:subject', dc_ns)
                for subject in subjects:
                    if subject.text and (':' in subject.text or ' - ' in subject.text):
                        # Возможный формат серии: "Серия: Название" или "Серия - Название"
                        if ':' in subject.text:
                            parts = subject.text.split(':', 1)
                        else:
                            parts = subject.text.split(' - ', 1)
                        
                        if len(parts) == 2 and parts[0].lower() in ['серия', 'series', 'цикл', 'cycle']:
                            metadata['series'] = parts[1].strip()
                            break
            
            # Если серия все еще не найдена, попробуем искать в названии
            if metadata['series'] is None and ' - ' in metadata['title']:
                # Возможный формат: "Название серии - Название книги"
                parts = metadata['title'].split(' - ', 1)
                if len(parts) == 2:
                    # Это эвристика и может давать ложные срабатывания
                    # Получаем больше контекста, чтобы проверить, если есть другие книги с таким же префиксом
                    metadata['potential_series'] = parts[0].strip()
                    
            # Очистка значений от недопустимых символов в файловой системе
            metadata['author'] = clean_filename(metadata['author'])
            metadata['title'] = clean_filename(metadata['title'])
            if metadata['series']:
                metadata['series'] = clean_filename(metadata['series'])
                
    except Exception as e:
        print(f"Ошибка при обработке {epub_path}: {str(e)}")
    
    return metadata


def clean_filename(name):
    """
    Очищает строку от символов, недопустимых в именах файлов.
    """
    if name:
        # Удаляем символы, недопустимые в именах файлов
        return re.sub(r'[\\/*?:"<>|]', '', name)
    return name


def find_series_in_collection(epub_files):
    """
    Анализирует коллекцию книг для выявления серий на основе схожих названий.
    Возвращает словарь с потенциальными сериями.
    """
    series_candidates = {}
    
    # Собираем информацию о потенциальных сериях
    for epub_file in epub_files:
        metadata = extract_metadata_from_epub(epub_file)
        if 'potential_series' in metadata and metadata['potential_series']:
            series_name = metadata['potential_series']
            if series_name not in series_candidates:
                series_candidates[series_name] = []
            series_candidates[series_name].append(epub_file)
    
    # Оставляем только те серии, где есть несколько книг
    return {series: files for series, files in series_candidates.items() if len(files) > 1}


def organize_epub_files(source_folder, recursive=True):
    """
    Организует epub файлы из source_folder по подпапкам с именами авторов и сериями.
    
    Args:
        source_folder: Путь к исходной папке с книгами
        recursive: Если True, просматривает подпапки в source_folder
    """
    source_path = Path(source_folder)
    
    # Проверяем, существует ли указанная папка
    if not source_path.exists() or not source_path.is_dir():
        print(f"Ошибка: Папка '{source_folder}' не существует.")
        return
    
    # Находим все epub файлы
    if recursive:
        epub_files = list(source_path.glob('**/*.epub'))
    else:
        epub_files = list(source_path.glob('*.epub'))
    
    if not epub_files:
        print(f"В папке '{source_folder}' epub файлы не найдены.")
        return
    
    print(f"Найдено {len(epub_files)} epub файлов.")
    
    # Первый проход: распределяем книги по авторам
    for epub_file in epub_files:
        # Получаем метаданные
        metadata = extract_metadata_from_epub(epub_file)
        
        # Создаем папку автора, если её нет
        author_folder = source_path / metadata['author']
        author_folder.mkdir(exist_ok=True)
        
        # Определяем новый путь файла
        new_file_path = author_folder / epub_file.name
        
        # Перемещаем файл в папку автора, если он еще не в этой папке
        if epub_file.parent != author_folder:
            # Проверяем, не существует ли уже такой файл
            if new_file_path.exists():
                print(f"Файл {new_file_path} уже существует, пропускаем.")
                continue
            
            # Перемещаем файл
            try:
                shutil.move(str(epub_file), str(new_file_path))
                print(f"Перемещен: {epub_file.name} -> {metadata['author']}/{epub_file.name}")
            except Exception as e:
                print(f"Ошибка при перемещении {epub_file}: {str(e)}")
    
    # Второй проход: организуем книги по сериям внутри папок авторов
    author_folders = [f for f in source_path.iterdir() if f.is_dir()]
    
    for author_folder in author_folders:
        # Получаем все epub файлы в папке автора
        author_epub_files = list(author_folder.glob('*.epub'))
        
        if not author_epub_files:
            continue
        
        # Словарь для хранения книг по сериям
        series_books = {}
        
        # Группируем книги по сериям
        for epub_file in author_epub_files:
            metadata = extract_metadata_from_epub(epub_file)
            
            if metadata['series']:
                if metadata['series'] not in series_books:
                    series_books[metadata['series']] = []
                series_books[metadata['series']].append((epub_file, metadata))
        
        # Перемещаем книги в папки серий
        for series_name, books in series_books.items():
            # Создаем папку серии
            series_folder = author_folder / series_name
            series_folder.mkdir(exist_ok=True)
            
            # Перемещаем каждую книгу
            for epub_file, metadata in books:
                # Формируем новое имя файла с учетом индекса серии, если он есть
                new_filename = epub_file.name
                if metadata['series_index'] is not None:
                    # Извлекаем расширение файла
                    basename, ext = os.path.splitext(epub_file.name)
                    # Форматируем индекс серии (например, 1.5 -> "1.5", 2 -> "2.0")
                    index_str = f"{metadata['series_index']:.1f}".rstrip('0').rstrip('.') if metadata['series_index'] % 1 == 0 else f"{metadata['series_index']:.1f}"
                    # Создаем новое имя файла
                    new_filename = f"{index_str} - {basename}{ext}"
                
                new_file_path = series_folder / new_filename
                
                # Проверяем, не существует ли уже такой файл
                if new_file_path.exists():
                    print(f"Файл {new_file_path} уже существует, пропускаем.")
                    continue
                
                # Перемещаем файл
                try:
                    shutil.move(str(epub_file), str(new_file_path))
                    print(f"Перемещен в серию: {epub_file.name} -> {metadata['author']}/{series_name}/{new_filename}")
                except Exception as e:
                    print(f"Ошибка при перемещении {epub_file} в серию: {str(e)}")


if __name__ == "__main__":
    # Получаем папку из аргументов командной строки или используем текущую
    if len(sys.argv) > 1:
        folder_path = sys.argv[1]
    else:
        folder_path = os.getcwd()
    
    # Определяем, нужно ли рекурсивно обрабатывать подпапки
    recursive = True
    if len(sys.argv) > 2:
        if sys.argv[2].lower() in ['false', 'no', '0', 'n']:
            recursive = False
    
    print(f"Организация epub файлов в папке: {folder_path}")
    print(f"Рекурсивный режим: {'включен' if recursive else 'выключен'}")
    organize_epub_files(folder_path, recursive)
    print("Готово!")
