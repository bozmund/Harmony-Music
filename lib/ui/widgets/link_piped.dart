import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:harmonymusic/utils/get_localization.dart';

import '../../app/providers/controller_providers.dart';
import '../../app/providers/service_providers.dart';
import '../../utils/helper.dart';
import '/services/piped_service.dart';
import '../screens/Settings/settings_screen_controller.dart';
import '../screens/Library/library_controller.dart';
import 'common_dialog_widget.dart';
import 'modified_text_field.dart';
import 'snackbar.dart';

class LinkPiped extends ConsumerStatefulWidget {
  const LinkPiped({super.key});

  @override
  ConsumerState<LinkPiped> createState() => _LinkPipedState();
}

class _LinkPipedState extends ConsumerState<LinkPiped> {
  late final PipedLinkedController pipedLinkedController;

  @override
  void initState() {
    super.initState();
    pipedLinkedController = PipedLinkedController(
      pipedServices: ref.read(pipedServicesProvider),
      settingsScreenController: ref.read(settingsScreenControllerProvider),
      libraryPlaylistsController: LibraryPlaylistsControllerRegistry.current!,
    );
  }

  @override
  void dispose() {
    pipedLinkedController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return CommonDialog(
      child: AnimatedBuilder(
        animation: pipedLinkedController,
        builder: (context, _) => Container(
          height: pipedLinkedController.selectedInst == "custom" ? 400 : 365,
          padding: const EdgeInsets.symmetric(vertical: 30, horizontal: 30),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text("Piped".tr, style: Theme.of(context).textTheme.titleLarge),
              Padding(
                padding: const EdgeInsets.only(top: 15.0, bottom: 10),
                child: DropdownButton(
                  underline: const SizedBox.shrink(),
                  value: pipedLinkedController.selectedInst,
                  items: pipedLinkedController.pipedInstList
                      .map(
                        (element) => DropdownMenuItem(
                          value: element.apiUrl,
                          child: Text(element.name),
                        ),
                      )
                      .toList(),
                  onChanged: (val) {
                    pipedLinkedController.selectInstance(val as String);
                  },
                ),
              ),
              pipedLinkedController.selectedInst == "custom"
                  ? ModifiedTextField(
                      controller:
                          pipedLinkedController.instApiUrlInputController,
                      cursorColor: Theme.of(
                        context,
                      ).textTheme.titleSmall!.color,
                      decoration: InputDecoration(hintText: "hintApiUrl".tr),
                    )
                  : const SizedBox.shrink(),
              ModifiedTextField(
                controller: pipedLinkedController.usernameInputController,
                cursorColor: Theme.of(context).textTheme.titleSmall!.color,
                decoration: InputDecoration(hintText: "username".tr),
              ),
              const SizedBox(height: 15),
              ModifiedTextField(
                controller: pipedLinkedController.passwordInputController,
                cursorColor: Theme.of(context).textTheme.titleSmall!.color,
                decoration: InputDecoration(
                  hintText: "password".tr,
                  suffixIcon: IconButton(
                    color: Theme.of(context).textTheme.titleSmall!.color,
                    icon: pipedLinkedController.passwordVisible
                        ? const Icon(Icons.visibility_off)
                        : const Icon(Icons.visibility),
                    onPressed: pipedLinkedController.togglePasswordVisible,
                  ),
                ),
                obscureText: !pipedLinkedController.passwordVisible,
              ),
              Expanded(
                child: Center(
                  child: Text(
                    pipedLinkedController.errorText,
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
              Container(
                decoration: BoxDecoration(
                  color: Theme.of(context).textTheme.titleLarge!.color,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: InkWell(
                  onTap: () => pipedLinkedController.link(context),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20.0,
                      vertical: 10,
                    ),
                    child: Text(
                      "link".tr,
                      style: TextStyle(color: Theme.of(context).canvasColor),
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
}

class PipedLinkedController extends ChangeNotifier {
  PipedLinkedController({
    required PipedServices pipedServices,
    required SettingsScreenController settingsScreenController,
    required LibraryPlaylistsController libraryPlaylistsController,
  }) : _pipedServices = pipedServices,
       _settingsScreenController = settingsScreenController,
       _libraryPlaylistsController = libraryPlaylistsController {
    unawaited(getAllInstList());
  }

  final instApiUrlInputController = TextEditingController();
  final usernameInputController = TextEditingController();
  final passwordInputController = TextEditingController();
  final pipedInstList = <PipedInstance>[
    PipedInstance(name: "selectAuthIns".tr, apiUrl: ""),
  ];
  final PipedServices _pipedServices;
  final SettingsScreenController _settingsScreenController;
  final LibraryPlaylistsController _libraryPlaylistsController;
  var selectedInst = "";
  var passwordVisible = false;
  var errorText = "";

  void selectInstance(String value) {
    errorText = "";
    selectedInst = value;
    notifyListeners();
  }

  void togglePasswordVisible() {
    passwordVisible = !passwordVisible;
    notifyListeners();
  }

  Future<void> getAllInstList() async {
    await _pipedServices.getAllInstanceList().then((res) {
      if (res.code == 1) {
        pipedInstList.addAll(
          List<PipedInstance>.from(res.response) +
              [PipedInstance(name: "customIns".tr, apiUrl: "custom")],
        );
      } else {
        errorText =
            "${res.errorMessage ?? "errorOccurredAlert".tr}! ${"customInsSelectMsg".tr}";
        pipedInstList.add(
          PipedInstance(name: "customIns".tr, apiUrl: "custom"),
        );
      }
      notifyListeners();
    });
  }

  Future<void> link(BuildContext context) async {
    errorText = "";
    notifyListeners();
    final userName = usernameInputController.text;
    final password = passwordInputController.text;
    if (selectedInst.isEmpty) {
      errorText = "selectAuthInsMsg".tr;
      notifyListeners();
      return;
    }
    if (userName.isEmpty ||
        password.isEmpty ||
        // ignore: invalid_use_of_protected_member
        (instApiUrlInputController.hasListeners &&
            instApiUrlInputController.text.isEmpty)) {
      errorText = "allFieldsReqMsg".tr;
      notifyListeners();
      return;
    }
    await _pipedServices
        .login(
          selectedInst == 'custom'
              ? instApiUrlInputController.text
              : selectedInst,
          userName,
          password,
        )
        .then((res) async {
          if (res.code == 1) {
            printINFO("Login Successful");
            _settingsScreenController.isLinkedWithPiped.value = true;
            if (context.mounted) {
              Navigator.of(context).pop();
              ScaffoldMessenger.of(context).showSnackBar(
                snackbar(context, "linkAlert".tr, size: SanckBarSize.MEDIUM),
              );
            }
            await _libraryPlaylistsController.syncPipedPlaylist();
          } else {
            errorText = res.errorMessage ?? "errorOccurredAlert".tr;
            notifyListeners();
          }
        });
  }

  @override
  void dispose() {
    instApiUrlInputController.dispose();
    usernameInputController.dispose();
    passwordInputController.dispose();
    super.dispose();
  }
}
