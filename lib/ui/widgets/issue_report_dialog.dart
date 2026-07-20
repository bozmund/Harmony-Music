import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:harmonymusic/services/app_platform_service.dart';

import 'common_dialog_widget.dart';

const _issueReportEndpoint = String.fromEnvironment('ISSUE_REPORT_ENDPOINT');
const _manualIssueUrl = 'https://github.com/bozmund/Harmony-Music/issues/new';

Future<Map<String, dynamic>> _buildIssueReportPayload({
  required Locale locale,
  required String title,
  required String description,
  String stepsToReproduce = '',
  String expectedResult = '',
  String actualResult = '',
  String contact = '',
  String debugDetails = '',
  Future<Map<String, dynamic>?> Function()? extraDiagnosticsBuilder,
}) async {
  final info = await AppPlatformService.getAppInfo();
  final diagnostics = <String, dynamic>{
    'appName': info.appName,
    'packageName': info.packageName,
    'version': info.version,
    'buildNumber': info.buildNumber,
    'platform': Platform.operatingSystem,
    'platformVersion': Platform.operatingSystemVersion,
    'locale': locale.toString(),
    'timestamp': DateTime.now().toUtc().toIso8601String(),
  };
  final extraDiagnostics = await extraDiagnosticsBuilder?.call();
  if (extraDiagnostics != null && extraDiagnostics.isNotEmpty) {
    diagnostics.addAll(extraDiagnostics);
  }

  return {
    'title': title.trim(),
    'description': description.trim(),
    'stepsToReproduce': stepsToReproduce.trim(),
    'expectedResult': expectedResult.trim(),
    'actualResult': actualResult.trim(),
    'contact': contact.trim(),
    'debugDetails': debugDetails.trim(),
    'diagnostics': diagnostics,
  };
}

/// Validates, builds the diagnostics payload and POSTs it to
/// [_issueReportEndpoint]. Returns an error message on failure, or `null`
/// on success. Shared by the full [IssueReportDialogController] form and any
/// quick-report flow that submits without showing editable fields.
Future<String?> submitIssueReportPayload({
  required Locale locale,
  required String title,
  required String description,
  String stepsToReproduce = '',
  String expectedResult = '',
  String actualResult = '',
  String contact = '',
  String debugDetails = '',
  Future<Map<String, dynamic>?> Function()? extraDiagnosticsBuilder,
}) async {
  if (title.trim().isEmpty || description.trim().isEmpty) {
    return "Title and description are required.";
  }

  if (_issueReportEndpoint.isEmpty) {
    return "Issue reporting endpoint is not configured.";
  }

  try {
    final payload = await _buildIssueReportPayload(
      locale: locale,
      title: title,
      description: description,
      stepsToReproduce: stepsToReproduce,
      expectedResult: expectedResult,
      actualResult: actualResult,
      contact: contact,
      debugDetails: debugDetails,
      extraDiagnosticsBuilder: extraDiagnosticsBuilder,
    );
    await Dio().post(
      _issueReportEndpoint,
      data: payload,
      options: Options(
        headers: {'content-type': 'application/json'},
        validateStatus: (status) =>
            status != null && status >= 200 && status < 300,
      ),
    );
    return null;
  } catch (e) {
    return "Could not submit issue. You can open GitHub manually.";
  }
}

class IssueReportDialogController extends ChangeNotifier {
  IssueReportDialogController({this.extraDiagnosticsBuilder});

  final Future<Map<String, dynamic>?> Function()? extraDiagnosticsBuilder;

  final titleController = TextEditingController();
  final descriptionController = TextEditingController();
  final stepsController = TextEditingController();
  final expectedController = TextEditingController();
  final actualController = TextEditingController();
  final contactController = TextEditingController();
  final debugDetailsController = TextEditingController();

  bool isSubmitting = false;
  String? error;
  bool submitted = false;

  Future<void> submit(Locale locale) async {
    if (isSubmitting) return;

    error = null;
    submitted = false;
    isSubmitting = true;
    notifyListeners();

    final result = await submitIssueReportPayload(
      locale: locale,
      title: titleController.text,
      description: descriptionController.text,
      stepsToReproduce: stepsController.text,
      expectedResult: expectedController.text,
      actualResult: actualController.text,
      contact: contactController.text,
      debugDetails: debugDetailsController.text,
      extraDiagnosticsBuilder: extraDiagnosticsBuilder,
    );

    error = result;
    submitted = result == null;
    isSubmitting = false;
    notifyListeners();
  }

  Future<void> openManualIssue(Locale locale) async {
    final payload = await _buildIssueReportPayload(
      locale: locale,
      title: titleController.text,
      description: descriptionController.text,
      stepsToReproduce: stepsController.text,
      expectedResult: expectedController.text,
      actualResult: actualController.text,
      contact: contactController.text,
      debugDetails: debugDetailsController.text,
      extraDiagnosticsBuilder: extraDiagnosticsBuilder,
    );
    final uri = Uri.parse(_manualIssueUrl).replace(
      queryParameters: {
        'labels': 'bug',
        'title': titleController.text.trim(),
        'body': _markdownBody(payload),
      },
    );
    await AppPlatformService.openUrl(uri.toString());
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
  void dispose() {
    titleController.dispose();
    descriptionController.dispose();
    stepsController.dispose();
    expectedController.dispose();
    actualController.dispose();
    contactController.dispose();
    debugDetailsController.dispose();
    super.dispose();
  }
}

class IssueReportDialog extends StatefulWidget {
  const IssueReportDialog({super.key, this.extraDiagnosticsBuilder});

  final Future<Map<String, dynamic>?> Function()? extraDiagnosticsBuilder;

  @override
  State<IssueReportDialog> createState() => _IssueReportDialogState();
}

class _IssueReportDialogState extends State<IssueReportDialog> {
  late final IssueReportDialogController controller;

  @override
  void initState() {
    super.initState();
    controller = IssueReportDialogController(
      extraDiagnosticsBuilder: widget.extraDiagnosticsBuilder,
    );
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return CommonDialog(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.85,
        ),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: AnimatedBuilder(
            animation: controller,
            builder: (context, _) => SingleChildScrollView(
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
                  if (controller.isSubmitting) ...[
                    const SizedBox(height: 8),
                    const LinearProgressIndicator(),
                  ],
                  if (controller.error != null) ...[
                    const SizedBox(height: 10),
                    Text(
                      controller.error!,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ],
                  if (controller.submitted) ...[
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
                        onPressed: controller.isSubmitting
                            ? null
                            : () => Navigator.of(context).pop(),
                        child: Text(controller.submitted ? "Close" : "Cancel"),
                      ),
                      const SizedBox(width: 8),
                      TextButton(
                        style: _issueDialogButtonStyle(context),
                        onPressed: controller.isSubmitting
                            ? null
                            : () => controller.openManualIssue(
                                Localizations.localeOf(context),
                              ),
                        child: const Text("Open GitHub"),
                      ),
                      const SizedBox(width: 8),
                      TextButton(
                        style: _issueDialogButtonStyle(context),
                        onPressed: controller.isSubmitting
                            ? null
                            : () => controller.submit(
                                Localizations.localeOf(context),
                              ),
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
    disabledForegroundColor: Theme.of(
      context,
    ).textTheme.bodyMedium!.color?.withValues(alpha: 0.45),
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
              color: Theme.of(
                context,
              ).textTheme.titleMedium!.color?.withValues(alpha: 0.78),
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
              style: Theme.of(
                context,
              ).textTheme.titleMedium!.copyWith(fontSize: 14),
              decoration: InputDecoration(
                isDense: true,
                filled: true,
                fillColor: Theme.of(
                  context,
                ).colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 12,
                ),
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
