import 'package:flutter/material.dart';
import 'package:otzaria/navigation/bloc/navigation_bloc.dart';
import 'package:otzaria/navigation/bloc/navigation_event.dart';
import 'package:otzaria/navigation/bloc/navigation_state.dart';
import 'package:otzaria/tabs/bloc/tabs_bloc.dart';
import 'package:otzaria/tabs/bloc/tabs_event.dart';
import 'package:otzaria/models/books.dart';
import "package:flutter_bloc/flutter_bloc.dart";
import 'package:otzaria/tabs/models/pdf_tab.dart';
import 'package:otzaria/tabs/models/text_tab.dart';
import 'package:flutter_settings_screens/flutter_settings_screens.dart';
import 'package:otzaria/data/repository/data_repository.dart';
import 'package:otzaria/utils/text_manipulation.dart' as utils;
import 'package:otzaria/tabs/models/tab.dart';

void openBook(BuildContext context, Book book, int index, String searchQuery) {
  // שלב 1: חישוב הערך הבוליאני ושמירתו במשתנה נפרד
  // זה הופך את הקוד לקריא יותר ומונע את השגיאה
  final bool shouldOpenLeftPane =
      (Settings.getValue<bool>('key-pin-sidebar') ?? false) ||
      (Settings.getValue<bool>('key-default-sidebar-open') ?? false);

  // שלב 2: שימוש במשתנה החדש בשני המקרים
  if (book is TextBook) {
    context.read<TabsBloc>().add(AddTab(TextBookTab(
          book: book,
          index: index,
          searchText: searchQuery,
          openLeftPane: shouldOpenLeftPane, // שימוש במשתנה הפשוט
        )));
  } else if (book is PdfBook) {
    context.read<TabsBloc>().add(AddTab(PdfBookTab(
          book: book,
          pageNumber: index,
          openLeftPane: shouldOpenLeftPane, // שימוש באותו משתנה פשוט
        )));
  }

  context.read<NavigationBloc>().add(const NavigateToScreen(Screen.reading));
}

/// Opens a book from a text reference (like "בראשית א:א" or "רמב״ם הלכות שבת א:א")
Future<void> openBookFromReference({
  required BuildContext context,
  required String reference,
  required Function(OpenedTab) openBookCallback,
}) async {
  try {
    // Clean and normalize the reference
    String cleanRef = reference.trim();
    
    // Remove common prefixes that might appear in links
    cleanRef = cleanRef.replaceAll(RegExp(r'^(ראה|עיין|כמו|כמבואר ב|כדאיתא ב|וכן ב|ועיין ב)'), '').trim();
    
    // Try to parse the reference and find the book
    final bookInfo = await _parseBookReference(cleanRef);
    
    if (bookInfo != null) {
      // Create the appropriate tab based on book type
      final bool shouldOpenLeftPane =
          (Settings.getValue<bool>('key-pin-sidebar') ?? false) ||
          (Settings.getValue<bool>('key-default-sidebar-open') ?? false);

      if (bookInfo['book'] is TextBook) {
        final tab = TextBookTab(
          book: bookInfo['book'] as TextBook,
          index: bookInfo['index'] as int,
          openLeftPane: shouldOpenLeftPane,
        );
        openBookCallback(tab);
      } else if (bookInfo['book'] is PdfBook) {
        final tab = PdfBookTab(
          book: bookInfo['book'] as PdfBook,
          pageNumber: bookInfo['index'] as int,
          openLeftPane: shouldOpenLeftPane,
        );
        openBookCallback(tab);
      }
    } else {
      throw Exception('לא נמצא ספר מתאים לקישור: $reference');
    }
  } catch (e) {
    rethrow;
  }
}

/// Parses a book reference and returns book and index information
Future<Map<String, dynamic>?> _parseBookReference(String reference) async {
  try {
    final dataRepository = DataRepository.instance;
    final library = await dataRepository.library;
    final titleToPath = await dataRepository.titleToPath;
    
    // Split reference into book name and location
    final parts = reference.split(RegExp(r'[:\s]+'));
    if (parts.isEmpty) return null;
    
    String bookName = parts[0].trim();
    
    // Try to find exact match first
    Book? foundBook;
    String? bookPath;
    
    // Look for exact title match
    for (final book in library) {
      if (book.title == bookName) {
        foundBook = book;
        bookPath = titleToPath[book.title];
        break;
      }
    }
    
    // If no exact match, try partial matching
    if (foundBook == null) {
      for (final book in library) {
        if (book.title.contains(bookName) || bookName.contains(book.title)) {
          foundBook = book;
          bookPath = titleToPath[book.title];
          break;
        }
      }
    }
    
    // If still no match, try with common abbreviations
    if (foundBook == null) {
      final expandedName = utils.replaceParaphrases(bookName);
      for (final book in library) {
        if (book.title.contains(expandedName) || expandedName.contains(book.title)) {
          foundBook = book;
          bookPath = titleToPath[book.title];
          break;
        }
      }
    }
    
    if (foundBook == null) return null;
    
    // Parse the index/location (default to 0 if not specified)
    int index = 0;
    if (parts.length > 1) {
      // Try to parse chapter/verse or page number
      final locationPart = parts.sublist(1).join(' ').trim();
      index = _parseLocationToIndex(locationPart);
    }
    
    return {
      'book': foundBook,
      'index': index,
      'path': bookPath,
    };
  } catch (e) {
    return null;
  }
}

/// Converts a location string (like "א:א" or "דף ה") to an index
int _parseLocationToIndex(String location) {
  if (location.isEmpty) return 0;
  
  try {
    // Handle page references (דף X)
    if (location.contains('דף')) {
      final pageMatch = RegExp(r'דף\s*([א-ת\d]+)').firstMatch(location);
      if (pageMatch != null) {
        return _hebrewToNumber(pageMatch.group(1)!) - 1; // Convert to 0-based index
      }
    }
    
    // Handle chapter:verse format (א:א)
    if (location.contains(':')) {
      final parts = location.split(':');
      if (parts.length >= 2) {
        final chapter = _hebrewToNumber(parts[0].trim());
        final verse = _hebrewToNumber(parts[1].trim());
        // Simple approximation: chapter * 20 + verse (adjust as needed)
        return (chapter - 1) * 20 + (verse - 1);
      }
    }
    
    // Handle simple chapter reference
    return _hebrewToNumber(location) - 1; // Convert to 0-based index
  } catch (e) {
    return 0;
  }
}

/// Converts Hebrew letters to numbers (א=1, ב=2, etc.)
int _hebrewToNumber(String hebrew) {
  if (hebrew.isEmpty) return 1;
  
  // Remove any non-Hebrew characters
  final cleanHebrew = hebrew.replaceAll(RegExp(r'[^א-ת]'), '');
  if (cleanHebrew.isEmpty) {
    // Try to parse as regular number
    return int.tryParse(hebrew.replaceAll(RegExp(r'[^\d]'), '')) ?? 1;
  }
  
  int result = 0;
  for (int i = 0; i < cleanHebrew.length; i++) {
    final char = cleanHebrew[i];
    final value = _getHebrewLetterValue(char);
    result += value;
  }
  
  return result > 0 ? result : 1;
}

/// Gets the numeric value of a Hebrew letter
int _getHebrewLetterValue(String letter) {
  const hebrewValues = {
    'א': 1, 'ב': 2, 'ג': 3, 'ד': 4, 'ה': 5, 'ו': 6, 'ז': 7, 'ח': 8, 'ט': 9,
    'י': 10, 'כ': 20, 'ל': 30, 'מ': 40, 'נ': 50, 'ס': 60, 'ע': 70, 'פ': 80, 'צ': 90,
    'ק': 100, 'ר': 200, 'ש': 300, 'ת': 400,
    // Final forms
    'ך': 20, 'ם': 40, 'ן': 50, 'ף': 80, 'ץ': 90,
  };
  
  return hebrewValues[letter] ?? 1;
}
