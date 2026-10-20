import 'dart:math' as math;

/// SPE-1: explainable ensemble. Competition-specific recent goals are primary;
/// shot metrics and market favourites are bounded secondary evidence.
class SuperPredictionEngine {
  List<Map<String, dynamic>> predict({
    required List<Map<String, dynamic>> fixtures,
    required List<Map<String, dynamic>> history,
  }) {
    final finished = history.where((r) =>
      const {'FT', 'FINISHED'}.contains(_s(r['status']).toUpperCase()) &&
      _n(r['scoreHome']) != null && _n(r['scoreAway']) != null).toList()
      ..sort((a, b) => _t(b).compareTo(_t(a)));
    return fixtures.map((f) {
      final league = _league(_s(f['league']));
      final cutoff = _t(f);
      final leagueRows = finished.where((r) =>
        league.isNotEmpty && _league(_s(r['league'])) == league &&
        (cutoff == 0 || _t(r) < cutoff)).take(80).toList();
      final home = _teamRows(leagueRows, _s(f['home']));
      final away = _teamRows(leagueRows, _s(f['away']));
      final homeBase = leagueRows.length >= 8 ? _avg(leagueRows.map((r) => _n(r['scoreHome'])!).toList(), 1.42) : 1.42;
      final awayBase = leagueRows.length >= 8 ? _avg(leagueRows.map((r) => _n(r['scoreAway'])!).toList(), 1.16) : 1.16;
      final hf = _form(home, _s(f['home']));
      final af = _form(away, _s(f['away']));
      var lh = homeBase * _clamp((hf['scored']! + 1.35) / 2.70, .58, 1.62) / _clamp((hf['conceded']! + 1.20) / 2.40, .58, 1.62);
      var la = awayBase * _clamp((af['scored']! + 1.15) / 2.30, .58, 1.62) / _clamp((af['conceded']! + 1.42) / 2.84, .58, 1.62);
      // The live feed may already contain verified recent-form summaries even
      // when the historical results cache has no rows for a team. Use those
      // summaries as a bounded fallback instead of assigning every unknown
      // team the same league-average profile.
      final lines = f['preMatchStats'] is List
          ? (f['preMatchStats'] as List).map((e) => e.toString()).toList()
          : <String>[];
      final homeForm = _feedForm(lines, 'Forma casa:');
      final awayForm = _feedForm(lines, 'Forma ospiti:');
      if (home.isEmpty && homeForm != null) {
        lh *= _clamp((homeForm['scored']! + 0.75) / (homeForm['conceded']! + 0.85), .62, 1.55);
      }
      if (away.isEmpty && awayForm != null) {
        la *= _clamp((awayForm['scored']! + 0.75) / (awayForm['conceded']! + 0.85), .62, 1.55);
      }
      final stats = _map(f['stats']);
      final hs = _n(stats['homeOn']), asot = _n(stats['awayOn']);
      if (hs != null && asot != null && hs >= 0 && asot >= 0 && hs <= 15 && asot <= 15) {
        lh *= _clamp(1 + (hs - asot) * .025, .88, 1.12);
        la *= _clamp(1 + (asot - hs) * .025, .88, 1.12);
      }
      final market = _market(lines);
      if (market.isNotEmpty && _same(market, _s(f['home'])) && !_same(market, _s(f['away']))) lh *= 1.05;
      if (market.isNotEmpty && _same(market, _s(f['away'])) && !_same(market, _s(f['home']))) la *= 1.05;
      lh = _clamp(lh, .2, 3.8); la = _clamp(la, .15, 3.4);
      final matrix = List.generate(8, (h) => List.generate(8, (a) => _pois(lh, h) * _pois(la, a)));
      var p1 = 0.0, px = 0.0, p2 = 0.0;
      var over15 = 0.0, over25 = 0.0, over35 = 0.0, btts = 0.0;
      var best = -1.0;
      var bh = 0, ba = 0;
      for (var h = 0; h < 8; h++) {
        for (var a = 0; a < 8; a++) {
          final p = matrix[h][a];
          if (h > a) p1 += p;
          if (h == a) px += p;
          if (h < a) p2 += p;
          if (h + a >= 2) over15 += p;
          if (h + a >= 3) over25 += p;
          if (h + a >= 4) over35 += p;
          if (h > 0 && a > 0) btts += p;
          if (p > best) { best = p; bh = h; ba = a; }
        }
      }
      final sum = p1 + px + p2;
      p1 /= sum; px /= sum; p2 /= sum;
      final strongest = math.max(p1, math.max(px, p2));
      final pick = strongest == p1 ? '1' : (strongest == p2 ? '2' : 'X');
      final quality = _clamp(24 + math.min(home.length, 8) * 3.2 + math.min(away.length, 8) * 3.2 +
        (hs != null && asot != null ? 10 : 0) + (market.isNotEmpty ? 5 : 0) + (leagueRows.length >= 8 ? 8 : 0), 20, 92).round();
      final scores = <Map<String, dynamic>>[];
      for (var h = 0; h <= 5; h++) {
        for (var a = 0; a <= 5; a++) scores.add({'score': h.toString() + '-' + a.toString(), 'p': matrix[h][a]});
      }
      scores.sort((a,b) => (b['p'] as double).compareTo(a['p'] as double));
      final reasons = <String>[];
      if (home.isNotEmpty) reasons.add(_s(f['home']) + ': ' + home.length.toString() + ' risultati nella stessa competizione');
      if (away.isNotEmpty) reasons.add(_s(f['away']) + ': ' + away.length.toString() + ' risultati nella stessa competizione');
      if (hs != null && asot != null) reasons.add('Tiri in porta storici: ' + hs.toStringAsFixed(1) + '–' + asot.toStringAsFixed(1));
      if (market.isNotEmpty) reasons.add('Segnale mercato: ' + market + ' (peso limitato)');
      if (reasons.isEmpty) reasons.add('Campione insufficiente: stima prudente, affidabilità limitata');
      return <String, dynamic>{...f, 'prediction': <String, dynamic>{
        'home': (p1 * 100).round(), 'draw': (px * 100).round(), 'away': (p2 * 100).round(),
        'xgHome': double.parse(lh.toStringAsFixed(2)), 'xgAway': double.parse(la.toStringAsFixed(2)),
        'score': bh.toString() + '-' + ba.toString(), 'scoreP': (best / sum * 100).round(),
        'ht': (lh * .44).round().toString() + '-' + (la * .44).round().toString(),
        'over15': (over15 / sum * 100).round(),
        'under15': ((sum - over15) / sum * 100).round(),
        'over25': (over25 / sum * 100).round(),
        'under25': ((sum - over25) / sum * 100).round(),
        'over35': (over35 / sum * 100).round(),
        'under35': ((sum - over35) / sum * 100).round(),
        'btts': (btts / sum * 100).round(),
        'noBtts': ((sum - btts) / sum * 100).round(),
        'pick': pick, 'quality': quality, 'samplesHome': home.length, 'samplesAway': away.length,
        'qualityLabel': quality >= 70 ? 'Buona' : (quality >= 45 ? 'Media' : 'Limitata'),
        'scores': scores.take(5).map((e) => {'score': e['score'], 'p': (((e['p'] as double) / sum) * 100).round()}).toList(),
        'reasons': reasons, 'model': 'SPE-1 · Poisson + forma + tiri + mercato',
      }};
    }).toList();
  }

  List<Map<String, dynamic>> _teamRows(List<Map<String, dynamic>> rows, String team) =>
    (rows.where((r) => _same(_s(r['home']), team) || _same(_s(r['away']), team)).toList()
      ..sort((a,b) => _t(b).compareTo(_t(a)))).take(8).toList();

  Map<String, double> _form(List<Map<String, dynamic>> rows, String team) {
    var scored = 0.0, conceded = 0.0, weight = 0.0;
    for (var i = 0; i < rows.length; i++) {
      final r = rows[i], h = _n(r['scoreHome']), a = _n(r['scoreAway']);
      if (h == null || a == null) continue;
      final isHome = _same(_s(r['home']), team), w = math.pow(.84, i).toDouble();
      scored += (isHome ? h : a) * w; conceded += (isHome ? a : h) * w; weight += w;
    }
    return {'scored': (scored + 2.7) / (weight + 2), 'conceded': (conceded + 2.5) / (weight + 2)};
  }
  Map<String, double>? _feedForm(List<String> lines, String prefix) {
    for (final line in lines) {
      if (!line.toLowerCase().startsWith(prefix.toLowerCase())) continue;
      // Expected feed shape: "Forma casa: ... · 2-8 gol · 1/9 pt".
      final match = RegExp(r'([0-9]+(?:\.[0-9]+)?)-([0-9]+(?:\.[0-9]+)?)\s*gol', caseSensitive: false).firstMatch(line);
      final points = RegExp(r'([0-9]+)\s*/\s*([0-9]+)\s*pt', caseSensitive: false).firstMatch(line);
      if (match == null || points == null) return null;
      final scored = double.tryParse(match.group(1)!);
      final conceded = double.tryParse(match.group(2)!);
      final possiblePoints = double.tryParse(points.group(2)!);
      // The feed expresses form as earned/possible points (e.g. 1/9 pt).
      // Three possible points per match means matches played = possiblePoints / 3.
      if (scored == null || conceded == null || possiblePoints == null ||
          possiblePoints <= 0 || possiblePoints > 60 || possiblePoints % 3 != 0) return null;
      final played = possiblePoints / 3;
      return {'scored': scored / played, 'conceded': conceded / played};
    }
    return null;
  }

  double _pois(double l, int k) { var p = math.exp(-l); for (var i = 1; i <= k; i++) p *= l / i; return p; }
  String _market(List<String> lines) {
    for (final line in lines) { final m = RegExp(r'Mercato favorito:\s*(.+)', caseSensitive:false).firstMatch(line); if (m != null) return m.group(1)!.trim(); }
    return '';
  }
  bool _same(String a, String b) => _key(a).isNotEmpty && _key(a) == _key(b);
  String _key(String s) => s.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '');
  String _s(dynamic v) => v?.toString().trim() ?? '';
  double? _n(dynamic v) => v is num ? v.toDouble() : double.tryParse(v?.toString() ?? '');
  int _t(Map<String,dynamic> r) => (_n(r['timestamp']) ?? 0).round();
  double _avg(List<double> v, double fallback) => v.isEmpty ? fallback : v.reduce((a,b) => a+b) / v.length;
  double _clamp(num v, num lo, num hi) => v.clamp(lo, hi).toDouble();
  Map<String,dynamic> _map(dynamic v) => v is Map ? Map<String,dynamic>.from(v) : <String,dynamic>{};
  String _league(String s) {
    final n = s.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), ' ').trim().replaceAll(RegExp(r'\s+'), ' ');
    final c = n.replaceAll(' ', '');
    const aliases = <String,String>{
      'premierleague':'premier league','englishpremierleague':'premier league','epl':'premier league','eng1':'premier league','eng.1':'premier league',
      'championship':'championship','eng2':'championship','eng.2':'championship','leagueone':'league one','eng3':'league one','leaguetwo':'league two','eng4':'league two',
      'seriea':'serie a','ita1':'serie a','ita.1':'serie a','italianseriea':'serie a','serieb':'serie b','ita2':'serie b','ita.2':'serie b',
      'laliga':'la liga','laligasantander':'la liga','esp1':'la liga','esp.1':'la liga','segunda':'segunda','esp2':'segunda','esp.2':'segunda',
      'bundesliga':'bundesliga','ger1':'bundesliga','ger.1':'bundesliga','ligue1':'ligue 1','fra1':'ligue 1','fra.1':'ligue 1','ligue2':'ligue 2','fra2':'ligue 2','fra.2':'ligue 2',
      'eredivisie':'eredivisie','ned1':'eredivisie','ned.1':'eredivisie','turkishsuperlig':'turkish super lig','superlig':'turkish super lig','tur1':'turkish super lig','tur.1':'turkish super lig',
    };
    return aliases[c] ?? n;
  }
}
