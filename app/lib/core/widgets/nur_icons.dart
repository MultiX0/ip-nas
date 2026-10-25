// Nur icon set: one semantic name per meaning, backed by Lucide (lucide.dev, ISC). Use these names instead of
// Material `Icons.*` so the app keeps one visual language and the icon family can be swapped in one place.
// Direction-aware glyphs (back, forward, chevrons) use Lucide's `Dir` variants, which mirror in RTL (Arabic).
import 'package:flutter/widgets.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

abstract final class NurIcons {
  // Navigation and shell
  static const IconData newChat = LucideIcons.squarePen;
  static const IconData sidebarClose = LucideIcons.panelLeftCloseDir;
  static const IconData sidebarOpen = LucideIcons.panelLeftOpenDir;
  static const IconData menu = LucideIcons.textAlignStartDir;
  static const IconData search = LucideIcons.search;
  static const IconData settings = LucideIcons.settings;
  static const IconData back = LucideIcons.arrowLeftDir;
  static const IconData forward = LucideIcons.arrowRightDir;
  static const IconData close = LucideIcons.x;
  static const IconData more = LucideIcons.ellipsis;
  static const IconData moreVertical = LucideIcons.ellipsisVertical;
  static const IconData chevron = LucideIcons.chevronRightDir;
  static const IconData chevronLeft = LucideIcons.chevronLeft; // fixed direction (branch arrows)
  static const IconData chevronRight = LucideIcons.chevronRight; // fixed direction (branch arrows)
  static const IconData chevronDown = LucideIcons.chevronDown;
  static const IconData externalLink = LucideIcons.externalLink;
  static const IconData scrollDown = LucideIcons.arrowDown;

  // Composer
  static const IconData send = LucideIcons.arrowUp;
  static const IconData stop = LucideIcons.square;
  static const IconData add = LucideIcons.plus;
  static const IconData mic = LucideIcons.mic;
  static const IconData micOff = LucideIcons.micOff;
  static const IconData voice = LucideIcons.audioLines;
  static const IconData attach = LucideIcons.paperclip;
  static const IconData image = LucideIcons.image;
  static const IconData camera = LucideIcons.camera;
  static const IconData file = LucideIcons.fileText;
  static const IconData fileUpload = LucideIcons.fileUp;
  static const IconData brokenImage = LucideIcons.imageOff;
  static const IconData think = LucideIcons.lightbulb;
  static const IconData tools = LucideIcons.wrench;
  static const IconData paste = LucideIcons.clipboardPaste;

  // Message actions
  static const IconData copy = LucideIcons.copy;
  static const IconData check = LucideIcons.check;
  static const IconData edit = LucideIcons.pencil;
  static const IconData rename = LucideIcons.pencilLine;
  static const IconData regenerate = LucideIcons.refreshCw;
  static const IconData refresh = LucideIcons.rotateCw;
  static const IconData sync = LucideIcons.refreshCw;
  static const IconData reset = LucideIcons.rotateCcw;
  static const IconData export = LucideIcons.share;
  static const IconData info = LucideIcons.info;
  static const IconData play = LucideIcons.play;
  static const IconData pause = LucideIcons.pause;

  // Chat list
  static const IconData chat = LucideIcons.messageCircle;
  static const IconData pin = LucideIcons.pin;
  static const IconData unpin = LucideIcons.pinOff;
  static const IconData archive = LucideIcons.archive;
  static const IconData unarchive = LucideIcons.archiveRestore;
  static const IconData delete = LucideIcons.trash2;

  // Models, memory, tools
  static const IconData memory = LucideIcons.brain;
  static const IconData skills = LucideIcons.bookOpen;
  static const IconData agent = LucideIcons.bot;
  static const IconData sparkle = LucideIcons.sparkles;
  static const IconData models = LucideIcons.boxes;
  static const IconData providers = LucideIcons.plug;
  static const IconData mcp = LucideIcons.plugZap;
  static const IconData extension = LucideIcons.puzzle;
  static const IconData compress = LucideIcons.foldVertical;
  static const IconData context = LucideIcons.gauge;
  static const IconData favorite = LucideIcons.star;
  static const IconData vision = LucideIcons.eye;
  static const IconData visibility = LucideIcons.eye;
  static const IconData visibilityOff = LucideIcons.eyeOff;
  static const IconData tune = LucideIcons.slidersHorizontal;
  static const IconData link = LucideIcons.link;
  static const IconData webSearch = LucideIcons.globe;
  static const IconData explore = LucideIcons.telescope;
  static const IconData terminal = LucideIcons.squareTerminal;
  static const IconData health = LucideIcons.activity;

  // NAS and system
  static const IconData nas = LucideIcons.serverNas;
  static const IconData apps = LucideIcons.layoutGrid;
  static const IconData appsError = LucideIcons.layoutGrid;
  static const IconData container = LucideIcons.container;
  static const IconData runtime = LucideIcons.cog;
  static const IconData disk = LucideIcons.hardDrive;
  static const IconData temperature = LucideIcons.thermometer;
  static const IconData cpu = LucideIcons.cpu;
  static const IconData ram = LucideIcons.memoryStick;
  static const IconData localModel = LucideIcons.cpuAi;
  static const IconData network = LucideIcons.arrowDownUp;
  static const IconData uptime = LucideIcons.clock;
  static const IconData wifi = LucideIcons.wifi;
  static const IconData wifiOff = LucideIcons.wifiOff;
  static const IconData download = LucideIcons.download;
  static const IconData cloud = LucideIcons.cloud;
  static const IconData computer = LucideIcons.monitor;
  static const IconData pairDevice = LucideIcons.smartphoneNfc;

  // Status
  static const IconData success = LucideIcons.circleCheck;
  static const IconData warning = LucideIcons.triangleAlert;
  static const IconData error = LucideIcons.circleAlert;
  static const IconData blocked = LucideIcons.ban;

  // Account and app
  static const IconData shield = LucideIcons.shield;
  static const IconData shieldCheck = LucideIcons.shieldCheck;
  static const IconData key = LucideIcons.keyRound;
  static const IconData theme = LucideIcons.sunMoon;
  static const IconData language = LucideIcons.languages;
  static const IconData person = LucideIcons.userRound;

  // Voice calls
  static const IconData captions = LucideIcons.captions;
  static const IconData captionsOff = LucideIcons.captionsOff;
  static const IconData flash = LucideIcons.zap;
}
