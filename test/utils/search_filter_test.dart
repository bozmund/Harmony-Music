import 'package:flutter_test/flutter_test.dart';
import 'package:harmonymusic/utils/search_filter.dart';

void main() {
  group('SearchFilter matches tests', () {
    test('Empty query matches everything', () {
      expect(SearchFilter.matches({'title': 'Linkin Park', 'artist': 'Linkin Park'}, ''), isTrue);
      expect(SearchFilter.matches({}, ''), isTrue);
    });

    test('Single term simple match across all fields', () {
      final fields = {'title': 'Numb', 'artist': 'Linkin Park'};
      expect(SearchFilter.matches(fields, 'Numb'), isTrue);
      expect(SearchFilter.matches(fields, 'Linkin'), isTrue);
      expect(SearchFilter.matches(fields, 'linkin'), isTrue);
      expect(SearchFilter.matches(fields, 'Jay-Z'), isFalse);
    });

    test('Multiple terms (Union/OR) match', () {
      final fields = {'title': 'Numb', 'artist': 'Linkin Park'};
      expect(SearchFilter.matches(fields, 'Numb, Jay-Z'), isTrue);
      expect(SearchFilter.matches(fields, 'Linkin Park, Jay-Z'), isTrue);
      expect(SearchFilter.matches(fields, 'Metallica, Jay-Z'), isFalse);
    });

    test('Exclusion (NOT) matches', () {
      final fields = {'title': 'Numb (Live)', 'artist': 'Linkin Park'};
      expect(SearchFilter.matches(fields, '!live'), isFalse);
      expect(SearchFilter.matches(fields, '!Numb'), isFalse);
      expect(SearchFilter.matches(fields, '!Jay-Z'), isTrue);
      expect(SearchFilter.matches(fields, 'Linkin Park, !live'), isFalse);
      expect(SearchFilter.matches({'title': 'In the End', 'artist': 'Linkin Park'}, 'Linkin Park, !live'), isTrue);
    });

    test('Scoped filters (a:, artist:) match', () {
      final fields = {'title': 'Linkin Park', 'artist': 'Hybrid Theory'}; // Swapped for testing
      expect(SearchFilter.matches(fields, 'a:Hybrid Theory'), isTrue);
      expect(SearchFilter.matches(fields, 'artist:Hybrid Theory'), isTrue);
      expect(SearchFilter.matches(fields, 'a:Linkin Park'), isFalse); // Linkin Park is title, not artist
    });

    test('Scoped filters (t:, title:) match', () {
      final fields = {'title': 'Hybrid Theory', 'artist': 'Linkin Park'};
      expect(SearchFilter.matches(fields, 't:Hybrid Theory'), isTrue);
      expect(SearchFilter.matches(fields, 'title:Hybrid Theory'), isTrue);
      expect(SearchFilter.matches(fields, 't:Linkin Park'), isFalse); // Linkin Park is artist, not title
    });

    test('Combined scoped and exclusion filters', () {
      final fields = {'title': 'Numb (Live)', 'artist': 'Linkin Park'};
      expect(SearchFilter.matches(fields, 'a:Linkin Park, !t:Live'), isFalse);
      expect(SearchFilter.matches({'title': 'Numb', 'artist': 'Linkin Park'}, 'a:Linkin Park, !t:Live'), isTrue);
      expect(SearchFilter.matches(fields, 't:Numb, !a:Metallica'), isTrue);
    });

    test('Multiple exclusions match', () {
      final fields = {'title': 'Song A (Live)', 'artist': 'Artist B'};
      expect(SearchFilter.matches(fields, '!live, !Artist B'), isFalse);
      expect(SearchFilter.matches({'title': 'Song A', 'artist': 'Artist C'}, '!live, !Artist B'), isTrue);
    });

    test('Complex combined filters', () {
      final fields = {'title': 'Numb', 'artist': 'Linkin Park'};
      const query = 'a:Linkin Park, a:Jay-Z, !t:Live, !t:Remix';
      expect(SearchFilter.matches(fields, query), isTrue);
      expect(SearchFilter.matches({'title': 'Empire State', 'artist': 'Jay-Z'}, query), isTrue);
      expect(SearchFilter.matches({'title': 'Numb (Live)', 'artist': 'Linkin Park'}, query), isFalse);
      expect(SearchFilter.matches({'title': 'Numb (Remix)', 'artist': 'Jay-Z'}, query), isFalse);
      expect(SearchFilter.matches({'title': 'One', 'artist': 'Metallica'}, query), isFalse);
    });

    test('Whitespace normalization', () {
      final fields = {'title': 'Numb (Live)', 'artist': 'Linkin Park'};
      expect(SearchFilter.matches(fields, ' a:Linkin , !t:live '), isFalse);
      expect(SearchFilter.matches({'title': 'Numb', 'artist': 'Linkin Park'}, ' a:Linkin , !t:live '), isTrue);
    });
  });
}
