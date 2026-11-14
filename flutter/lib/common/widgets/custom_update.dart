import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_hbb/common.dart';
import 'package:flutter_hbb/models/platform_model.dart';
import 'package:path_provider/path_provider.dart';
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
                  '确认后在应用内下载并校验安装包，随后直接弹出安装界面（首次需允许「安装未知应用」）。'),
            ),
        ],
      ),
      actions: [
        dialogButton('Cancel', onPressed: close, isOutline: true),
        dialogButton('OK', onPressed: () async {
          close();
          if (isAndroid) {
            // Fetch the apk inside the app (rust verifies the checksum), then
            // hand the file to the system installer. No browser round trip.
            gFFI.dialogManager.showLoading(translate('Downloading...'));
            String res;
            try {
              final dir = (await getTemporaryDirectory()).path;
              res = await bind.mainCustomUpdateDownload(
                  url: url,
                  sha256: sha256,
                  build: remoteBuild,
                  destDir: dir);
            } catch (e) {
              res = 'error:$e';
            }
            gFFI.dialogManager.dismissAll();
            if (res.startsWith('ok:')) {
              final launched =
                  await gFFI.invokeMethod('install_apk', res.substring(3));
              if (!launched) {
                showToast('请在系统页面允许「安装未知应用」，再点一次更新');
              }
              return;
            }
            // Download failed: keep the old browser path as a fallback rather
            // than leaving the user without a way to update.
            showToast(res.replaceFirst('error:', ''));
            await launchUrl(Uri.parse(url),
                mode: LaunchMode.externalApplication);
            return;
          }
          if (!isWindows) {
            // iOS/linux/mac: no installer to hand a file to, open the link.
            final ok =
                await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
            if (!ok) {
              showToast(url);
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
