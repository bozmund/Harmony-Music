class SearchFilter {
  /// Matches [fields] against [query] using "Smart Filter" syntax with scopes.
  /// Union (OR): Separate multiple terms with commas (e.g., 'Artist A, Artist B').
  /// Exclusion (NOT): Prefix terms with '!' to exclude them (e.g., '!live').
  /// Scopes:
  /// - 'a:' or 'artist:': Matches only against the 'artist' field.
  /// - 't:' or 'title:': Matches only against the 'title' field.
  /// - No prefix: Matches against all provided fields.
  static bool matches(Map<String, String?> fields, String query) {
    if (query.isEmpty) return true;

    // Split by comma and clean up terms
    final terms = query
        .split(',')
        .map((e) => e.trim().toLowerCase())
        .where((e) => e.isNotEmpty)
        .toList();

    if (terms.isEmpty) return true;

    final exclusions = terms.where((t) => t.startsWith('!')).toList();
    final inclusions = terms.where((t) => !t.startsWith('!')).toList();

    // If any exclusion term matches, immediately return false
    for (var term in exclusions) {
      if (_termMatches(fields, term.substring(1))) {
        return false;
      }
    }

    // If there are no inclusion terms, but we passed the exclusion check, return true
    if (inclusions.isEmpty) return true;

    // If any inclusion term matches, return true (Union/OR logic)
    return inclusions.any((term) => _termMatches(fields, term));
  }

  static bool _termMatches(Map<String, String?> fields, String term) {
    if (term.isEmpty) return false;

    String? targetField;
    String actualTerm = term;

    if (term.startsWith('a:')) {
      targetField = 'artist';
      actualTerm = term.substring(2);
    } else if (term.startsWith('artist:')) {
      targetField = 'artist';
      actualTerm = term.substring(7);
    } else if (term.startsWith('t:')) {
      targetField = 'title';
      actualTerm = term.substring(2);
    } else if (term.startsWith('title:')) {
      targetField = 'title';
      actualTerm = term.substring(6);
    }

    if (actualTerm.isEmpty) return false;

    if (targetField != null) {
      final value = fields[targetField]?.toLowerCase() ?? '';
      return value.contains(actualTerm);
    }

    // Default: check all fields
    return fields.values.any((value) => (value?.toLowerCase() ?? '').contains(actualTerm));
  }
}
