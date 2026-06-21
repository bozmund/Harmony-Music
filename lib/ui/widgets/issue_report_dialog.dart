import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import 'common_dialog_widget.dart';

const _issueReportEndpoint = String.fromEnvironment('ISSUE_REPORT_ENDPOINT');
const _manualIssueUrl = 'https://github.com/bozmund/Harmony-Music/issues/new';

class IssueReportDialogController extends GetxController {
  final titleController = TextEditingController();
  final descriptionController = TextEditingController();
  final stepsController = TextEditingController();
  final expectedController = TextEditingController();
  final actualController = TextEditingController();
  final contactController = TextEditingController();
  final debugDetailsController = TextEditingController();

  final isSubmitting = false.obs;
  final error = RxnString();
  final submitted = false.obs;

  Future<void> submit() async {
    if (isSubmitting.value) return;

    error.value = null;
    submitted.value = false;

    if (titleController.text.trim().isEmpty ||
        descriptionController.text.trim().isEmpty) {
      error.value = "Title and description are required.";
      return;
    }

    if (_issueReportEndpoint.isEmpty) {
      error.value = "Issue reporting endpoint is not configured.";
      return;
    }

    isSubmitting.value = true;
    try {
      final payload = await _buildPayload();
      await Dio().post(
        _issueReportEndpoint,
        data: payload,
        options: Options(
          headers: {'content-type': 'application/json'},
          validateStatus: (status) =>
              status != null && status >= 200 && status < 300,
        ),
      );
      submitted.value = true;
    } catch (e) {
      error.value = "Could not submit issue. You can open GitHub manually.";
    } finally {
      isSubmitting.value = false;
    }
  }

  Future<void> openManualIssue() async {
    final payload = await _buildPayload();
    final uri = Uri.parse(_manualIssueUrl).replace(queryParameters: {
      'labels': 'bug',
      'title': titleController.text.trim(),
      'body': _markdownBody(payload),
    });
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  Future<Map<String, dynamic>> _buildPayload() async {
    final info = await PackageInfo.fromPlatform();
    final diagnostics = {
      'appName': info.appName,
      'packageName': info.packageName,
      'version': info.version,
      'buildNumber': info.buildNumber,
      'platform': Platform.operatingSystem,
      'platformVersion': Platform.operatingSystemVersion,
      'locale': Get.locale?.toString() ?? Platform.localeName,
      'timestamp': DateTime.now().toUtc().toIso8601String(),
    };

    return {
      'title': titleController.text.trim(),
      'description': descriptionController.text.trim(),
      'stepsToReproduce': stepsController.text.trim(),
      'expectedResult': expectedController.text.trim(),
      'actualResult': actualController.text.trim(),
      'contact': contactController.text.trim(),
      'debugDetails': debugDetailsController.text.trim(),
      'diagnostics': diagnostics,
    };
  }

  String _markdownBody(Map<String, dynamic> payload) {
    final diagnostics = payload['diagnostics'] as Map<String, dynamic>;
    return '''
**Description**
${payload['description']}

**Steps to reproduce**
${payload['stepsToReproduce']}

**Expected result**
${payload['expectedResult']}

**Actual result**
${payload['actualResult']}

**Contact**
${payload['contact']}

**Debug details**
${payload['debugDetails']}

**Diagnostics**
```json
${const JsonEncoder.withIndent('  ').convert(diagnostics)}
```
''';
  }

  @override
  void onClose() {
    titleController.dispose();
    descriptionController.dispose();
    stepsController.dispose();
    expectedController.dispose();
    actualController.dispose();
    contactController.dispose();
    debugDetailsController.dispose();
    super.onClose();
  }
}

class IssueReportDialog extends StatelessWidget {
  const IssueReportDialog({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = Get.isRegistered<IssueReportDialogController>()
        ? Get.find<IssueReportDialogController>()
        : Get.put(IssueReportDialogController());

    return CommonDialog(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.85,
        ),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Obx(
            () => SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    "Report an issue",
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 14),
                  _IssueTextField(
                    controller: controller.titleController,
                    label: "Title",
                    minHeight: 52,
                  ),
                  _IssueTextField(
                    controller: controller.descriptionController,
                    label: "Description",
                    maxLines: 3,
                    minHeight: 92,
                  ),
                  _IssueTextField(
                    controller: controller.stepsController,
                    label: "Steps to reproduce",
                    maxLines: 4,
                    minHeight: 112,
                  ),
                  _IssueTextField(
                    controller: controller.expectedController,
                    label: "Expected result",
                    maxLines: 2,
                    minHeight: 72,
                  ),
                  _IssueTextField(
                    controller: controller.actualController,
                    label: "Actual result",
                    maxLines: 2,
                    minHeight: 72,
                  ),
                  _IssueTextField(
                    controller: controller.contactController,
                    label: "Contact (optional)",
                    minHeight: 52,
                  ),
                  _IssueTextField(
                    controller: controller.debugDetailsController,
                    label: "Debug details (optional)",
                    maxLines: 4,
                    minHeight: 112,
                  ),
                  if (controller.isSubmitting.value) ...[
                    const SizedBox(height: 8),
                    const LinearProgressIndicator(),
                  ],
                  if (controller.error.value != null) ...[
                    const SizedBox(height: 10),
                    Text(
                      controller.error.value!,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: Theme.of(context).colorScheme.error,
                          ),
                    ),
                  ],
                  if (controller.submitted.value) ...[
                    const SizedBox(height: 10),
                    Text(
                      "Issue submitted. Thank you!",
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ],
                  const SizedBox(height: 16),
                  Wrap(
                    alignment: WrapAlignment.end,
                    runSpacing: 8,
                    children: [
                      TextButton(
                        style: _issueDialogButtonStyle(context),
                        onPressed: controller.isSubmitting.value
                            ? null
                            : () => Get.back(),
                        child: Text(
                            controller.submitted.value ? "Close" : "Cancel"),
                      ),
                      const SizedBox(width: 8),
                      TextButton(
                        style: _issueDialogButtonStyle(context),
                        onPressed: controller.isSubmitting.value
                            ? null
                            : controller.openManualIssue,
                        child: const Text("Open GitHub"),
                      ),
                      const SizedBox(width: 8),
                      TextButton(
                        style: _issueDialogButtonStyle(context),
                        onPressed: controller.isSubmitting.value
                            ? null
                            : controller.submit,
                        child: const Text("Submit"),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

ButtonStyle _issueDialogButtonStyle(BuildContext context) {
  return TextButton.styleFrom(
    foregroundColor: Theme.of(context).textTheme.titleMedium!.color,
    disabledForegroundColor:
        Theme.of(context).textTheme.bodyMedium!.color?.withValues(alpha: 0.45),
    textStyle: Theme.of(context).textTheme.titleMedium!.copyWith(fontSize: 14),
  );
}

class _IssueTextField extends StatelessWidget {
  const _IssueTextField({
    required this.controller,
    required this.label,
    this.maxLines = 1,
    required this.minHeight,
  });

  final TextEditingController controller;
  final String label;
  final int maxLines;
  final double minHeight;

  @override
  Widget build(BuildContext context) {
    final border = OutlineInputBorder(
      borderRadius: BorderRadius.circular(8),
      borderSide: BorderSide(
        color: Theme.of(context).dividerColor.withValues(alpha: 0.7),
      ),
    );

    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: Theme.of(context).textTheme.titleMedium!.copyWith(
                  fontSize: 13,
                  color: Theme.of(context)
                      .textTheme
                      .titleMedium!
                      .color
                      ?.withValues(alpha: 0.78),
                ),
          ),
          const SizedBox(height: 6),
          ConstrainedBox(
            constraints: BoxConstraints(minHeight: minHeight),
            child: TextField(
              controller: controller,
              minLines: maxLines,
              maxLines: maxLines,
              textAlignVertical: TextAlignVertical.top,
              cursorColor: Theme.of(context).textTheme.titleMedium!.color,
              style: Theme.of(context).textTheme.titleMedium!.copyWith(
                    fontSize: 14,
                  ),
              decoration: InputDecoration(
                isDense: true,
                filled: true,
                fillColor: Theme.of(context)
                    .colorScheme
                    .surfaceContainerHighest
                    .withValues(alpha: 0.35),
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                border: border,
                enabledBorder: border,
                focusedBorder: border.copyWith(
                  borderSide: BorderSide(
                    color: Theme.of(context).colorScheme.secondary,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
