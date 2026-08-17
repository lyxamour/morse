import 'dart:convert';

import 'package:http/http.dart' as http;

/// app 内更新检查清单，由 release workflow 写入 CF Pages（国内直连可达），
/// 不走 GitHub API（私有仓库需鉴权 + 国内不稳）。
const updateManifestUrl = 'https://morse.embla.cf/update.json';

/// GitHub Releases 国内直连慢，Android 安装包走 gh-proxy 镜像，失败可在浏览器改直链。
const _ghMirror = 'https://gh-proxy.com/';

class UpdateInfo {
  const UpdateInfo({
    required this.version,
    required this.apk,
    required this.page,
  });

  final String version;
  final String apk;
  final String page;
}

UpdateInfo parseUpdate(String body) {
  final map = jsonDecode(body) as Map<String, dynamic>;
  return UpdateInfo(
    version: map['version'] as String,
    apk: map['apk'] as String,
    page: map['page'] as String,
  );
}

Future<UpdateInfo> fetchLatestUpdate() async {
  final res = await http
      .get(Uri.parse(updateManifestUrl))
      .timeout(const Duration(seconds: 10));
  return parseUpdate(res.body);
}

/// a 比 b 新返回 1，相同 0，旧返回 -1（点分段按数字比较，缺段按 0）。
int compareVersions(String a, String b) {
  final pa = a.split('.').map(int.parse).toList();
  final pb = b.split('.').map(int.parse).toList();
  for (var i = 0; i < pa.length || i < pb.length; i++) {
    final d = (i < pa.length ? pa[i] : 0).compareTo(i < pb.length ? pb[i] : 0);
    if (d != 0) return d;
  }
  return 0;
}

String mirrorUrl(String url) =>
    url.startsWith('https://github.com/') ? '$_ghMirror$url' : url;
