import 'dart:convert';
import 'dart:math' as math;
import 'package:shared_preferences/shared_preferences.dart';

/// Local scoreline learner. Predictions are generated from historical goal
/// records, graded against published results, and recalibrated after each match.
class ScorePredictionEngine {
  static const String _storageKey = 'match_ai_pro_score_memory_v1';
  bool _loaded = false;
  final List<Map<String, dynamic>> _records = <Map<String, dynamic>>[];
  final Map<String, double> _teamGoalBias = <String, double>{};
  double _halfTimeFraction = 0.45;

  List<Map<String, dynamic>> get records =>
      _records.map((item) => Map<String, dynamic>.from(item)).toList();
  double get halfTimeFraction => _halfTimeFraction;
  int get trainedTeams => _teamGoalBias.length;

  Future<void> _load() async {
    if (_loaded) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_storageKey);
      if (raw != null && raw.isNotEmpty) {
        final decoded = jsonDecode(raw);
        if (decoded is Map) {
          final savedRecords = decoded['records'];
          if (savedRecords is List) {
            _records
              ..clear()
              ..addAll(savedRecords.whereType<Map>()
                  .map((item) => Map<String, dynamic>.from(item)));
          }
          final bias = decoded['teamGoalBias'];
          if (bias is Map) {
            _teamGoalBias
              ..clear()
              ..addEntries(bias.entries.map((entry) => MapEntry(
                    entry.key.toString(), _double(entry.value) ?? 0.0)));
          }
          _halfTimeFraction =
              (_double(decoded['halfTimeFraction']) ?? 0.45).clamp(0.30, 0.60).toDouble();
        }
      }
    } catch (_) {
      // Local persistence is optional: the dashboard must still run without it.
    }
    _loaded = true;
  }

  Future<void> _save() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_storageKey, jsonEncode(<String, dynamic>{
        'version': 1,
        'updatedAt': DateTime.now().toIso8601String(),
        'records': _records,
        'teamGoalBias': _teamGoalBias,
        'halfTimeFraction': _halfTimeFraction,
      }));
    } catch (_) {
      // Do not stop the app if device storage is temporarily unavailable.
    }
  }

  Future<void> update({
    required List<Map<String, dynamic>> fixtures,
    required List<Map<String, dynamic>> historicalResults,
  }) async {
    await _load();
    var changed = false;
    final results = <Map<String, dynamic>>[];
    results.addAll(historicalResults.map((item) => Map<String, dynamic>.from(item)));
    for (final fixture in fixtures) {
      final status = (fixture['status'] ?? '').toString().toUpperCase();
      if ((status == 'FT' || status == 'FINISHED') &&
          _integer(fixture['scoreHome']) != null &&
          _integer(fixture['scoreAway']) != null) {
        results.add(fixture);
      }
    }

    // Grade recorded forecasts against results. A full-time result is learned
    // once; a half-time result can be graded later if its source arrives later.
    for (final forecast in _records) {
      final result = _findResult(forecast, results);
      if (result != null && _grade(forecast, result)) changed = true;
    }

    // Refresh pre-kick-off forecasts when form evidence or learned calibration
    // changes. Once a match starts, preserve the last pre-match call.
    for (final fixture in fixtures) {
      if ((fixture['status'] ?? '').toString().toUpperCase() != 'NS') continue;
      final prediction = _makePrediction(fixture);
      if (prediction == null) continue;
      final key = _fixtureKey(fixture);
      final existingIndex = _records.indexWhere((item) => item['key'] == key);
      if (existingIndex < 0) {
        prediction
          ..['key'] = key
          ..['status'] = 'NS'
          ..['createdAt'] = DateTime.now().toIso8601String()
          ..['revisions'] = <Map<String, dynamic>>[]
          ..['gradedFT'] = false
          ..['gradedHT'] = false
          ..['learnedFT'] = false
          ..['learnedHT'] = false;
        _records.add(prediction);
        changed = true;
        continue;
      }
      final existing = _records[existingIndex];
      if (existing['gradedFT'] == true || existing['status'] != 'NS') continue;
      if (existing['signature'] == prediction['signature']) continue;

      final revisions = (existing['revisions'] as List? ?? const <dynamic>[])
          .whereType<Map>()
          .map((item) => Map<String, dynamic>.from(item))
          .toList();
      revisions.add(<String, dynamic>{
        'updatedAt': existing['updatedAt'],
        'htHome': existing['predHTHome'],
        'htAway': existing['predHTAway'],
        'ftHome': existing['predFTHome'],
        'ftAway': existing['predFTAway'],
      });
      if (revisions.length > 8) revisions.removeRange(0, revisions.length - 8);
      prediction
        ..['key'] = key
        ..['status'] = 'NS'
        ..['createdAt'] = existing['createdAt']
        ..['revisions'] = revisions
        ..['gradedFT'] = existing['gradedFT'] == true
        ..['gradedHT'] = existing['gradedHT'] == true
        ..['learnedFT'] = existing['learnedFT'] == true
        ..['learnedHT'] = existing['learnedHT'] == true;
      _records[existingIndex] = prediction;
      changed = true;
    }

    _records.sort((a, b) =>
        (_integer(b['timestamp']) ?? 0).compareTo(_integer(a['timestamp']) ?? 0));
    if (_records.length > 500) {
      _records.removeRange(500, _records.length);
      changed = true;
    }
    if (changed) await _save();
  }

  Map<String, dynamic>? _makePrediction(Map<String, dynamic> fixture) {
    final pre = (fixture['preMatchStats'] as List? ?? const <dynamic>[])
        .map((value) => value.toString()).toList();
    final homeForm = _parseForm(pre, 'casa');
    final awayForm = _parseForm(pre, 'ospiti');
    if (homeForm == null || awayForm == null) return null;
    final homeGames = homeForm['games'] as int;
    final awayGames = awayForm['games'] as int;
    if (homeGames < 2 || awayGames < 2) return null;

    final homeAttack = (homeForm['gf'] as int) / homeGames;
    final homeConceded = (homeForm['ga'] as int) / homeGames;
    final awayAttack = (awayForm['gf'] as int) / awayGames;
    final awayConceded = (awayForm['ga'] as int) / awayGames;
    final baseHome = ((homeAttack * 0.58) + (awayConceded * 0.42)) * 1.06;
    final baseAway = ((awayAttack * 0.58) + (homeConceded * 0.42)) * 0.94;
    final homeKey = _teamKey((fixture['home'] ?? '').toString());
    final awayKey = _teamKey((fixture['away'] ?? '').toString());
    final homeLambda =
        (baseHome + (_teamGoalBias[homeKey] ?? 0.0)).clamp(0.10, 4.0).toDouble();
    final awayLambda =
        (baseAway + (_teamGoalBias[awayKey] ?? 0.0)).clamp(0.10, 4.0).toDouble();
    final half = _bestExactScore(homeLambda * _halfTimeFraction,
        awayLambda * _halfTimeFraction);
    final full = _bestExactScore(homeLambda, awayLambda);
    final oneXtwo = _oneXtwo(homeLambda, awayLambda);

    final relevantForm = pre.where((line) =>
        line.toLowerCase().startsWith('forma casa:') ||
        line.toLowerCase().startsWith('forma ospiti:')).toList();
    final signature = jsonEncode(<dynamic>[
      relevantForm, _teamGoalBias[homeKey] ?? 0.0,
      _teamGoalBias[awayKey] ?? 0.0, _halfTimeFraction]);

    return <String, dynamic>{
      'id': _integer(fixture['id']),
      'home': (fixture['home'] ?? 'Casa').toString(),
      'away': (fixture['away'] ?? 'Ospite').toString(),
      'league': (fixture['league'] ?? 'Calcio').toString(),
      'time': (fixture['time'] ?? '--:--').toString(),
      'date': _fixtureDate(fixture),
      'timestamp': _integer(fixture['timestamp']) ?? 0,
      'predHTHome': half['home'],
      'predHTAway': half['away'],
      'probHTExact': half['probability'],
      'predFTHome': full['home'],
      'predFTAway': full['away'],
      'probFTExact': full['probability'],
      'probHome': oneXtwo['home'],
      'probDraw': oneXtwo['draw'],
      'probAway': oneXtwo['away'],
      'lambdaHome': homeLambda,
      'lambdaAway': awayLambda,
      'htFraction': _halfTimeFraction,
      'evidence': <String, dynamic>{
        'homeGames': homeGames, 'awayGames': awayGames,
        'homeGF': homeForm['gf'], 'homeGA': homeForm['ga'],
        'awayGF': awayForm['gf'], 'awayGA': awayForm['ga'],
      },
      'basis':
          'Gol fatti/subiti nelle ultime gare, forza offensiva e difensiva avversaria, lieve vantaggio casa e calibrazione dagli esiti precedenti.',
      'signature': signature,
      'updatedAt': DateTime.now().toIso8601String(),
    };
  }

  Map<String, dynamic>? _parseForm(List<String> lines, String side) {
    final label = side == 'casa' ? 'Forma casa:' : 'Forma ospiti:';
    for (final line in lines) {
      if (!line.toLowerCase().startsWith(label.toLowerCase())) continue;
      final match = RegExp(
        r'Forma\s+(?:casa|ospiti):\s*(\d+)\s*V\s+(\d+)\s*N\s+(\d+)\s*P\s*[·•]\s*(\d+)\s*-\s*(\d+)\s*gol',
        caseSensitive: false,
      ).firstMatch(line);
      if (match == null) return null;
      final wins = int.tryParse(match.group(1) ?? '') ?? 0;
      final draws = int.tryParse(match.group(2) ?? '') ?? 0;
      final losses = int.tryParse(match.group(3) ?? '') ?? 0;
      return <String, dynamic>{
        'games': wins + draws + losses,
        'gf': int.tryParse(match.group(4) ?? '') ?? 0,
        'ga': int.tryParse(match.group(5) ?? '') ?? 0,
      };
    }
    return null;
  }

  Map<String, dynamic> _bestExactScore(double homeLambda, double awayLambda) {
    final homeP = _poisson(homeLambda, 7);
    final awayP = _poisson(awayLambda, 7);
    var bestHome = 0;
    var bestAway = 0;
    var bestProbability = 0.0;
    for (var h = 0; h < homeP.length; h++) {
      for (var a = 0; a < awayP.length; a++) {
        final probability = homeP[h] * awayP[a];
        if (probability > bestProbability) {
          bestProbability = probability;
          bestHome = h;
          bestAway = a;
        }
      }
    }
    return <String, dynamic>{
      'home': bestHome, 'away': bestAway,
      'probability': bestProbability * 100.0,
    };
  }

  List<double> _poisson(double lambda, int maxGoals) {
    final values = <double>[math.exp(-lambda)];
    for (var goals = 1; goals <= maxGoals; goals++) {
      values.add(values[goals - 1] * lambda / goals);
    }
    return values;
  }

  Map<String, double> _oneXtwo(double homeLambda, double awayLambda) {
    final homeP = _poisson(homeLambda, 8);
    final awayP = _poisson(awayLambda, 8);
    var home = 0.0, draw = 0.0, away = 0.0;
    for (var h = 0; h < homeP.length; h++) {
      for (var a = 0; a < awayP.length; a++) {
        final p = homeP[h] * awayP[a];
        if (h > a) {
          home += p;
        } else if (h == a) {
          draw += p;
        } else {
          away += p;
        }
      }
    }
    final total = home + draw + away;
    if (total <= 0) return <String, double>{'home': 0, 'draw': 0, 'away': 0};
    return <String, double>{
      'home': home / total * 100,
      'draw': draw / total * 100,
      'away': away / total * 100,
    };
  }

  Map<String, dynamic>? _findResult(
      Map<String, dynamic> forecast, List<Map<String, dynamic>> results) {
    Map<String, dynamic>? best;
    var bestScore = 0;
    final forecastId = _integer(forecast['id']);
    final forecastTs = _integer(forecast['timestamp']) ?? 0;
    for (final result in results) {
      if (_integer(result['scoreHome']) == null ||
          _integer(result['scoreAway']) == null) continue;
      final status = (result['status'] ?? '').toString().toUpperCase();
      if (status != 'FT' && status != 'FINISHED' &&
          status != 'AFTER EXTRA TIME' && result['finished'] != true) continue;
      final resultId = _integer(result['id']);
      final idsMatch = forecastId != null && forecastId > 0 &&
          resultId != null && resultId == forecastId;
      final homeMatch = _similarTeamNames(
          (forecast['home'] ?? '').toString(), (result['home'] ?? '').toString());
      final awayMatch = _similarTeamNames(
          (forecast['away'] ?? '').toString(), (result['away'] ?? '').toString());
      final resultTs = _integer(result['timestamp']) ?? 0;
      final delta = forecastTs > 0 && resultTs > 0
          ? (forecastTs - resultTs).abs() : 0;
      final sameDate = delta == 0 || delta <= const Duration(hours: 36).inSeconds;
      if (!idsMatch && !(homeMatch && awayMatch && sameDate)) continue;
      var score = idsMatch ? 100 : 50;
      if (homeMatch && awayMatch) score += 10;
      if (sameDate) score += 5;
      if (_integer(result['scoreHTHome']) != null &&
          _integer(result['scoreHTAway']) != null) score += 3;
      if (score > bestScore) {
        best = result;
        bestScore = score;
      }
    }
    return best;
  }

  bool _grade(Map<String, dynamic> forecast, Map<String, dynamic> result) {
    var changed = false;
    final actualHome = _integer(result['scoreHome']);
    final actualAway = _integer(result['scoreAway']);
    if (actualHome == null || actualAway == null) return false;

    if (forecast['gradedFT'] != true) {
      forecast['actualHome'] = actualHome;
      forecast['actualAway'] = actualAway;
      forecast['ftExact'] = _integer(forecast['predFTHome']) == actualHome &&
          _integer(forecast['predFTAway']) == actualAway;
      forecast['ft1x2Correct'] =
          _outcome(_integer(forecast['predFTHome']), _integer(forecast['predFTAway'])) ==
              _outcome(actualHome, actualAway);
      forecast['gradedFT'] = true;
      forecast['status'] = 'FT';
      forecast['gradedAt'] = DateTime.now().toIso8601String();

      if (forecast['learnedFT'] != true) {
        final homeKey = _teamKey((forecast['home'] ?? '').toString());
        final awayKey = _teamKey((forecast['away'] ?? '').toString());
        final homeLambda = _double(forecast['lambdaHome']);
        final awayLambda = _double(forecast['lambdaAway']);
        if (homeLambda != null && homeKey.isNotEmpty) {
          final residual = actualHome - homeLambda;
          _teamGoalBias[homeKey] =
              ((_teamGoalBias[homeKey] ?? 0.0) * 0.75 + residual * 0.25)
                  .clamp(-0.80, 0.80).toDouble();
        }
        if (awayLambda != null && awayKey.isNotEmpty) {
          final residual = actualAway - awayLambda;
          _teamGoalBias[awayKey] =
              ((_teamGoalBias[awayKey] ?? 0.0) * 0.75 + residual * 0.25)
                  .clamp(-0.80, 0.80).toDouble();
        }
        forecast['learnedFT'] = true;
        forecast['learningNote'] = forecast['ftExact'] == true
            ? 'Risultato esatto centrato: previsione verificata.'
            : 'Errore registrato: previsto ' +
                (forecast['predFTHome'] ?? '?').toString() + '-' +
                (forecast['predFTAway'] ?? '?').toString() +
                ', risultato reale $actualHome-$actualAway. Scostamento usato per ricalibrare il modello.';
      }
      changed = true;
    }

    final htHome = _integer(result['scoreHTHome']);
    final htAway = _integer(result['scoreHTAway']);
    if (htHome != null && htAway != null && forecast['gradedHT'] != true) {
      forecast['actualHTHome'] = htHome;
      forecast['actualHTAway'] = htAway;
      forecast['htExact'] = _integer(forecast['predHTHome']) == htHome &&
          _integer(forecast['predHTAway']) == htAway;
      forecast['gradedHT'] = true;
      if (forecast['learnedHT'] != true) {
        final finalTotal = actualHome + actualAway;
        final halfTotal = htHome + htAway;
        if (finalTotal > 0) {
          final observed = (halfTotal / finalTotal).clamp(0.25, 0.65).toDouble();
          _halfTimeFraction =
              (_halfTimeFraction * 0.80 + observed * 0.20)
                  .clamp(0.30, 0.60).toDouble();
        }
        forecast['learnedHT'] = true;
      }
      changed = true;
    }
    return changed;
  }

  String _outcome(int? home, int? away) {
    if (home == null || away == null) return '?';
    if (home > away) return '1';
    if (home < away) return '2';
    return 'X';
  }

  String _fixtureKey(Map<String, dynamic> fixture) =>
      _fixtureDate(fixture) + '|' +
      _teamKey((fixture['home'] ?? '').toString()) + '|' +
      _teamKey((fixture['away'] ?? '').toString());

  String _fixtureDate(Map<String, dynamic> fixture) {
    final timestamp = _integer(fixture['timestamp']);
    if (timestamp != null && timestamp > 0) {
      return DateTime.fromMillisecondsSinceEpoch(timestamp * 1000)
          .toLocal().toIso8601String().substring(0, 10);
    }
    final time = (fixture['time'] ?? '').toString();
    return RegExp(r'(\d{4}-\d{2}-\d{2})').firstMatch(time)?.group(1) ??
        DateTime.now().toIso8601String().substring(0, 10);
  }

  String _teamKey(String input) {
    final value = input.toLowerCase().replaceAll(
        RegExp(r'\b(football club|soccer club|fc|afc|cf|sc|club|the)\b'), ' ');
    return value.replaceAll(RegExp(r'[^a-z0-9]'), '');
  }

  bool _similarTeamNames(String a, String b) {
    final left = _teamKey(a), right = _teamKey(b);
    if (left.isEmpty || right.isEmpty) return false;
    if (left == right) return true;
    if (left.length >= 5 && right.length >= 5 &&
        (left.contains(right) || right.contains(left))) return true;
    final lTokens = a.toLowerCase().split(RegExp(r'[^a-z0-9]+'))
        .where((token) => token.length > 2 &&
            !{'football', 'club', 'the'}.contains(token)).toSet();
    final rTokens = b.toLowerCase().split(RegExp(r'[^a-z0-9]+'))
        .where((token) => token.length > 2 &&
            !{'football', 'club', 'the'}.contains(token)).toSet();
    if (lTokens.isEmpty || rTokens.isEmpty) return false;
    return lTokens.intersection(rTokens).length /
            lTokens.union(rTokens).length >= 0.67;
  }

  int? _integer(dynamic value) {
    if (value is num) return value.round();
    return int.tryParse(value?.toString() ?? '');
  }

  double? _double(dynamic value) {
    if (value is num) return value.toDouble();
    return double.tryParse((value ?? '').toString().replaceAll(',', '.'));
  }
}