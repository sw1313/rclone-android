import 'dart:convert';

class RcloneMountFlags {
  const RcloneMountFlags({
    this.vfsCacheMode = 'writes',
    this.vfsCacheMaxSize = '1G',
    this.vfsCacheMaxAge = '24h',
    this.dirCacheTime = '5m',
    this.bufferSize = '16M',
    this.vfsReadChunkSize = '128M',
    this.transfers = 4,
    this.checkers = 8,
    this.bwlimit = '',
    this.uid = '',
    this.gid = '9997',
    this.umask = '0',
    this.dirPerms = '0771',
    this.filePerms = '0660',
    this.allowOther = true,
    this.logLevel = 'INFO',
    this.extraArgs = '',
  });

  final String vfsCacheMode;
  final String vfsCacheMaxSize;
  final String vfsCacheMaxAge;
  final String dirCacheTime;
  final String bufferSize;
  final String vfsReadChunkSize;
  final int transfers;
  final int checkers;
  final String bwlimit;
  final String uid;
  final String gid;
  final String umask;
  final String dirPerms;
  final String filePerms;
  final bool allowOther;
  final String logLevel;
  final String extraArgs;

  RcloneMountFlags copyWith({
    String? vfsCacheMode,
    String? vfsCacheMaxSize,
    String? vfsCacheMaxAge,
    String? dirCacheTime,
    String? bufferSize,
    String? vfsReadChunkSize,
    int? transfers,
    int? checkers,
    String? bwlimit,
    String? uid,
    String? gid,
    String? umask,
    String? dirPerms,
    String? filePerms,
    bool? allowOther,
    String? logLevel,
    String? extraArgs,
  }) {
    return RcloneMountFlags(
      vfsCacheMode: vfsCacheMode ?? this.vfsCacheMode,
      vfsCacheMaxSize: vfsCacheMaxSize ?? this.vfsCacheMaxSize,
      vfsCacheMaxAge: vfsCacheMaxAge ?? this.vfsCacheMaxAge,
      dirCacheTime: dirCacheTime ?? this.dirCacheTime,
      bufferSize: bufferSize ?? this.bufferSize,
      vfsReadChunkSize: vfsReadChunkSize ?? this.vfsReadChunkSize,
      transfers: transfers ?? this.transfers,
      checkers: checkers ?? this.checkers,
      bwlimit: bwlimit ?? this.bwlimit,
      uid: uid ?? this.uid,
      gid: gid ?? this.gid,
      umask: umask ?? this.umask,
      dirPerms: dirPerms ?? this.dirPerms,
      filePerms: filePerms ?? this.filePerms,
      allowOther: allowOther ?? this.allowOther,
      logLevel: logLevel ?? this.logLevel,
      extraArgs: extraArgs ?? this.extraArgs,
    );
  }

  Map<String, dynamic> toJson() => {
        'vfsCacheMode': vfsCacheMode,
        'vfsCacheMaxSize': vfsCacheMaxSize,
        'vfsCacheMaxAge': vfsCacheMaxAge,
        'dirCacheTime': dirCacheTime,
        'bufferSize': bufferSize,
        'vfsReadChunkSize': vfsReadChunkSize,
        'transfers': transfers,
        'checkers': checkers,
        'bwlimit': bwlimit,
        'uid': uid,
        'gid': gid,
        'umask': umask,
        'dirPerms': dirPerms,
        'filePerms': filePerms,
        'allowOther': allowOther,
        'logLevel': logLevel,
        'extraArgs': extraArgs,
      };

  factory RcloneMountFlags.fromJson(Map<String, dynamic>? json) {
    if (json == null) return const RcloneMountFlags();
    return RcloneMountFlags(
      vfsCacheMode: json['vfsCacheMode'] as String? ?? 'writes',
      vfsCacheMaxSize: json['vfsCacheMaxSize'] as String? ?? '1G',
      vfsCacheMaxAge: json['vfsCacheMaxAge'] as String? ?? '24h',
      dirCacheTime: json['dirCacheTime'] as String? ?? '5m',
      bufferSize: json['bufferSize'] as String? ?? '16M',
      vfsReadChunkSize: json['vfsReadChunkSize'] as String? ?? '128M',
      transfers: (json['transfers'] as num?)?.toInt() ?? 4,
      checkers: (json['checkers'] as num?)?.toInt() ?? 8,
      bwlimit: json['bwlimit'] as String? ?? '',
      uid: json['uid'] as String? ?? '',
      gid: json['gid'] as String? ?? '9997',
      umask: json['umask'] as String? ?? '0',
      dirPerms: json['dirPerms'] as String? ?? '0771',
      filePerms: json['filePerms'] as String? ?? '0660',
      allowOther: json['allowOther'] as bool? ?? true,
      logLevel: json['logLevel'] as String? ?? 'INFO',
      extraArgs: json['extraArgs'] as String? ?? '',
    );
  }
}

class MountProfile {
  const MountProfile({
    required this.id,
    required this.name,
    required this.remoteName,
    this.remotePath = '',
    required this.localPath,
    this.enabled = false,
    this.flags = const RcloneMountFlags(),
  });

  final String id;
  final String name;
  final String remoteName;
  final String remotePath;
  final String localPath;
  final bool enabled;
  final RcloneMountFlags flags;

  String get remoteSpec =>
      remotePath.isEmpty ? '$remoteName:' : '$remoteName:$remotePath';

  MountProfile copyWith({
    String? id,
    String? name,
    String? remoteName,
    String? remotePath,
    String? localPath,
    bool? enabled,
    RcloneMountFlags? flags,
  }) {
    return MountProfile(
      id: id ?? this.id,
      name: name ?? this.name,
      remoteName: remoteName ?? this.remoteName,
      remotePath: remotePath ?? this.remotePath,
      localPath: localPath ?? this.localPath,
      enabled: enabled ?? this.enabled,
      flags: flags ?? this.flags,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'remoteName': remoteName,
        'remotePath': remotePath,
        'localPath': localPath,
        'enabled': enabled,
        'flags': flags.toJson(),
      };

  factory MountProfile.fromJson(Map<String, dynamic> json) {
    return MountProfile(
      id: json['id'] as String,
      name: json['name'] as String? ?? json['id'] as String,
      remoteName: json['remoteName'] as String? ?? '',
      remotePath: json['remotePath'] as String? ?? '',
      localPath: json['localPath'] as String? ?? '/storage/emulated/0/Cloud',
      enabled: json['enabled'] as bool? ?? false,
      flags: RcloneMountFlags.fromJson(
        (json['flags'] as Map?)?.cast<String, dynamic>(),
      ),
    );
  }
}

class WifiRule {
  const WifiRule({
    required this.id,
    this.kind = 'wifi',
    required this.ssid,
    required this.trigger,
    this.vpnName = '',
    this.vpnTrigger = 'connect',
    this.triggerSource = 'vpn',
    required this.action,
    required this.profileIds,
    this.enabled = true,
  });

  final String id;
  /// wifi | vpn | both（both 为「前提状态 + 触发器」）
  final String kind;
  final String ssid;
  final String trigger;
  final String vpnName;
  final String vpnTrigger;
  /// both 时哪一侧是触发器：wifi | vpn
  final String triggerSource;
  final String action;
  final List<String> profileIds;
  final bool enabled;

  bool get isVpn => kind == 'vpn';
  bool get isBoth => kind == 'both';
  bool get usesWifi => kind == 'wifi' || kind == 'both';
  bool get usesVpn => kind == 'vpn' || kind == 'both';
  bool get triggerIsVpn => !isBoth || triggerSource == 'vpn';

  String get wifiTrigger => usesWifi ? trigger : 'connect';
  String get resolvedVpnName => kind == 'vpn' && vpnName.isEmpty ? ssid : vpnName;
  String get resolvedVpnTrigger => kind == 'vpn' && vpnName.isEmpty ? trigger : vpnTrigger;

  WifiRule copyWith({
    String? id,
    String? kind,
    String? ssid,
    String? trigger,
    String? vpnName,
    String? vpnTrigger,
    String? triggerSource,
    String? action,
    List<String>? profileIds,
    bool? enabled,
  }) {
    return WifiRule(
      id: id ?? this.id,
      kind: kind ?? this.kind,
      ssid: ssid ?? this.ssid,
      trigger: trigger ?? this.trigger,
      vpnName: vpnName ?? this.vpnName,
      vpnTrigger: vpnTrigger ?? this.vpnTrigger,
      triggerSource: triggerSource ?? this.triggerSource,
      action: action ?? this.action,
      profileIds: profileIds ?? this.profileIds,
      enabled: enabled ?? this.enabled,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'kind': kind,
        'ssid': ssid,
        'trigger': trigger,
        'vpnName': vpnName,
        'vpnTrigger': vpnTrigger,
        'triggerSource': triggerSource,
        'action': action,
        'profileIds': profileIds,
        'enabled': enabled,
      };

  factory WifiRule.fromJson(Map<String, dynamic> json) {
    final kind = json['kind'] as String? ?? 'wifi';
    final ssid = json['ssid'] as String? ?? '';
    final trigger = json['trigger'] as String? ?? 'connect';
    return WifiRule(
      id: json['id'] as String,
      kind: kind,
      ssid: ssid,
      trigger: trigger,
      vpnName: json['vpnName'] as String? ?? (kind == 'vpn' ? ssid : ''),
      vpnTrigger: json['vpnTrigger'] as String? ?? (kind == 'vpn' ? trigger : 'connect'),
      triggerSource: json['triggerSource'] as String? ?? 'vpn',
      action: json['action'] as String? ?? 'mount',
      profileIds: ((json['profileIds'] as List?) ?? const [])
          .map((e) => e.toString())
          .toList(),
      enabled: json['enabled'] as bool? ?? true,
    );
  }
}

class AppSettings {
  const AppSettings({
    this.preferRealMount = true,
    this.startOnBoot = true,
    this.unmountOnKill = false,
    this.wifiMonitorEnabled = true,
  });

  final bool preferRealMount;
  final bool startOnBoot;
  final bool unmountOnKill;
  final bool wifiMonitorEnabled;

  AppSettings copyWith({
    bool? preferRealMount,
    bool? startOnBoot,
    bool? unmountOnKill,
    bool? wifiMonitorEnabled,
  }) {
    return AppSettings(
      preferRealMount: preferRealMount ?? this.preferRealMount,
      startOnBoot: startOnBoot ?? this.startOnBoot,
      unmountOnKill: unmountOnKill ?? this.unmountOnKill,
      wifiMonitorEnabled: wifiMonitorEnabled ?? this.wifiMonitorEnabled,
    );
  }

  Map<String, dynamic> toJson() => {
        'preferRealMount': preferRealMount,
        'startOnBoot': startOnBoot,
        'unmountOnKill': unmountOnKill,
        'wifiMonitorEnabled': wifiMonitorEnabled,
      };

  factory AppSettings.fromJson(Map<String, dynamic> json) {
    return AppSettings(
      preferRealMount: json['preferRealMount'] as bool? ?? true,
      startOnBoot: json['startOnBoot'] as bool? ?? json['restoreOnBoot'] as bool? ?? true,
      unmountOnKill: json['unmountOnKill'] as bool? ?? false,
      wifiMonitorEnabled: json['wifiMonitorEnabled'] as bool? ?? true,
    );
  }

  static AppSettings decode(String raw) {
    if (raw.trim().isEmpty) return const AppSettings();
    return AppSettings.fromJson(jsonDecode(raw) as Map<String, dynamic>);
  }
}

class RemoteInfo {
  const RemoteInfo({required this.name, required this.type, this.params = const {}});

  final String name;
  final String type;
  final Map<String, dynamic> params;
}

class RemoteEntry {
  const RemoteEntry({
    required this.path,
    required this.name,
    required this.isDir,
    this.size = 0,
    this.modTime,
    this.mimeType,
  });

  final String path;
  final String name;
  final bool isDir;
  final int size;
  final DateTime? modTime;
  final String? mimeType;

  factory RemoteEntry.fromJson(Map<String, dynamic> json) {
    DateTime? time;
    final raw = json['ModTime'] ?? json['modTime'];
    if (raw is String && raw.isNotEmpty) {
      time = DateTime.tryParse(raw);
    }
    return RemoteEntry(
      path: (json['Path'] ?? json['path'] ?? json['Name'] ?? '').toString(),
      name: (json['Name'] ?? json['name'] ?? '').toString(),
      isDir: json['IsDir'] == true || json['isDir'] == true,
      size: (json['Size'] as num?)?.toInt() ?? (json['size'] as num?)?.toInt() ?? 0,
      modTime: time,
      mimeType: json['MimeType'] as String? ?? json['mimeType'] as String?,
    );
  }
}

class NativeStatus {
  const NativeStatus({
    this.rootAvailable = false,
    this.binariesReady = false,
    this.rcloneReady = false,
    this.fusermountReady = false,
    this.rcdRunning = false,
    this.rcdUrl = 'http://127.0.0.1:5572/',
    this.rcdUser = 'rclone',
    this.rcdPass = '',
    this.rcloneVersion = '',
    this.abi = '',
    this.filesDir = '',
    this.configPath = '',
    this.currentSsid,
    this.currentVpn,
    this.locationGranted = false,
    this.locationEnabled = false,
    this.nearbyWifiGranted = false,
    this.wifiHint = '',
    this.mountedIds = const [],
    this.serviceRunning = false,
    this.hasAllFiles = false,
    this.batteryIgnored = false,
    this.bootHookInstalled = false,
  });

  final bool rootAvailable;
  final bool binariesReady;
  final bool rcloneReady;
  final bool fusermountReady;
  final bool rcdRunning;
  final String rcdUrl;
  final String rcdUser;
  final String rcdPass;
  final String rcloneVersion;
  final String abi;
  final String filesDir;
  final String configPath;
  final String? currentSsid;
  final String? currentVpn;
  final bool locationGranted;
  final bool locationEnabled;
  final bool nearbyWifiGranted;
  final String wifiHint;
  final List<String> mountedIds;
  final bool serviceRunning;
  final bool hasAllFiles;
  final bool batteryIgnored;
  final bool bootHookInstalled;

  bool get canRealMount => rootAvailable && fusermountReady && rcloneReady;

  bool get needsPermissionSetup => !hasAllFiles || !batteryIgnored;

  NativeStatus copyWith({
    bool? rootAvailable,
    bool? binariesReady,
    bool? rcloneReady,
    bool? fusermountReady,
    bool? rcdRunning,
    String? rcdUrl,
    String? rcdUser,
    String? rcdPass,
    String? rcloneVersion,
    String? abi,
    String? filesDir,
    String? configPath,
    String? currentSsid,
    String? currentVpn,
    bool? locationGranted,
    bool? locationEnabled,
    bool? nearbyWifiGranted,
    String? wifiHint,
    List<String>? mountedIds,
    bool? serviceRunning,
    bool? hasAllFiles,
    bool? batteryIgnored,
    bool? bootHookInstalled,
  }) {
    return NativeStatus(
      rootAvailable: rootAvailable ?? this.rootAvailable,
      binariesReady: binariesReady ?? this.binariesReady,
      rcloneReady: rcloneReady ?? this.rcloneReady,
      fusermountReady: fusermountReady ?? this.fusermountReady,
      rcdRunning: rcdRunning ?? this.rcdRunning,
      rcdUrl: rcdUrl ?? this.rcdUrl,
      rcdUser: rcdUser ?? this.rcdUser,
      rcdPass: rcdPass ?? this.rcdPass,
      rcloneVersion: rcloneVersion ?? this.rcloneVersion,
      abi: abi ?? this.abi,
      filesDir: filesDir ?? this.filesDir,
      configPath: configPath ?? this.configPath,
      currentSsid: currentSsid ?? this.currentSsid,
      currentVpn: currentVpn ?? this.currentVpn,
      locationGranted: locationGranted ?? this.locationGranted,
      locationEnabled: locationEnabled ?? this.locationEnabled,
      nearbyWifiGranted: nearbyWifiGranted ?? this.nearbyWifiGranted,
      wifiHint: wifiHint ?? this.wifiHint,
      mountedIds: mountedIds ?? this.mountedIds,
      serviceRunning: serviceRunning ?? this.serviceRunning,
      hasAllFiles: hasAllFiles ?? this.hasAllFiles,
      batteryIgnored: batteryIgnored ?? this.batteryIgnored,
      bootHookInstalled: bootHookInstalled ?? this.bootHookInstalled,
    );
  }

  factory NativeStatus.fromMap(Map<dynamic, dynamic> map) {
    return NativeStatus(
      rootAvailable: map['rootAvailable'] == true,
      binariesReady: map['binariesReady'] == true,
      rcloneReady: map['rcloneReady'] == true,
      fusermountReady: map['fusermountReady'] == true,
      rcdRunning: map['rcdRunning'] == true,
      rcdUrl: (map['rcdUrl'] ?? 'http://127.0.0.1:5572/').toString(),
      rcdUser: (map['rcdUser'] ?? 'rclone').toString(),
      rcdPass: (map['rcdPass'] ?? '').toString(),
      rcloneVersion: (map['rcloneVersion'] ?? '').toString(),
      abi: (map['abi'] ?? '').toString(),
      filesDir: (map['filesDir'] ?? '').toString(),
      configPath: (map['configPath'] ?? '').toString(),
      currentSsid: map['currentSsid']?.toString(),
      currentVpn: map['currentVpn']?.toString(),
      locationGranted: map['locationGranted'] == true,
      locationEnabled: map['locationEnabled'] == true,
      nearbyWifiGranted: map['nearbyWifiGranted'] == true,
      wifiHint: (map['wifiHint'] ?? '').toString(),
      mountedIds: ((map['mountedIds'] as List?) ?? const [])
          .map((e) => e.toString())
          .toList(),
      serviceRunning: map['serviceRunning'] == true,
      hasAllFiles: map['hasAllFiles'] == true,
      batteryIgnored: map['batteryIgnored'] == true,
      bootHookInstalled: map['bootHookInstalled'] == true,
    );
  }
}

class LogItem {
  const LogItem({
    required this.time,
    required this.level,
    required this.message,
  });

  final DateTime time;
  final String level;
  final String message;
}

List<MountProfile> decodeMounts(String raw) {
  if (raw.trim().isEmpty) return [];
  final list = jsonDecode(raw) as List<dynamic>;
  return list
      .map((e) => MountProfile.fromJson((e as Map).cast<String, dynamic>()))
      .toList();
}

List<WifiRule> decodeWifiRules(String raw) {
  if (raw.trim().isEmpty) return [];
  final list = jsonDecode(raw) as List<dynamic>;
  return list
      .map((e) => WifiRule.fromJson((e as Map).cast<String, dynamic>()))
      .toList();
}
