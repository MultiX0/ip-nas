// Turn planner for small local models: a deterministic intent classifier (English, Arabic MSA and common dialects)
// that runs before the model. It never answers: every reply is written by the model. NAS questions call the right
// tool first, so the model answers from real values; app actions ("restart jellyfin", "stop it") resolve the name
// against the real container list and call docker_action (the user still approves it); small talk, identity and
// requests Nur cannot do get a short answer frame and no tools. Pure Dart, no Flutter imports.
import '../memory/memory_text.dart' show normalizeText;

enum TurnIntent {
  greeting,
  thanks,
  ack,
  bye,
  howAreYou,
  identity,
  capabilities,
  remember,
  recallMemory,
  cannotDo,
  unsafe,
  nasStatus,
  apps,
  appAction,
  webSearch,
  troubleshoot,
  chat,
}

/// A tool call the app makes itself before (or instead of) the model.
class PlannedCall {
  final String tool;
  final Map<String, dynamic> args;
  const PlannedCall(this.tool, [this.args = const {}]);
}

class TurnPlan {
  final TurnIntent intent;
  final String lang; // 'ar' | 'en'
  /// Tool calls the app runs first, in order (an app action may need the container list first).
  final List<PlannedCall> calls;
  /// nasStatus: which values were asked for (temp, ram, disk, cpu, uptime; empty = overall health).
  final Set<String> focus;
  /// App the user named or referred to ("it"), for apps / appAction.
  final String? app;
  final String? action;
  /// Request-only answer frame for the model (appended to the latest user message).
  final String? hint;
  /// Built-in skill whose quick card helps this turn (small models get the card, not the whole skill).
  final String? skill;
  /// The fact to save ("remember that ..."); the engine saves it before the model answers.
  final String? fact;
  /// Advice, explanations and definitions: the model answers from what it knows. Offered tools, a small model
  /// checks the NAS instead and reports its values ("best way to cool the Pi" got the current RAM and temperature).
  final bool noTools;
  const TurnPlan(this.intent, this.lang,
      {this.calls = const [],
      this.focus = const {},
      this.app,
      this.action,
      this.hint,
      this.skill,
      this.fact,
      this.noTools = false});

  TurnPlan copyWith({String? app, String? hint}) => TurnPlan(intent, lang,
      calls: calls,
      focus: focus,
      app: app ?? this.app,
      action: action,
      hint: hint ?? this.hint,
      skill: skill,
      fact: fact,
      noTools: noTools);
}

class PlanContext {
  /// User messages before this one in the visible chat.
  final int priorUserTurns;
  /// Container names from the latest docker_list in this chat (empty when unknown).
  final List<String> knownApps;
  /// The app most recently mentioned in this chat (for "restart it").
  final String? lastApp;
  final bool voice;
  const PlanContext({this.priorUserTurns = 0, this.knownApps = const [], this.lastApp, this.voice = false});
}


final _askLangEn = RegExp(
    r'\b(in|into|to)\s+(arabic|english|french|german|spanish|turkish|urdu|persian|farsi|hindi|italian|russian|chinese|japanese|korean)\b|\btranslat',
    caseSensitive: false);
final _askLangAr = RegExp(r'بالعربي|بالإنجليزي|بالانجليزي|بالإنكليزي|بالانكليزي|بالفرنسي|ترجم');

/// The user asks for a given language or a translation ("say hello in Arabic", "ترجم هذا"), so the reply
/// language is theirs to choose and the language lock stays off.
bool asksForLanguage(String text) => _askLangEn.hasMatch(text) || _askLangAr.hasMatch(text);

/// 'ar' when the text has more Arabic than Latin letters.
/// Counts WORDS, not letters: "شغّل jellyfin" or "كم ال RAM الفاضية؟" are Arabic messages with Latin app names / terms.
String detectLang(String text) {
  final a = RegExp(r'[؀-ۿ]+').allMatches(text).length;
  final l = RegExp(r'[A-Za-z]+').allMatches(text).length;
  if (a == 0) return 'en';
  return a >= l ? 'ar' : 'en';
}


String _en(String s) => s.toLowerCase().replaceAll('’', "'").replaceAll(RegExp(r'\s+'), ' ').trim();
String _ar(String s) => normalizeText(s).replaceAll(RegExp(r'\s+'), ' ').trim();

/// Strips punctuation and emojis around a short message.
String _bare(String s) => s.replaceAll(RegExp(r'''[!?.,;:،؛؟\u2026"'\u201C\u201D\u00AB\u00BB()\[\]{}*~_\-]+|[\u{1F300}-\u{1FAFF}\u{2600}-\u{27BF}]''', unicode: true), ' ')
    .replaceAll(RegExp(r'\s+'), ' ')
    .trim();

RegExp _arRx(String p) => RegExp(normalizeText(p));

final _thanksEn = RegExp(r"^(ok(ay)?|great|cool|perfect|nice|awesome|good|got it|alright|all right|super)?\s*(thanks?( you)?( so much| very much| a lot)?|thx|ty|cheers|much appreciated|appreciate it|merci)( nur)?( (so much|a lot))?$");
final _thanksAr = _arRx(r'^(تمام |طيب |اوكي |ممتاز |حلو )?(شكرا( لك| جزيلا| كتير| كثير| يا نور)?|مشكور|يعطيك العافيه|الله يعطيك العافيه|تسلم|تسلم ايدك|يسلمو|جزاك الله خير|ممنون|متشكر)( يا نور)?$');
final _ackEn = RegExp(r"^(ok(ay)?|k|kk|cool|nice|great|perfect|awesome|got it|alright|all right|sure|fine|good|yep|yes|right|i see|understood|noted|sounds good|ok cool|okay cool)$");
final _ackAr = _arRx(r'^(تمام|طيب|اوكي|اوك|ممتاز|حلو|ماشي|زين|عظيم|فهمت|واضح|تمام تمام|اها|ايوه|نعم|اكيد)$');
final _byeEn = RegExp(r"^(ok(ay)? )?(bye|goodbye|good bye|bye bye|see you|see ya|later|good night|goodnight|talk later|cya)( nur)?$");
final _byeAr = _arRx(r'^(مع السلامه|باي|الى اللقاء|تصبح على خير|سلام|يلا باي)$');
final _greetEn = RegExp(r"^(hi|hello|hey|hiya|yo|greetings|good (morning|afternoon|evening)|morning|hey there|hi there|hello there)( nur)?$");
final _greetAr = _arRx(r'^(مرحبا|مرحباً|اهلا|اهلا وسهلا|هلا|هلا والله|السلام عليكم|سلام عليكم|صباح الخير|مساء الخير|صباح النور|مساء النور|هاي)( يا نور| نور)?$');
final _howEn = RegExp(r"^((hi|hello|hey)( nur)?,? )?(how are you( doing| today)?|how's it going|how are things|how do you do|how are you nur|you good|what's up|whats up|sup)( nur)?$");
final _howAr = _arRx(r'^((مرحبا|اهلا|هلا) )?(كيفك|كيف حالك|كيف الحال|شلونك|ازيك|عامل ايه|كيف انت|اخبارك|شو اخبارك|كيفك اليوم|وش لونك|شخبارك)( يا نور)?$');

final _identityEn = RegExp(r"\b(who are you|what are you|what'?s your name|what is your name|your name\??$|introduce yourself|are you (an? )?(ai|bot|robot|human|chatgpt|gpt))\b");
final _identityAr = _arRx(r'(من انت|مين انت|من تكون|ما اسمك|شو اسمك|وش اسمك|ايش اسمك|عرفني بنفسك|عرف عن نفسك|هل انت انسان|هل انت روبوت)');
final _capsEn = RegExp(r"\b(what can you do|what (else )?can you help( me)? with|what are you (able|capable) (to do|of)|what are you able to help|how can you help|what do you do|your (capabilities|features|abilities)|what are your (skills|capabilities|features))\b");
final _capsAr = _arRx(r'(ماذا تستطيع|ماذا يمكنك|ماذا تقدر|ما الذي تستطيع|شو بتقدر|شو تقدر|ايش تقدر|وش تقدر|ايش بتعرف تعمل|شو بتعمل|ما هي قدراتك|ما قدراتك|كيف تساعدني|كيف ممكن تساعدني|بماذا تساعدني)');

final _recallEn = RegExp(r"\b(what do you (know|remember) about me|what have you (saved|stored|remembered)|do you (know|remember) (anything|something) about me|what('?s| is) my name|do you (know|remember) my name|tell me what you (know|remember) about me|what do you remember)\b");
final _recallAr = _arRx(r'(ماذا تعرف عني|ماذا تتذكر عني|ماذا تذكر عني|شو بتعرف عني|شو تعرف عني|وش تعرف عني|ايش تعرف عني|ما اسمي|شو اسمي|وش اسمي|هل تعرف اسمي|هل تتذكر اسمي|ماذا حفظت عني)');

final _rememberTailEn = RegExp(r"^(.{4,300}?)[\s,.;!]*(please,? )?(remember|note|save|keep in mind|don'?t forget|do not forget) (it|that|this)( please)?[.!]*$", caseSensitive: false, dotAll: true);
final _rememberHeadEn = RegExp(r"^\s*(?:hey nur[,!]?\s*)?(?:please\s+|can you\s+|could you\s+)?(?:(?:remember|keep in mind|don'?t forget|do not forget)\s*(?:that|this|:)?|(?:note|save|write down)\s*(?:that|this:|:))\s+(.{4,300}?)[.!]*$", caseSensitive: false, dotAll: true);
final _rememberAr = RegExp(r'^\s*(?:من فضلك\s+|لو سمحت\s+|ممكن\s+)?(?:تذكر|تذكّر|احفظ|سجل|سجّل|لا تنس|لا تنسى|خليك فاكر|خلّيك متذكر)\s*(?:أن|ان|إن|:)?\s+(.{3,300}?)[.!؟]*$', dotAll: true);
final _rememberTailAr = RegExp(r'^(.{3,300}?)[\s،,.!]*(?:من فضلك\s+|لو سمحت\s+)?(?:تذكر ذلك|تذكره|تذكرها|احفظ ذلك|احفظه|احفظها|سجل ذلك)[.!]*$', dotAll: true);

/// The fact in "remember that X", "X, please remember it", "تذكر أن X" (null when the message is not a request to
/// remember). The engine saves it itself, so it never depends on a small model choosing to call memory_save.
String? rememberedFact(String text) {
  final t = text.trim();
  if (t.endsWith('?') || t.endsWith('؟')) return null; // "do you remember ...?" is a question
  final m = _rememberHeadEn.firstMatch(t) ?? _rememberTailEn.firstMatch(t) ?? _rememberAr.firstMatch(t) ?? _rememberTailAr.firstMatch(t);
  if (m == null) return null;
  final g = m.groupCount >= 1 ? m.group(1) : null;
  final fact = (g ?? '').trim().replaceAll(RegExp(r'[\s.!؟?,،]+$'), '');
  if (fact.length < 3 || RegExp(r'^(it|that|this|me)$|^to ', caseSensitive: false).hasMatch(fact)) return null;
  return fact;
}

// Things Nur cannot do (capability honesty). Each maps to an honest one-line answer.
final _cannotEn = <String, RegExp>{
  'media': RegExp(r"\b(play|stream|put on|cast)\b.{0,30}\b(music|song|songs|movie|movies|film|video|videos|playlist|show|series|episode|radio|podcast)\b|\b(stream|cast)\b.{0,20}\b(tv|television)\b"),
  'alarm': RegExp(r"\b(set|create|make|add)\b.{0,20}\b(alarm|timer|reminder)\b|\bremind me\b|\bremember to\b|\bwake me\b|\b(alarm|timer) for\b"),
  'message': RegExp(r"\b(send|write and send|text|email|e-mail|call|phone|message)\b.{0,30}\b(email|e-mail|mail|sms|text|message|whatsapp|my (boss|mom|dad|wife|husband|friend)|someone)\b"),
  'smarthome': RegExp(r"\b(turn|switch|dim|set)\b.{0,15}\b(on|off|up|down)?\b.{0,20}\b(lights?|lamp|lamps|ac|air ?con\w*|heater|heating|thermostat|tv|television|fan|door|lock|blinds|plug)\b"),
  'order': RegExp(r"\b(order|buy|purchase|book)\b.{0,20}\b(pizza|food|meal|taxi|uber|ticket|tickets|flight|hotel|groceries|something|me)\b"),
  'backup': RegExp(r"\b(back ?up|sync|copy|upload|transfer)\b.{0,30}\b(my )?(phone|iphone|android|laptop|computer|pc)?\b.{0,20}\b(photos?|pictures|files|videos|contacts)\b.{0,30}\b(to|onto|into)\b.{0,10}\b(the |my )?(nas|server)\b"),
  'power': RegExp(r"\b(reboot|restart|shut ?down|power (off|down)|turn off)\b.{0,10}\b(the |my )?(nas|pi|raspberry pi|server|system|whole thing)\b"),
};
final _cannotAr = <String, RegExp>{
  'media': _arRx(r'(شغل|شغلي|شغل لي|اعرض|ابث|بث|افتح)\s?(لي )?.{0,15}(اغنيه|اغاني|موسيقي|فيلم|افلام|مسلسل|فيديو|حلقه|راديو|بودكاست)'),
  'alarm': _arRx(r'(منبه|اضبط المنبه|ذكرني|نبهني|صحيني|مؤقت|تايمر)'),
  'message': _arRx(r'(ارسل|ابعث|ابعت|راسل|اتصل)\s?.{0,20}(بريد|ايميل|رساله|مسج|واتساب|ب)'),
  'smarthome': _arRx(r'(اطفئ|اطفي|طفي|شغل|افتح|سكر|اغلق)\s?.{0,10}(الاضاءه|الانوار|الضوء|اللمبه|المكيف|التلفزيون|التلفاز|الشاشه|السخان|الباب|المروحه)'),
  'order': _arRx(r'(اطلب لي|اطلبلي|تطلب لي|اشتر|احجز)\s?.{0,15}(بيتزا|اكل|طعام|وجبه|تاكسي|اوبر|تذكره|طياره|فندق)?'),
  'power': _arRx(r'(اعد تشغيل|اعاده تشغيل|طفي|اطفئ|اغلق|ريستارت|وقف|اوقف)\s(الجهاز|السيرفر|الخادم|الناس|الراسبيري)'),
};

final _unsafeEn = <String, RegExp>{
  'destroy': RegExp(r"\brm\s+-\w*r\w*f?|\bmkfs\b|\bdd\s+if=|\bformat\b.{0,20}\b(drive|disk|hdd|ssd|sd|partition|nas|storage)\b|\b(delete|erase|wipe|remove|destroy)\b.{0,15}\b(all|every|everything)\b.{0,25}\b(files?|data|folders?|disks?|drives?|nas|storage|photos?)?|\bwipe\b.{0,20}\b(drive|disk|nas|everything)\b|\bchmod\s+-r\s+777\s+/|\bfactory reset\b"),
  'secret': RegExp(r"\b(root |admin |ssh |sudo |wifi |wi-fi )?password\b|\bprivate key\b|\bapi key\b"),
  'exposure': RegExp(r"\b(disable|turn off)\b.{0,15}\bfirewall\b|\bopen all ports\b"),
};
final _unsafeAr = <String, RegExp>{
  'destroy': _arRx(r'((امسح|احذف|امحي|امحِ|شيل|ازل) (كل|جميع)|فرمت|فورمات|تهيئه القرص|تهيئه الهارد|مسح كامل|rm -rf)'),
  'secret': _arRx(r'(كلمه السر|كلمه المرور|الباسورد|باسورد|كلمه مرور)'),
};

// NAS status: words that mean live values (EN + AR + dialect), and which value they ask for.
final _focusEn = <String, RegExp>{
  'temp': RegExp(r"\b(temp|temps|temperature|temperatures|hot|hotter|heat|overheat\w*|warm|cool|cooling|thermal|thrott\w*|degrees?)\b"),
  'ram': RegExp(r"\b(ram|memory usage|free memory|memory free|memory left|available memory|how much memory|memory)\b"),
  'disk': RegExp(r"\b(disks?|drives?|storage|space|hdd\d?|ssd|full|capacity|free space)\b"),
  'cpu': RegExp(r"\b(cpu|processor|load)\b"),
  'uptime': RegExp(r"\b(uptime|up time|how long .{0,20}(up|running|on))\b"),
};
final _focusAr = <String, RegExp>{
  'temp': _arRx(r'(حراره|حرارة|الحراره|سخن|ساخن|سخونه|حامي|بارد|تبريد|درجه)'),
  'ram': _arRx(r'(رام|الرام|ذاكره|الذاكره|ميموري)'),
  'disk': _arRx(r'(قرص|اقراص|الاقراص|القرص|مساحه|المساحه|تخزين|التخزين|هارد|الهارد|ممتلئ|الديسك)'),
  'cpu': _arRx(r'(معالج|المعالج|الحمل|cpu)'),
  'uptime': _arRx(r'(منذ متي يعمل|مده التشغيل|من متي شغال)'),
};
final _healthEn = RegExp(
    r"\b(how('?s| is| are)|status|health|healthy|doing|check|state|everything ok|all good|ok\??$|okay\??$|fine\??$|alright|running smoothly|any problems?|issues?)\b.{0,40}\b(nas|pi|raspberry|server|system|box|machine|device|home server)\b|\b(nas|pi|server|system)\b.{0,20}\b(status|health|doing|ok|okay|fine|alright)\b|^(nas|system) (status|health)$");
final _healthAr = _arRx(
    r'(كيف|شو|ما|وش|ايش|كيفك يا)?\s?(حال|حاله|وضع|اخبار|احوال)\s?(ال)?\s?(جهاز|الجهاز|السيرفر|الخادم|الناس|nas|النظام|الراسبيري)|(الجهاز|السيرفر|الناس|nas)\s?(عامل ايه|كيف حاله|بخير|تمام|شغال كويس|وضعه)|(افحص|تحقق من|شيك على|اطمن على)\s?(ال)?(جهاز|السيرفر|الناس|nas)');
final _statusQuestionEn = RegExp(r"\b(how much|how many|how hot|how full|how warm|what('?s| is| are) (the|my)|is (it|the|my)|are (the|my)|show|check|tell me|give me|current|right now|now|free|used|left|available|usage|level|and the|what about)\b|\?$|^(and|what about) ");
final _statusQuestionAr = _arRx(r'(كم|قديش|قديه|اديش|ما هي|ما هو|شو|وش|ايش|هل|كيف|اعطني|اعرض|افحص|الان|هلا|هلق|حاليا|و(ال)?(حراره|الرام|الذاكره|الاقراص|المساحه))|؟$');
final _knowledgeEn = RegExp(r"\b(what is an?|what are|what does|explain|define|definition|meaning of|difference between|how (do|does|can|should) (i|you|we)|how to|why (do|does|is|are)|tips?|advice|recommend\w*|should i (buy|get|use)|best way|history of)\b");
final _knowledgeAr = _arRx(r'(اشرح|ما معني|عرف لي|الفرق بين|كيف اقوم|كيف يمكنني|كيف اعمل|نصيحه|نصائح|انصحني|تنصحني|هل تنصح|لماذا|ليش|شو يعني|'
    r'(افضل|احسن|اسهل) (طريقه|وسيله)|ما (هي )?(ال)?طريقه|'
    r'(كيف|ازاي|شلون) (ممكن |اقدر |بقدر )?(ابرد|اخفض|اقلل|احمي|احافظ|اصلح|احل|امنع|اتجنب|انظف|اسرع|اوفر|احسن|اجعل|اركب|اثبت|اضيف|اغير))');

// Apps.
final _appsListEn = RegExp(r"\b(which|what|list|show|any)\b.{0,25}\b(apps?|applications?|containers?|services?|dockers?)\b|\b(apps?|containers?|services?)\b.{0,20}\b(running|installed|up|on the nas|do i have)\b|\bdocker (ps|status|list)\b");
final _appsListAr = _arRx(r'(التطبيقات|تطبيقات|الحاويات|حاويات|الخدمات|خدمات|الدوكر|دوكر)\s?.{0,20}(شغال|تعمل|يعمل|المثبت|مثبت|عندي|الموجود|موجود|اللي)|(ما|شو|وش|ايش|ما هي|اعرض)\s?(هي )?(ال)?(تطبيقات|حاويات|خدمات)');
final _appStateEn = RegExp(r"\b(is|are|was)\b.{0,50}\b(running|up|working|down|on|alive|started|stopped|online|ok|okay|healthy)\b|\b(status|state)\b|\bwhat about\b|\bstill (running|up|working)\b");
final _appStateAr = _arRx(r'(شغال|يعمل|تعمل|واقف|متوقف|شغاله|بيشتغل|حالته|حاله|وضعه|ماشي)');

final _actionEn = <String, RegExp>{
  'restart': RegExp(r"\b(restart|reboot|relaunch|reload|bounce)\b"),
  'stop': RegExp(r"\b(stop|shut ?down|turn off|switch off|kill|halt)\b"),
  'start': RegExp(r"\b(start|launch|turn on|switch on|bring up|boot up|run)\b"),
  'pause': RegExp(r"\bpause\b"),
  'unpause': RegExp(r"\b(unpause|resume)\b"),
  'remove': RegExp(r"\b(remove|uninstall|delete)\b"),
};
final _actionAr = <String, RegExp>{
  'restart': _arRx(r'(اعد تشغيل|اعاده تشغيل|اعيد تشغيل|ريستارت|رستارت|اعمل ريستارت|عيد تشغيل)'),
  'stop': _arRx(r'(اوقف|وقف|ايقاف|طفي|اطفئ|سكر|اقفل)'),
  'start': _arRx(r'(شغل|تشغيل|فعل|افتح)'),
  'remove': _arRx(r'(احذف|ازل|امسح|شيل)'),
};
final _itRef = RegExp(r"\b(it|that|this|that one|this one|that app|the app|that container|the container)\b");
final _itRefAr = _arRx(r'(ـه$|ه$|ها$|هو|هي|التطبيق|الحاويه|نفسه)');

const _commonApps = [
  'jellyfin', 'searxng', 'nextcloud', 'immich', 'plex', 'emby', 'syncthing', 'pihole', 'pi-hole', 'adguard', 'portainer',
  'homeassistant', 'home-assistant', 'transmission', 'qbittorrent', 'sonarr', 'radarr', 'prowlarr', 'jackett', 'navidrome',
  'photoprism', 'vaultwarden', 'gitea', 'nginx', 'traefik', 'llamacpp', 'llama.cpp', 'open-webui', 'openwebui',
  'nur-hub', 'casaos', 'filebrowser', 'samba', 'uptime-kuma', 'grafana', 'prometheus', 'mosquitto', 'node-red', 'kavita',
];

// Web search.
final _searchEn = RegExp(r"^(please |can you |could you |nur,? )?(search( the web| online| the internet| google)?( for)?|look up|lookup|google|find (out|info|information)( about| on)?|browse( for)?)\s+(.+)$");
final _freshEn = RegExp(r"\b(latest|newest|most recent|current version|recent news|news about|news on|today'?s news|price of|how much does .{2,40} cost|weather in|weather today|release date|released|stock price|exchange rate|score of|who won)\b");
final _searchAr = _arRx(r'^(من فضلك |ممكن |لو سمحت )?(ابحث|بحث|دور|فتش|جوجل)( لي)?( في الانترنت| في النت| علي الانترنت| علي النت)?( عن| على| علي)?\s+(.+)$');
final _freshAr = _arRx(r'(اخر اصدار|احدث اصدار|اخر نسخه|احدث نسخه|اخر الاخبار|اخبار|سعر|اسعار|الطقس|حاله الطقس|موعد اصدار|من فاز|سعر الصرف)');

// Troubleshooting (model answers, with the troubleshooting skill card and live status first).
final _troubleEn = RegExp(r"\b(slow|sluggish|lag\w*|freez\w*|crash\w*|not working|doesn'?t work|won'?t (start|load|open|work)|isn'?t working|broken|error|errors|fail\w*|problem|issue|keeps (restarting|crashing)|overheat\w*|too hot|almost full|disk full|out of space|no space|(is|are) (almost |nearly |completely )?full)\b");
final _troubleAr = _arRx(r'(بطيء|بطئ|ثقيل|معلق|يعلق|لا يعمل|ما يشتغل|ما بيشتغل|مش شغال|عطل|خربان|مشكله|خطا|سخن جدا|سخن كتير|سخن كثير|حامي كتير|حار جدا|حار كتير|ممتلئ|امتلا|المساحه خلصت|ما في مساحه|شو اعمل|ماذا افعل|وش اسوي|ايش اعمل|شو بعمل|ماذا يجب)');
final _yesNoEn = RegExp(r'^(is|are|was|does|do)\b');
final _yesNoAr = _arRx(r'^(هل)');

int _words(String s) => s.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).length;

/// Plans the turn for [text]. Deterministic: the same text and context always give the same plan.
TurnPlan planTurn(String text, {PlanContext ctx = const PlanContext()}) {
  final lang = detectLang(text);
  final raw = text.trim();
  if (raw.isEmpty || raw.contains('<file name=')) return TurnPlan(TurnIntent.chat, lang);
  final en = _en(raw);
  final ar = _ar(raw);
  final bareEn = _bare(en);
  final bareAr = _bare(ar);

  // Small talk (the whole message): the model answers briefly, without tools.
  if (_thanksEn.hasMatch(bareEn) || _thanksAr.hasMatch(bareAr)) return _small(TurnIntent.thanks, lang, ctx);
  if (_byeEn.hasMatch(bareEn) || _byeAr.hasMatch(bareAr)) return _small(TurnIntent.bye, lang, ctx);
  if (_howEn.hasMatch(bareEn) || _howAr.hasMatch(bareAr)) return _small(TurnIntent.howAreYou, lang, ctx);
  if (_greetEn.hasMatch(bareEn) || _greetAr.hasMatch(bareAr)) return _small(TurnIntent.greeting, lang, ctx);
  if (_ackEn.hasMatch(bareEn) || _ackAr.hasMatch(bareAr)) return _small(TurnIntent.ack, lang, ctx);

  // A greeting in front of a real request ("hi nur, how hot is my nas?") is dropped for classification.
  final body = en.replaceFirst(RegExp(r"^(hi|hello|hey|ok(ay)?|so|well|nur|hey nur|hi nur)[\s,!.]+"), '');
  final bodyAr = ar.replaceFirst(_arRx(r'^(مرحبا|اهلا|هلا|يا نور|نور|طيب|تمام)[\s،,!.]+'), '');

  // Remember X: the app saves it, the model confirms.
  final fact = rememberedFact(raw);
  if (fact != null) return TurnPlan(TurnIntent.remember, lang, fact: fact, hint: _hint('chat', lang, ctx.voice), noTools: true);

  // Destructive or secret requests: the model answers with no tools offered, so nothing can run.
  if (_unsafeEn.values.any((r) => r.hasMatch(body)) || _unsafeAr.values.any((r) => r.hasMatch(bodyAr))) {
    return TurnPlan(TurnIntent.unsafe, lang, hint: _hint('chat', lang, ctx.voice), noTools: true);
  }

  // Identity / capabilities: the model answers from its system prompt.
  if (_capsEn.hasMatch(body) || _capsAr.hasMatch(bodyAr)) return _small(TurnIntent.capabilities, lang, ctx);
  if ((_identityEn.hasMatch(body) || _identityAr.hasMatch(bodyAr)) && _words(raw) <= 10) return _small(TurnIntent.identity, lang, ctx);

  // What Nur knows about the user (the engine lists the saved memories).
  if (_recallEn.hasMatch(body) || _recallAr.hasMatch(bodyAr)) return TurnPlan(TurnIntent.recallMemory, lang);

  // App actions: "restart jellyfin", "stop it", "أعد تشغيل jellyfin".
  final app = _findApp(raw, ctx.knownApps);
  final act = _findAction(body, bodyAr);
  // "remember to restart X tomorrow" / "every night" is a schedule, not an action to run now.
  final scheduled = RegExp(r"\b(remember to|remind me|tomorrow|tonight|later|every (day|night|week|morning)|at \d|in \d+ (min|minute|hour)s?)\b").hasMatch(body) ||
      _arRx(r'(بكره|بكرة|غدا|لاحقا|بعد ساعه|كل يوم|كل ليله|ذكرني)').hasMatch(bodyAr);
  if (act != null && !scheduled && !_knowledgeEn.hasMatch(body) && !_knowledgeAr.hasMatch(bodyAr)) {
    final target = app ?? ((_itRef.hasMatch(body) || (lang == 'ar' && _itRefAr.hasMatch(bodyAr))) ? ctx.lastApp : null);
    if (target != null && _words(raw) <= 14) {
      final known = ctx.knownApps.any((a) => a.toLowerCase() == target.toLowerCase());
      return TurnPlan(TurnIntent.appAction, lang,
          app: target,
          action: act,
          calls: [if (!known) const PlannedCall('docker_list'), PlannedCall('docker_action', {'name': target, 'action': act})],
          skill: 'docker-app-manager');
    }
  }

  // Things Nur cannot do: the model answers, with no tools offered.
  if (_cannotEn.values.any((r) => r.hasMatch(body)) || (lang == 'ar' && _cannotAr.values.any((r) => r.hasMatch(bodyAr)))) {
    return _small(TurnIntent.cannotDo, lang, ctx);
  }

  // "What is RAM?" / "ما هو الرام؟" asks for a definition, not for the NAS's value.
  final definition = RegExp(r"^(what('?s| is| are)|define|explain) (an? |the )?[\w.\-]+\??$").hasMatch(bareEn) ||
      _arRx(r'^(ما هو|ما هي|ما معني|شو يعني|اشرح) [^ ]+$').hasMatch(bareAr);
  final knowledge = definition || _knowledgeEn.hasMatch(body) || _knowledgeAr.hasMatch(bodyAr);

  // Troubleshooting: check live status first, then the model explains with the troubleshooting card.
  final yesNoTemp = (_yesNoEn.hasMatch(body) || _yesNoAr.hasMatch(bodyAr)) &&
      (_focusEn['temp']!.hasMatch(body) || _focusAr['temp']!.hasMatch(bodyAr)) && _words(raw) <= 10;
  if ((_troubleEn.hasMatch(body) || _troubleAr.hasMatch(bodyAr)) && !yesNoTemp) {
    if (app != null) {
      return TurnPlan(TurnIntent.troubleshoot, lang, app: app, calls: const [PlannedCall('docker_list')], skill: 'troubleshooting',
          hint: _hint('troubleshoot', lang, ctx.voice));
    }
    final aboutNas = _focusEn.values.any((r) => r.hasMatch(body)) || _focusAr.values.any((r) => r.hasMatch(bodyAr)) ||
        RegExp(r"\b(nas|pi|server|system)\b").hasMatch(body) || _arRx(r'(الجهاز|السيرفر|الناس)').hasMatch(bodyAr);
    if (aboutNas) {
      return TurnPlan(TurnIntent.troubleshoot, lang, calls: const [PlannedCall('nas_system_status')], skill: 'troubleshooting',
          hint: _hint('troubleshoot', lang, ctx.voice));
    }
  }

  // Apps list / one app's state.
  final appsList = _appsListEn.hasMatch(body) || _appsListAr.hasMatch(bodyAr);
  final appState = app != null && (_appStateEn.hasMatch(body) || _appStateAr.hasMatch(bodyAr) || _words(raw) <= 4);
  if ((appsList || appState) && !knowledge) {
    return TurnPlan(TurnIntent.apps, lang, app: appState ? app : null, calls: const [PlannedCall('docker_list')]);
  }

  // NAS status: live values.
  final focus = <String>{
    for (final e in _focusEn.entries) if (e.value.hasMatch(body)) e.key,
    for (final e in _focusAr.entries) if (e.value.hasMatch(bodyAr)) e.key,
  };
  if (focus.contains('ram') && RegExp(r'\bremember|\bmemories\b').hasMatch(body)) focus.remove('ram');
  // "CPU temperature" / "حرارة المعالج" asks for the temperature, not the load.
  if (focus.contains('temp') && focus.contains('cpu') && !RegExp(r'\bload\b').hasMatch(body) && !_arRx('(الحمل|حمل)').hasMatch(bodyAr)) {
    focus.remove('cpu');
  }
  final health = _healthEn.hasMatch(body) || _healthAr.hasMatch(bodyAr);
  final question = _statusQuestionEn.hasMatch(body) || _statusQuestionAr.hasMatch(bodyAr) || _words(raw) <= 4;
  final notNas = RegExp(r"\b(weather|outside|outdoors?|forecast|in the city|oven|water|body|fever)\b").hasMatch(body) || _arRx(r"(الطقس|الجو|برا|خارج البيت|الحمى)").hasMatch(bodyAr);
  if (!knowledge && !notNas && (health || (focus.isNotEmpty && question))) {
    return TurnPlan(TurnIntent.nasStatus, lang, focus: focus, calls: const [PlannedCall('nas_system_status')]);
  }

  // Web search: explicit "search for X" or clearly fresh facts.
  final sm = _searchEn.firstMatch(body);
  final smAr = _searchAr.firstMatch(bodyAr);
  if (sm != null || smAr != null || _freshEn.hasMatch(body) || (lang == 'ar' && _freshAr.hasMatch(bodyAr))) {
    final q = searchQuery(raw);
    return TurnPlan(TurnIntent.webSearch, lang, calls: [PlannedCall('web_search', {'query': q})], skill: 'web-research',
        hint: _hint('web', lang, ctx.voice));
  }

  // Everything else: the model, with the general answer frame.
  return TurnPlan(TurnIntent.chat, lang, hint: _hint(knowledge ? 'knowledge' : 'chat', lang, ctx.voice), noTools: knowledge);
}

TurnPlan _small(TurnIntent i, String lang, PlanContext ctx) => TurnPlan(i, lang, hint: _hint('chat', lang, ctx.voice), noTools: true);

/// The app most recently mentioned in [textsNewestFirst] (for "restart it").
String? lastMentionedApp(Iterable<String> textsNewestFirst, List<String> known) {
  for (final t in textsNewestFirst) {
    final a = _findApp(t, known);
    if (a != null) return a;
  }
  return null;
}

/// The real container name for [name] in a docker_list result (exact, then without punctuation, then contained).
String? resolveAppName(List<Map> items, String name) {
  String k(Object? s) => '${s ?? ''}'.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
  final n = k(name);
  if (n.isEmpty) return null;
  for (final x in items) {
    if ('${x['name']}'.toLowerCase() == name.toLowerCase()) return '${x['name']}';
  }
  for (final x in items) {
    if (k(x['name']) == n) return '${x['name']}';
  }
  for (final x in items) {
    if (k(x['name']).contains(n) || k(x['image']).contains(n)) return '${x['name']}';
  }
  return null;
}

String? _findApp(String text, List<String> known) {
  final low = text.toLowerCase();
  for (final a in [...known, ..._commonApps]) {
    final n = a.toLowerCase();
    if (n.length < 3) continue;
    final re = RegExp('(?<![a-z0-9])${RegExp.escape(n)}(?![a-z0-9])');
    if (re.hasMatch(low)) {
      // Prefer the real container name: "llama.cpp" matches the container "llamacpp".
      final real = known.firstWhere((k) => k.toLowerCase() == n || k.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '') == n.replaceAll(RegExp(r'[^a-z0-9]'), ''),
          orElse: () => a);
      return real;
    }
  }
  return null;
}

String? _findAction(String en, String ar) {
  for (final e in _actionEn.entries) {
    if (e.value.hasMatch(en)) {
      // "start" inside "restart" is excluded by \b; "turn on the lights" is handled by cannotDo (no app).
      return e.key;
    }
  }
  for (final e in _actionAr.entries) {
    if (e.value.hasMatch(ar)) return e.key;
  }
  return null;
}

/// The search query from the user's words: "search the web for X" gives "X".
String searchQuery(String text) {
  var q = text.trim();
  q = q.replaceFirst(
      RegExp(r"^(please |can you |could you |nur,? )?(search( the web| online| the internet| google)?( for)?|look up|lookup|google|find (out|info|information)( about| on)?|browse( for)?)\s+", caseSensitive: false),
      '');
  q = q.replaceFirst(RegExp(r'^(من فضلك |ممكن |لو سمحت )?(ابحث|بحث|دوّر|دور|فتش)( لي)?( في الإنترنت| في الانترنت| في النت| على الإنترنت| على النت)?( عن| على)?\s+'), '');
  q = q.replaceAll(RegExp(r'[?؟!.]+$'), '').trim();
  return q.isEmpty ? text.trim() : q;
}


/// The request-only text added to the latest user message when the model answers: tool data for models without tool
/// support, the skill quick card(s), then the answer frame. Kept short (each line costs ~2.5 s of prompt reading on a
/// Pi); '' when nothing applies.
String turnHint(TurnPlan plan, {String skillCard = '', String langCard = '', String data = ''}) {
  final ar = plan.lang == 'ar';
  final parts = <String>[
    if (data.isNotEmpty) ar ? '(بيانات من أدوات الجهاز:\n$data)' : '(Data from the NAS tools:\n$data)',
    if (skillCard.isNotEmpty) '(Guide: $skillCard)',
    if (langCard.isNotEmpty) '(Arabic style: $langCard)',
    if ((plan.hint ?? '').isNotEmpty) plan.hint!,
  ];
  return parts.join('\n');
}

String _hint(String kind, String lang, bool voice) {
  final ar = lang == 'ar';
  switch (kind) {
    case 'web':
      return ar
          ? '(أجب من نتائج البحث أعلاه في جملة إلى ثلاث جمل، واذكر اسم المصدر. لا تخترع أرقاماً أو إصدارات.)'
          : voice
              ? '(Answer from the search results in 1-2 spoken sentences. Say the source name, no links.)'
              : '(Answer from the search results in 1-3 sentences and cite 1-2 sources as markdown links. Do not invent versions or numbers.)';
    case 'troubleshoot':
      return ar
          ? '(ابدأ بالسبب الأرجح من الأرقام أعلاه، ثم خطوتين أو ثلاث خطوات عملية قصيرة.)'
          : '(Start with the most likely cause based on the numbers above, then give 2-3 short practical steps.)';
    case 'knowledge':
      return ar ? '(أجب بإيجاز ووضوح.)' : '(Answer briefly and clearly.)';
    default:
      return '';
  }
}

