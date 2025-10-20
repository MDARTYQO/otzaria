import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_html/flutter_html.dart';
import 'package:flutter_context_menu/flutter_context_menu.dart' as ctx;
import 'package:otzaria/settings/settings_bloc.dart';
import 'package:otzaria/settings/settings_state.dart';
import 'package:otzaria/tabs/bloc/tabs_bloc.dart';
import 'package:otzaria/tabs/bloc/tabs_state.dart';
import 'package:otzaria/text_book/bloc/text_book_bloc.dart';
import 'package:otzaria/text_book/bloc/text_book_state.dart';
import 'package:otzaria/tabs/models/text_tab.dart';
import 'package:otzaria/text_book/view/combined_view/commentary_list_for_combined_view.dart';
import 'package:otzaria/text_book/view/links_screen.dart';
import 'package:otzaria/widgets/progressive_scrolling.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';
import 'package:flutter_settings_screens/flutter_settings_screens.dart';
import 'package:otzaria/tabs/models/tab.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/utils/text_manipulation.dart' as utils;
import 'package:otzaria/text_book/bloc/text_book_event.dart';

class CombinedView extends StatefulWidget {
  CombinedView({
    super.key,
    required this.data,
    required this.openBookCallback,
    required this.openLeftPaneTab,
    required this.textSize,
    required this.showSplitedView,
    required this.tab,
  });

  final List<String> data;
  final Function(OpenedTab) openBookCallback;
  final void Function(int) openLeftPaneTab;
  final ValueNotifier<bool> showSplitedView;
  final double textSize;
  final TextBookTab tab;

  @override
  State<CombinedView> createState() => _CombinedViewState();
}

class _CombinedViewState extends State<CombinedView> {
  final GlobalKey<SelectionAreaState> _selectionKey =
      GlobalKey<SelectionAreaState>();

  /// טיפול בלחיצה על קישורים לספרים
  void _handleBookLink(String? url) {
    if (url == null || url.isEmpty) return;
    
    // אם זה קישור לספר מקומי (מתחיל ב-book://)
    if (url.startsWith('book://')) {
      final urlContent = url.substring(7); // הסרת הקידומת book://
      
      // בדיקה אם יש כותרת או דף ספציפי (מופרד ב-#)
      final parts = urlContent.split('#');
      final bookTitle = parts[0];
      int pageIndex = 0;
      String? searchText;
      
      // אם יש חלק ספציפי אחרי ה-#
      if (parts.length > 1) {
        final fragment = parts[1];
        
        // אם זה דף (מתחיל ב-"דף_")
        if (fragment.startsWith('דף_')) {
          final pageStr = fragment.substring(3); // הסרת "דף_"
          pageIndex = _hebrewToNumber(pageStr);
        } else {
          // אחרת, זה כותרת לחיפוש
          searchText = fragment.replaceAll('_', ' ');
        }
      }
      
      // פתיחת הספר בתוכנה
      final tab = TextBookTab(
        book: TextBook(title: bookTitle),
        index: pageIndex,
        openLeftPane: (Settings.getValue<bool>('key-pin-sidebar') ?? false) ||
            (Settings.getValue<bool>('key-default-sidebar-open') ?? false),
      );
      
      widget.openBookCallback(tab);
      
      // אם יש טקסט לחיפוש, נבצע חיפוש אחרי פתיחת הספר
      if (searchText != null && searchText.isNotEmpty) {
        // נחכה רגע שהספר ייפתח ואז נבצע חיפוש וניווט
        Future.delayed(const Duration(milliseconds: 500), () {
          _searchAndNavigateToText(searchText);
        });
      }
    }
  }
  
  /// המרת אותיות עבריות למספרים (פשוט)
  int _hebrewToNumber(String hebrew) {
    // מפת המרה בסיסית
    final Map<String, int> hebrewNumerals = {
      'א': 1, 'ב': 2, 'ג': 3, 'ד': 4, 'ה': 5,
      'ו': 6, 'ז': 7, 'ח': 8, 'ט': 9, 'י': 10,
      'כ': 20, 'ל': 30, 'מ': 40, 'נ': 50,
      'ס': 60, 'ע': 70, 'פ': 80, 'צ': 90,
      'ק': 100, 'ר': 200, 'ש': 300, 'ת': 400,
    };
    
    int result = 0;
    for (int i = 0; i < hebrew.length; i++) {
      final char = hebrew[i];
      if (hebrewNumerals.containsKey(char)) {
        result += hebrewNumerals[char]!;
      }
    }
    
    // אם יש עמוד א' או ב', נתאים את האינדקס
    if (hebrew.endsWith('א')) {
      result = (result - 1) * 2; // עמוד א
    } else if (hebrew.endsWith('ב')) {
      result = (result - 1) * 2 + 1; // עמוד ב
    } else {
      result = result > 0 ? result - 1 : 0;
    }
    
    return result;
  }

  /// חיפוש טקסט בספר וניווט אליו
  void _searchAndNavigateToText(String searchText) {
    final currentState = context.read<TextBookBloc>().state;
    if (currentState is! TextBookLoaded) return;

    // חיפוש הטקסט בתוכן הספר
    int foundIndex = -1;
    for (int i = 0; i < widget.data.length; i++) {
      final content = widget.data[i];
      // חיפוש הטקסט (ללא רגישות לרווחים וסימני פיסוק)
      final cleanContent = utils.removeVolwels(content.toLowerCase());
      final cleanSearchText = utils.removeVolwels(searchText.toLowerCase());
      
      if (cleanContent.contains(cleanSearchText)) {
        foundIndex = i;
        break;
      }
    }

    if (foundIndex != -1) {
      // עדכון טקסט החיפוש להדגשה
      context.read<TextBookBloc>().add(UpdateSearchText(searchText));
      
      // ניווט לאינדקס שנמצא
      currentState.scrollController.scrollTo(
        index: foundIndex,
        duration: const Duration(milliseconds: 500),
      );
      
      // עדכון האינדקס הנבחר
      context.read<TextBookBloc>().add(UpdateSelectedIndex(foundIndex));
    }
  }

  /// helper קטן שמחזיר רשימת MenuEntry מקבוצה אחת
  List<ctx.MenuItem<void>> _buildGroup(
    List<String>? group,
    TextBookLoaded st,
  ) {
    if (group == null || group.isEmpty) return const [];
    return group.map((title) {
      // בודקים אם הפרשן הנוכחי פעיל
      final bool isActive = st.activeCommentators.contains(title);

      return ctx.MenuItem<void>(
        label: title,
        // הוספה: מוסיפים אייקון V אם הפרשן פעיל
        icon: isActive ? Icons.check : null,
        onSelected: () {
          final current = List<String>.from(st.activeCommentators);
          current.contains(title) ? current.remove(title) : current.add(title);
          context.read<TextBookBloc>().add(UpdateCommentators(current));          
        },
      );
    }).toList();
  }

  ctx.ContextMenu _buildContextMenu(TextBookLoaded state) {
    // 1. קבלת מידע על גודל המסך
    final screenHeight = MediaQuery.of(context).size.height;

    // 2. זיהוי פרשנים שכבר שויכו לקבוצה
    final Set<String> alreadyListed = {
      ...state.rishonim,
      ...state.acharonim,
      ...state.modernCommentators,
    };

    // 3. יצירת רשימה של פרשנים שלא שויכו לאף קבוצה
    final List<String> ungrouped = state.availableCommentators
        .where((c) => !alreadyListed.contains(c))
        .toList();

    return ctx.ContextMenu(
      // 4. הגדרת הגובה המקסימלי ל-70% מגובה המסך
      maxHeight: screenHeight * 0.9,
      entries: [
        ctx.MenuItem(
            label: 'חיפוש', onSelected: () => widget.openLeftPaneTab(1)),
        ctx.MenuItem.submenu(
          label: 'פרשנות',
          enabled: state.availableCommentators.isNotEmpty, // <--- חדש
          items: [
            ctx.MenuItem(
              label: 'הצג את כל המפרשים',
              icon: state.activeCommentators.toSet().containsAll(
                      state.availableCommentators)
                  ? Icons.check
                  : null,              
              onSelected: () {
                final allActive = state.activeCommentators.toSet().containsAll(
                    state.availableCommentators);
                context.read<TextBookBloc>().add(
                      UpdateCommentators(
                        allActive ? <String>[] : List<String>.from(
                            state.availableCommentators),
                      ),
                    );
              },
            ),
            const ctx.MenuDivider(),
            // ראשונים
            ..._buildGroup(state.rishonim, state),

            // מוסיפים קו הפרדה רק אם יש גם ראשונים וגם אחרונים
            if (state.rishonim.isNotEmpty && state.acharonim.isNotEmpty)
              const ctx.MenuDivider(),

            // אחרונים
            ..._buildGroup(state.acharonim, state),

            // מוסיפים קו הפרדה רק אם יש גם אחרונים וגם בני זמננו
            if (state.acharonim.isNotEmpty &&
                state.modernCommentators.isNotEmpty)
              const ctx.MenuDivider(),

            // מחברי זמננו
            ..._buildGroup(state.modernCommentators, state),

            // הוסף קו הפרדה רק אם יש קבוצות אחרות וגם פרשנים לא-משויכים
            if ((state.rishonim.isNotEmpty ||
                    state.acharonim.isNotEmpty ||
                    state.modernCommentators.isNotEmpty) &&
                ungrouped.isNotEmpty)
              const ctx.MenuDivider(),

            // הוסף את רשימת הפרשנים הלא משויכים
            ..._buildGroup(ungrouped, state),
          ],
        ),
        ctx.MenuItem.submenu(
          label: 'קישורים',
          enabled: LinksViewer.getLinks(state).isNotEmpty, // <--- חדש
          items: LinksViewer.getLinks(state)
              .map(
                (link) => ctx.MenuItem(
                  label: link.heRef,
                  onSelected: () {
                    widget.openBookCallback(
                      TextBookTab(
                        book: TextBook(
                          title: utils.getTitleFromPath(link.path2),
                        ),
                        index: link.index2 - 1,
                        openLeftPane:
                            (Settings.getValue<bool>('key-pin-sidebar') ??
                                    false) ||
                                (Settings.getValue<bool>(
                                        'key-default-sidebar-open') ??
                                    false),
                      ),
                    );
                  },
                ),
              )
              .toList(),
        ),
        const ctx.MenuDivider(),
        ctx.MenuItem(
          label: 'בחר את כל הטקסט',
          onSelected: () =>
              _selectionKey.currentState?.selectableRegion.selectAll(),
        ),
      ],
    );
  }

  Widget buildKeyboardListener() {
    return BlocBuilder<TextBookBloc, TextBookState>(
      bloc: context.read<TextBookBloc>(),
      builder: (context, state) {
        if (state is! TextBookLoaded) {
          return const Center(child: CircularProgressIndicator());
        }
        return ProgressiveScroll(
          maxSpeed: 10000.0,
          curve: 10.0,
          accelerationFactor: 5,
          scrollController: state.scrollOffsetController,
          child: SelectionArea(
            key: _selectionKey,
            contextMenuBuilder: (_, __) => const SizedBox.shrink(),
            child: ctx.ContextMenuRegion(
              // <-- ה-Region היחיד, במיקום הנכון
              contextMenu: _buildContextMenu(state),
              child: buildOuterList(state),
            ),
          ),
        );
      },
    );
  }

  Widget buildOuterList(TextBookLoaded state) {
    return ScrollablePositionedList.builder(
      key: PageStorageKey(widget.tab),
      initialScrollIndex: state.visibleIndices.first,
      itemPositionsListener: state.positionsListener,
      itemScrollController: state.scrollController,
      scrollOffsetController: state.scrollOffsetController,
      itemCount: widget.data.length,
      itemBuilder: (context, index) {
        ExpansibleController controller = ExpansibleController();
        return buildExpansiomTile(controller, index, state);
      },
    );
  }

  ExpansionTile buildExpansiomTile(
    ExpansibleController controller,
    int index,
    TextBookLoaded state,
  ) {
    return ExpansionTile(
      shape: const Border(),
      //maintainState: true,
      controller: controller,
      key: PageStorageKey(widget.data[index]),
      iconColor: Colors.transparent,
      tilePadding: const EdgeInsets.all(0.0),
      collapsedIconColor: Colors.transparent,
      title: BlocBuilder<SettingsBloc, SettingsState>(
        builder: (context, settingsState) {
          String data = widget.data[index];
          if (!settingsState.showTeamim) {
            data = utils.removeTeamim(data);
          }

          if (settingsState.replaceHolyNames) {
            data = utils.replaceHolyNames(data);
          }
          return Html(
            //remove nikud if needed
            data: state.removeNikud
                ? utils.addBookLinks(utils.highLight(
                    utils.removeVolwels('$data\n'),
                    state.searchText,
                  ))
                : utils.addBookLinks(utils.highLight('$data\n', state.searchText)),
            style: {
              'body': Style(
                  fontSize: FontSize(widget.textSize),
                  fontFamily: settingsState.fontFamily,
                  textAlign: TextAlign.justify),
            },
            onLinkTap: (url, attributes, element) {
              _handleBookLink(url);
            },
          );
        },
      ),
      children: [
        widget.showSplitedView.value
            ? const SizedBox.shrink()
            : CommentaryListForCombinedView(
                index: index,
                fontSize: widget.textSize,
                openBookCallback: widget.openBookCallback,
                showSplitView: false,
              ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return buildKeyboardListener();
  }
}
