import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:harmonymusic/ui/screens/Library/library_controller.dart';

import 'additional_operation_dialog.dart';
import 'modified_text_field.dart';

enum OperationMode { arrange, delete, addToPlaylist, none }

enum SortType {
  name,
  date,
  duration,
  recentlyPlayed,
}

Set<SortType> buildSortTypeSet(
    [bool dateRequired = false,
    bool durationRequired = false,
    bool recentlyPlayedRequired = false]) {
  Set<SortType> requiredSortTypes = {};
  if (dateRequired) {
    requiredSortTypes.add(SortType.date);
  }
  if (durationRequired) {
    requiredSortTypes.add(SortType.duration);
  }
  if (recentlyPlayedRequired) {
    requiredSortTypes.add(SortType.recentlyPlayed);
  }
  return requiredSortTypes;
}

class SortWidget extends StatelessWidget {
  /// Additional operations - Delete Multiple songs, Rearrange offline playlist, Add Multiple songs to playlist
  const SortWidget({
    super.key,
    required this.tag,
    this.itemCountTitle = '',
    this.titleLeftPadding = 18,
    this.isAdditionalOperationRequired = true,
    this.requiredSortTypes = const <SortType>{SortType.name},
    this.isSearchFeatureRequired = false,
    this.isPlaylistRearrangeFeatureRequired = false,
    this.isSongDeletionFeatureRequired = false,
    required this.screenController,
    this.onSearchStart,
    this.onSearch,
    this.onSearchClose,
    this.itemIcon,
    this.startAdditionalOperation,
    this.selectAll,
    this.performAdditionalOperation,
    this.cancelAdditionalOperation,
    this.isImportFeatureRequired = false,
    required this.onSort,
  });

  /// unique identifier for each sort-widget
  final String tag;
  final String itemCountTitle;
  final IconData? itemIcon;
  final bool isAdditionalOperationRequired;
  final double titleLeftPadding;
  final Set<SortType> requiredSortTypes;
  final bool isSearchFeatureRequired;
  final bool isSongDeletionFeatureRequired;
  final bool isPlaylistRearrangeFeatureRequired;
  final dynamic screenController;
  final Function(SortWidgetController, OperationMode)? startAdditionalOperation;
  final Function(bool)? selectAll;
  final Function()? performAdditionalOperation;
  final Function()? cancelAdditionalOperation;
  final Function(String?)? onSearchStart;
  final Function(String, String?)? onSearch;
  final Function(String?)? onSearchClose;
  final Function(SortType, bool) onSort;
  final bool isImportFeatureRequired;

  Future<void> _showImportDialog(BuildContext context) async {
    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Theme.of(context).cardColor,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(15),
        ),
        title: Text(
          "importPlaylist".tr,
          style: Theme.of(context).textTheme.titleLarge,
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              "importPlaylistDesc".tr,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 12),
            Text(
              "importLargeFileNote".tr,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    fontStyle: FontStyle.italic,
                    color: Theme.of(context).colorScheme.secondary,
                  ),
            ),
            const SizedBox(height: 24),
            Center(
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Theme.of(context).colorScheme.secondary,
                  foregroundColor: Theme.of(context).colorScheme.onSecondary,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                icon: const Icon(Icons.file_open),
                label: Text("selectFile".tr),
                onPressed: () async {
                  await Get.find<LibraryPlaylistsController>()
                      .importPlaylistFromJson(context);
                  if(!context.mounted) return;
                  Navigator.pop(context);
                  Navigator.pop(context);
                },
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            style: TextButton.styleFrom(
              foregroundColor: Theme.of(context).colorScheme.secondary,
            ),
            onPressed: () => Navigator.pop(context),
            child: Text("close".tr),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final controller = Get.put(SortWidgetController(), tag: tag);
    final canSaveLibrarySearch = tag == "LibSongSort";
    return Padding(
      padding: const EdgeInsets.only(top: 10.0),
      child: SizedBox(
        height: 40,
        child: Obx(
          () => Stack(
            children: [
              if (controller.isSearchingEnabled.isFalse)
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    Padding(
                      padding: EdgeInsets.only(left: titleLeftPadding),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Text(itemCountTitle),
                          if (itemIcon != null)
                            Icon(
                              Icons.music_note,
                              size: 15,
                              color: Theme.of(context).colorScheme.secondary,
                            )
                        ],
                      ),
                    ),
                    Obx(
                      () => _customIconButton(
                        isSelected: controller.sortType.value == SortType.name,
                        icon: Icons.sort_by_alpha,
                        tooltip: "sortByName".tr,
                        onPressed: () {
                          controller.onSortByName(onSort);
                        },
                      ),
                    ),
                    requiredSortTypes.contains(SortType.date)
                        ? Obx(
                            () => _customIconButton(
                              isSelected:
                                  controller.sortType.value == SortType.date,
                              icon: Icons.calendar_month,
                              tooltip: "sortByDate".tr,
                              onPressed: () {
                                controller.onSortByDate(onSort);
                              },
                            ),
                          )
                        : const SizedBox.shrink(),
                    requiredSortTypes.contains(SortType.duration)
                        ? Obx(() => _customIconButton(
                              isSelected: controller.sortType.value ==
                                  SortType.duration,
                              tooltip: "sortByDuration".tr,
                              icon: Icons.timer,
                              onPressed: () {
                                controller.onSortByDuration(onSort);
                              },
                            ))
                        : const SizedBox.shrink(),
                    const Expanded(child: SizedBox()),
                    Obx(
                      () => _customIconButton(
                        icon: controller.isAscending.value
                            ? Icons.arrow_downward
                            : Icons.arrow_upward,
                        tooltip: "sortAscendNDescend".tr,
                        onPressed: () {
                          controller.onAscendNDescend(onSort);
                        },
                      ),
                    ),
                    if (isImportFeatureRequired)
                      _customIconButton(
                        icon: Icons.import_contacts,
                        tooltip: "importPlaylist".tr,
                        onPressed: () => _showImportDialog(context),
                      ),
                    if (isSearchFeatureRequired)
                      _customIconButton(
                        icon: Icons.search,
                        tooltip: "search".tr,
                        onPressed: () {
                          onSearchStart!(tag);
                          controller.toggleSearch();
                        },
                      ),
                    if (isAdditionalOperationRequired)
                      PopupMenuButton(
                        child: const Icon(
                          Icons.more_vert,
                          size: 20,
                        ),
                        // Callback that sets the selected popup menu item.
                        onSelected: (mode) async {
                          await showDialog(
                              context: context,
                              builder: (context) => AdditionalOperationDialog(
                                    operationMode: mode,
                                    screenController: screenController,
                                    controller: controller,
                                  ));

                          controller.setActiveMode(mode);
                          startAdditionalOperation!(controller, mode);
                        },
                        itemBuilder: (BuildContext context) => <PopupMenuEntry>[
                          if (isPlaylistRearrangeFeatureRequired)
                            PopupMenuItem(
                              value: OperationMode.arrange,
                              child: Text("reArrangePlaylist".tr),
                            ),
                          if (isSongDeletionFeatureRequired)
                            PopupMenuItem(
                              value: OperationMode.delete,
                              child: Text("removeMultiple".tr),
                            ),
                          PopupMenuItem(
                            value: OperationMode.addToPlaylist,
                            child: Text("addMultipleSongs".tr),
                          ),
                        ],
                      ),
                    const SizedBox(
                      width: 15,
                    )
                  ],
                ),
              if (controller.isSearchingEnabled.value)
                Container(
                  height: 40,
                  padding: const EdgeInsets.only(left: 5, right: 20),
                  // color:
                  //     Theme.of(context).scaffoldBackgroundColor.withAlpha(125),
                  child: ColoredBox(
                    color: Theme.of(context)
                        .scaffoldBackgroundColor
                        .withAlpha(125),
                    child: ModifiedTextField(
                      controller: controller.textEditingController,
                      textAlignVertical: TextAlignVertical.center,
                      autofocus: true,
                      onChanged: (value) {
                        onSearch!(value, tag);
                      },
                      cursorColor:
                          Theme.of(context).textTheme.titleSmall!.color,
                      decoration: InputDecoration(
                        isDense: true,
                        contentPadding: const EdgeInsets.all(8),
                        filled: true,
                        border: const OutlineInputBorder(),
                        hintText: tag.startsWith("Lib")
                            ? "searchHint".tr
                            : "search".tr,
                        suffixIconColor:
                            Theme.of(context).colorScheme.secondary,
                        suffixIcon: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (canSaveLibrarySearch)
                              IconButton(
                                splashRadius: 10,
                                iconSize: 20,
                                icon: const Icon(Icons.save),
                                onPressed: () async {
                                  final query = controller
                                      .textEditingController.text
                                      .trim();
                                  if (query.isEmpty) return;
                                  final isSearchControllerRegistered =
                                      Get.isRegistered<
                                          LibrarySearchesController>();
                                  if (!isSearchControllerRegistered) {
                                    Get.put(LibrarySearchesController());
                                  }
                                  await Get.find<LibrarySearchesController>()
                                      .saveSearch(query);
                                  Get.snackbar("searchSaved".tr, query);
                                },
                              ),
                            IconButton(
                              splashRadius: 10,
                              iconSize: 20,
                              icon: const Icon(Icons.cancel),
                              onPressed: () {
                                onSearchClose!(tag);
                                controller.toggleSearch();
                              },
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _customIconButton({
    required IconData icon,
    required String tooltip,
    bool? isSelected,
    Function()? onPressed,
  }) {
    return IconButton(
      icon: Icon(icon),
      padding: const EdgeInsets.all(0),
      color: isSelected == null || isSelected == true
          ? Theme.of(Get.context!).textTheme.bodySmall!.color
          : Theme.of(Get.context!).colorScheme.secondary,
      iconSize: 20,
      splashRadius: 20,
      visualDensity: const VisualDensity(horizontal: -3, vertical: -3),
      onPressed: onPressed,
      tooltip: tooltip,
    );
  }
}

class SortWidgetController extends GetxController {
  final Rx<SortType> sortType = SortType.name.obs;
  final isAscending = true.obs;
  final isSearchingEnabled = false.obs;
  final isRearrangingEnabled = false.obs;
  final isDeletionEnabled = false.obs;
  final isAddToPlaylistEnabled = false.obs;
  final isAllSelected = false.obs;
  TextEditingController textEditingController = TextEditingController();

  void setActiveMode(OperationMode mode) {
    isAddToPlaylistEnabled.value = OperationMode.addToPlaylist == mode;
    isDeletionEnabled.value = OperationMode.delete == mode;
    isRearrangingEnabled.value = OperationMode.arrange == mode;
  }

  void toggleSelectAll(bool val) {
    isAllSelected.value = val;
  }

  void onSortByName(Function onSort) {
    sortType.value = SortType.name;
    onSort(sortType.value, isAscending.value);
  }

  void onSortByDuration(Function onSort) {
    sortType.value = SortType.duration;
    onSort(sortType.value, isAscending.value);
  }

  void onSortByDate(Function onSort) {
    sortType.value = SortType.date;
    onSort(sortType.value, isAscending.value);
  }

  void onAscendNDescend(Function onSort) {
    isAscending.value = !isAscending.value;
    onSort(sortType.value, isAscending.value);
  }

  void toggleSearch() {
    isSearchingEnabled.value = !isSearchingEnabled.value;
  }

  @override
  void onClose() {
    textEditingController.dispose();
    super.onClose();
  }
}
