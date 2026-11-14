import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_hbb/common.dart';
import 'package:flutter_hbb/models/platform_model.dart';
import 'package:url_launcher/url_launcher.dart';

/// Update flow of this fork: everything comes from our own server instead of
/// github.com/rustdesk, so an official build can never replace the fork.
/// The manifest is written by publish_update.py on the server.
Future<void> showCustomUpdateCheck() async {
  final dm = gFFI.dialogManager;
  dm.showLoading(translate('Wait, please...'));
  String raw;
  try {
    raw = await bind.mainCustomUpdateCheck();
  } catch (e) {
    raw = 'error:$e';
  }
  dm.dismissAll();
  if (raw.startsWith('error:')) {
    showToast(raw.substring('error:'.length));
    return;
  }
  Map<String, dynamic> manifest;
  try {
    manifest = jsonDecode(raw) as Map<String, dynamic>;
  } catch (e) {
    showToast('bad manifest');
    return;
  }

  final remoteBuild = '${manifest['build'] ?? ''}';
  final notes = '${manifest['notes'] ?? ''}';
  final localBuild = await bind.mainGetOption(key: 'custom-build');
  final key = isWindows ? 'windows' : (isAndroid ? 'android' : '');
  final entry = key.isEmpty ? null : manifest[key];
  if (entry is! Map) {
    showToast(translate('Not available'));
    return;
  }
  final url = '${entry['url'] ?? ''}';
  final sha256 = '${entry['sha256'] ?? ''}';
  if (url.isEmpty || sha256.isEmpty) {
    showToast('bad manifest');
    return;
  }

  if (localBuild.isNotEmpty && localBuild == remoteBuild) {
    showToast(translate('Already up to date'));
    return;
  }

  dm.show((setState, close, context) {
    return CustomAlertDialog(
      title: Text(translate('Update')),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('服务器最新：$remoteBuild'),
          if (!isWindows)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(localBuild.isEmpty
                  ? '本机：未知（按下面按钮下载安装包）'
                  : '本机：$localBuild'),
            ),
          if (notes.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(notes),
            ),
          if (!isWindows)
            const Padding(
              padding: EdgeInsets.only(top: 8),
              child: Text(
                  '确认后在浏览器里下载安装包，下载完点通知栏的安装提示即可（安卓不允许静默安装）。'),
            ),
        ],
      ),
      actions: [
        dialogButton('Cancel', onPressed: close, isOutline: true),
        dialogButton('OK', onPressed: () async {
          close();
          if (!isWindows) {
            // Android can not install silently, it must hand the apk to the
            // system installer, so just open the download link.
            final ok =
                await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
            if (!ok) {
              // Nothing to open a browser with: at least keep the link reachable.
              showToast(url);
            } else {
              showToast('已打开浏览器，下载完成后点通知栏安装');
            }
            return;
          }
          gFFI.dialogManager.showLoading(translate('Downloading...'));
          final res =
              await bind.mainCustomUpdateApply(url: url, sha256: sha256, build: remoteBuild);
          gFFI.dialogManager.dismissAll();
          if (!res.startsWith('ok')) {
            showToast(res);
          }
        }),
      ],
    );
  });
}
