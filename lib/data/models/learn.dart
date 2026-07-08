/// Learn content parsed from the snapshot's `learn` key (admin-authored). Units
/// hold lessons hold steps; a step's typed fields are read off its `payload`
/// by kind. A lesson's [fundId] is resolved to the live rate in the UI, so
/// content never carries a stale number.

enum LearnStepKind { explainer, interactive, quiz, image, chart, unknown }

class LearnContent {
  final List<LearnUnit> units;
  const LearnContent(this.units);

  static const empty = LearnContent([]);
  bool get isEmpty => units.isEmpty;

  factory LearnContent.fromJson(Map<String, dynamic> j) => LearnContent(
        ((j['units'] as List?) ?? const [])
            .map((u) => LearnUnit.fromJson((u as Map).cast<String, dynamic>()))
            .toList(),
      );
}

class LearnUnit {
  final String id;
  final String title;
  final String? subtitle;
  final String? accent;
  final String? unlockAfter;
  final List<LearnLesson> lessons;

  const LearnUnit({
    required this.id,
    required this.title,
    this.subtitle,
    this.accent,
    this.unlockAfter,
    this.lessons = const [],
  });

  factory LearnUnit.fromJson(Map<String, dynamic> j) => LearnUnit(
        id: j['id'] as String,
        title: j['title'] as String,
        subtitle: j['subtitle'] as String?,
        accent: j['accent'] as String?,
        unlockAfter: j['unlock_after'] as String?,
        lessons: ((j['lessons'] as List?) ?? const [])
            .map((l) =>
                LearnLesson.fromJson((l as Map).cast<String, dynamic>()))
            .toList(),
      );
}

class LearnLesson {
  final String id;
  final String title;
  final int xp;
  final String? fundId;
  final List<LearnStep> steps;

  const LearnLesson({
    required this.id,
    required this.title,
    this.xp = 20,
    this.fundId,
    this.steps = const [],
  });

  factory LearnLesson.fromJson(Map<String, dynamic> j) => LearnLesson(
        id: j['id'] as String,
        title: j['title'] as String,
        xp: (j['xp'] as num?)?.toInt() ?? 20,
        fundId: j['fund_id'] as String?,
        steps: ((j['steps'] as List?) ?? const [])
            .map((s) => LearnStep.fromJson((s as Map).cast<String, dynamic>()))
            .toList(),
      );
}

class LearnOption {
  final String text;
  final bool correct;
  const LearnOption(this.text, this.correct);

  factory LearnOption.fromJson(Map<String, dynamic> j) =>
      LearnOption((j['text'] as String?) ?? '', j['correct'] == true);
}

class LearnStep {
  final String id;
  final LearnStepKind kind;
  final Map<String, dynamic> payload;

  const LearnStep({required this.id, required this.kind, required this.payload});

  factory LearnStep.fromJson(Map<String, dynamic> j) => LearnStep(
        id: (j['id'] as String?) ?? '',
        kind: switch (j['kind']) {
          'explainer' => LearnStepKind.explainer,
          'interactive' => LearnStepKind.interactive,
          'quiz' => LearnStepKind.quiz,
          'image' => LearnStepKind.image,
          'chart' => LearnStepKind.chart,
          _ => LearnStepKind.unknown,
        },
        payload: ((j['payload'] as Map?) ?? const {}).cast<String, dynamic>(),
      );

  // Shared
  String? get title => payload['title'] as String?;
  String? get body => payload['body'] as String?;
  String? get note => payload['note'] as String?;

  // interactive
  String? get widget => payload['widget'] as String?;
  double? get rate => (payload['rate'] as num?)?.toDouble();
  double? get min => (payload['min'] as num?)?.toDouble();
  double? get max => (payload['max'] as num?)?.toDouble();
  double? get initial => (payload['initial'] as num?)?.toDouble();

  // quiz
  String? get prompt => payload['prompt'] as String?;
  String? get explainOk => payload['explain_ok'] as String?;
  String? get explainNo => payload['explain_no'] as String?;
  List<LearnOption> get options => ((payload['options'] as List?) ?? const [])
      .map((o) => LearnOption.fromJson((o as Map).cast<String, dynamic>()))
      .toList();
}
