/// Données de la collecte, telles que gardées sur le téléphone et envoyées au serveur.
library;

String? _s(Object? v) => (v is String && v.trim().isNotEmpty) ? v : null;

/// Une ligne de semence reçue par un producteur.
class Seed {
  const Seed({required this.id, required this.variety, required this.quantityKg, this.receivedOn});

  final String id;
  final String variety;
  final double quantityKg;

  /// `AAAA-MM-JJ`.
  final String? receivedOn;

  Map<String, dynamic> toJson() => {'id': id, 'variety': variety, 'quantity_kg': quantityKg, 'received_on': receivedOn};

  factory Seed.fromJson(Map<String, dynamic> j) => Seed(
    id: j['id'] as String,
    variety: j['variety'] as String,
    quantityKg: (j['quantity_kg'] as num).toDouble(),
    receivedOn: _s(j['received_on']),
  );
}

class Producer {
  const Producer({
    required this.id,
    required this.lastName,
    required this.firstName,
    this.phone,
    this.memberCard,
    this.sex,
    this.village,
    this.photoId,
    this.consentAt,
    this.source = 'app',
    this.seeds = const [],
  });

  final String id;
  final String lastName;
  final String firstName;
  final String? phone;
  final String? memberCard;

  /// `F` ou `H`.
  final String? sex;
  final String? village;
  final String? photoId;

  /// Date du consentement ; absente pour un producteur importé qui n'a pas encore été vu.
  final DateTime? consentAt;

  /// `app` ou `import`.
  final String source;
  final List<Seed> seeds;

  String get fullName => '$firstName ${lastName.toUpperCase()}';

  Producer copyWith({
    String? lastName,
    String? firstName,
    String? phone,
    String? memberCard,
    String? sex,
    String? village,
    String? photoId,
    DateTime? consentAt,
    List<Seed>? seeds,
  }) => Producer(
    id: id,
    lastName: lastName ?? this.lastName,
    firstName: firstName ?? this.firstName,
    phone: phone ?? this.phone,
    memberCard: memberCard ?? this.memberCard,
    sex: sex ?? this.sex,
    village: village ?? this.village,
    photoId: photoId ?? this.photoId,
    consentAt: consentAt ?? this.consentAt,
    source: source,
    seeds: seeds ?? this.seeds,
  );

  /// Corps de `PUT /api/app/producers/<id>`.
  Map<String, dynamic> toPayload({List<String> deletedSeedIds = const []}) => {
    'last_name': lastName,
    'first_name': firstName,
    'phone': phone,
    'member_card': memberCard,
    'sex': sex,
    'village': village,
    'photo_id': photoId,
    'consent_at': consentAt?.toUtc().toIso8601String(),
    'seeds': [for (final s in seeds) s.toJson()],
    'deleted_seed_ids': deletedSeedIds,
  };

  Map<String, dynamic> toJson() => {'id': id, ...toPayload(), 'source': source}..remove('deleted_seed_ids');

  factory Producer.fromJson(Map<String, dynamic> j, {List<Seed>? seeds}) => Producer(
    id: j['id'] as String,
    lastName: j['last_name'] as String,
    firstName: j['first_name'] as String,
    phone: _s(j['phone']),
    memberCard: _s(j['member_card']),
    sex: _s(j['sex']),
    village: _s(j['village']),
    photoId: _s(j['photo_id']),
    consentAt: DateTime.tryParse(j['consent_at'] as String? ?? ''),
    source: j['source'] as String? ?? 'app',
    seeds: seeds ?? [for (final s in (j['seeds'] as List?) ?? const []) Seed.fromJson(Map<String, dynamic>.from(s as Map))],
  );

  /// Vrai si le texte de recherche correspond (nom, prénom, téléphone, carte, village), sans accents ni casse.
  bool matches(String query) {
    final q = fold(query.trim());
    if (q.isEmpty) return true;
    final hay = fold('$firstName $lastName ${phone ?? ''} ${memberCard ?? ''} ${village ?? ''}');
    return q.split(RegExp(r'\s+')).every(hay.contains);
  }
}

/// Minuscules sans accents, pour la recherche.
String fold(String s) {
  const from = 'àâäáãçéèêëíìîïñóòôöõúùûüýÿ';
  const to = 'aaaaaceeeeiiiinooooouuuuyy';
  final b = StringBuffer();
  for (final c in s.toLowerCase().split('')) {
    final i = from.indexOf(c);
    b.write(i >= 0 ? to[i] : c);
  }
  return b.toString();
}

/// Listes fermées reçues du serveur.
class Lists {
  const Lists({this.villages = const [], this.varieties = const [], this.irrigation = const [], this.waterSources = const []});

  final List<String> villages;
  final List<String> varieties;
  final List<String> irrigation;
  final List<String> waterSources;

  Map<String, dynamic> toJson() => {'villages': villages, 'varieties': varieties, 'irrigation': irrigation, 'water_sources': waterSources};

  factory Lists.fromJson(Map<String, dynamic>? j) {
    List<String> l(String k) => [for (final x in (j?[k] as List?) ?? const []) x as String];
    return Lists(villages: l('villages'), varieties: l('varieties'), irrigation: l('irrigation'), waterSources: l('water_sources'));
  }
}

/// Le compte connecté.
class Account {
  const Account({required this.id, required this.name, required this.phone, required this.role});

  final String id;
  final String name;
  final String phone;
  final String role;

  Map<String, dynamic> toJson() => {'id': id, 'name': name, 'phone': phone, 'role': role};

  factory Account.fromJson(Map<String, dynamic> j) =>
      Account(id: j['id'] as String, name: j['name'] as String, phone: j['phone'] as String, role: j['role'] as String);
}
