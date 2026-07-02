import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('SearchScreen reads its controller from Riverpod', () {
    final source = File(
      'lib/ui/screens/Search/search_screen.dart',
    ).readAsStringSync();

    expect(source, contains('ref.watch(searchScreenControllerProvider)'));
    expect(source, isNot(contains('Get.find<SearchScreenController>()')));
    expect(source, isNot(contains('Get.put(SearchScreenController')));
    expect(source, isNot(contains('Get.toNamed')));
  });

  test('SearchScreenController receives service dependencies explicitly', () {
    final source = File(
      'lib/ui/screens/Search/search_screen_controller.dart',
    ).readAsStringSync();

    expect(source, contains('required SearchHistoryRepository'));
    expect(source, contains('required MusicServiceContract'));
    expect(source, contains('extends ChangeNotifier'));
    expect(source, isNot(contains("package:get/get.dart")));
    expect(source, isNot(contains('extends GetxController')));
    expect(source, isNot(contains('.obs')));
    expect(source, isNot(contains('Get.find<MusicServiceContract>')));
  });

  test('SearchResultScreen owns result controller locally', () {
    final source = File(
      'lib/ui/screens/Search/search_result_screen.dart',
    ).readAsStringSync();

    expect(source, contains('ConsumerStatefulWidget'));
    expect(source, contains('SearchResultScreenControllerRegistry.register'));
    expect(source, contains('musicServiceContractProvider'));
    expect(source, isNot(contains('Get.find<SearchResultScreenController>')));
    expect(source, isNot(contains('Get.put(SearchResultScreenController')));
  });

  test(
    'SearchResultScreenController receives service dependencies explicitly',
    () {
      final source = File(
        'lib/ui/screens/Search/search_result_screen_controller.dart',
      ).readAsStringSync();

      expect(source, contains('required MusicServiceContract'));
      expect(source, contains('required HomeScreenController'));
      expect(source, contains('required SettingsScreenController'));
      expect(source, contains('extends ChangeNotifier'));
      expect(source, isNot(contains('extends GetxController')));
      expect(source, isNot(contains('.obs')));
      expect(source, isNot(contains('Get.find<MusicServiceContract>')));
      expect(source, isNot(contains('Get.find<HomeScreenController>')));
      expect(source, isNot(contains('Get.find<SettingsScreenController>')));
    },
  );

  test('GetX bridge has been removed', () {
    expect(File('lib/app/providers/getx_bridge.dart').existsSync(), isFalse);
  });
}
