import 'package:flutter/material.dart';

class LanguagePickerSheet extends StatefulWidget {
  final String title;
  final List<String> languages;
  final String selectedLanguage;

  const LanguagePickerSheet({
    super.key,
    required this.title,
    required this.languages,
    required this.selectedLanguage,
  });

  @override
  State<LanguagePickerSheet> createState() => _LanguagePickerSheetState();
}

class _LanguagePickerSheetState extends State<LanguagePickerSheet> {
  final _searchCtrl = TextEditingController();

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final query = _searchCtrl.text.trim().toLowerCase();
    final filtered = widget.languages
        .where((language) => language.toLowerCase().contains(query))
        .toList();

    // Fixed size regardless of content/result count — this sheet used to
    // shrink to fit the filtered list (mainAxisSize.min + shrinkWrap),
    // which made it visibly resize as the user typed a search query.
    return SizedBox(
      width: double.infinity,
      height: 520,
      child: Container(
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        ),
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
            child: Column(
              children: [
                Container(
                  width: 42,
                  height: 4,
                  decoration: BoxDecoration(
                    color: theme.dividerColor,
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
                const SizedBox(height: 18),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    widget.title,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: _searchCtrl,
                  onChanged: (_) => setState(() {}),
                  decoration: InputDecoration(
                    hintText: 'Search language',
                    prefixIcon: const Icon(Icons.search_rounded),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                Expanded(
                  child: filtered.isEmpty
                      ? Center(
                          child: Text(
                            'No languages found',
                            style: TextStyle(
                              fontSize: 13,
                              color: theme.colorScheme.onSurface.withValues(
                                alpha: 0.55,
                              ),
                            ),
                          ),
                        )
                      : ListView.separated(
                          itemCount: filtered.length,
                          separatorBuilder: (_, _) =>
                              Divider(height: 1, color: theme.dividerColor),
                          itemBuilder: (context, index) {
                            final language = filtered[index];
                            return ListTile(
                              contentPadding: EdgeInsets.zero,
                              title: Text(language),
                              trailing: language == widget.selectedLanguage
                                  ? Icon(
                                      Icons.check_rounded,
                                      color: theme.colorScheme.primary,
                                    )
                                  : null,
                              onTap: () => Navigator.pop(context, language),
                            );
                          },
                        ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
