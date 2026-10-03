enum MobileNavItem {
  home,
  library,
  search,
  settings,
}

/// Visual order of bottom nav bar

const List<MobileNavItem> defaultMobileNavOrder = [
  MobileNavItem.home,
  MobileNavItem.library,
  MobileNavItem.search,
  MobileNavItem.settings,
];

extension MobileNavItemExtension on MobileNavItem {
  int get tabIndex {
    return switch (this) {
      MobileNavItem.home => 0,
      MobileNavItem.library => 1,
      MobileNavItem.search => 2,
      MobileNavItem.settings => 3,
    };
  }

  String get storageKey => name;
}

MobileNavItem? mobileNavItemFromStorageKey(String value){
  for (final item in MobileNavItem.values){
    if (item.name == value){
      return item;
    }
  }

  return null;
}


