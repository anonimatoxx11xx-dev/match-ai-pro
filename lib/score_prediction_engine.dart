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

    // Mark saved forecasts as live as soon as the feed reports kick-off.
    // Their displayed score stays frozen at the last pre-match update.
    for (final fixture in fixtures) {
      if ((fixture['status'] ?? '').toString().toUpperCase() != 'LIVE') continue;
      final key = _fixtureKey(fixture);
      final index = _records.indexWhere((item) => item['key'] == key);
      if (index >= 0 && _records[index]['gradedFT'] != true &&
          _records[index]['status'] != 'LIVE') {
        _records[index]['status'] = 'LIVE';
        changed = true;
      }
    }

    // Refresh pre-kick-off forecasts when form evidence or learned calibration
    // changes. Once a match starts, preserve the last pre-match call.
    for (final fixture in fixtures) {
      if ((fixture['status'] ?? '').toString().toUpperCase() != 'NS') continue;
      final prediction = _makePrediction(fixture, results);
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

  Map<String, dynamic>? _makePrediction(
      Map<String, dynamic> fixture, List<Map<String, dynamic>> historicalResults) {
    final pre = (fixture['preMatchStats'] as List? ?? const <dynamic>[])
        .map((value) => value.toString()).toList();
    final kickOff = _integer(fixture['timestamp']) ?? 0;
    final homeName = (fixture['home'] ?? '').toString();
    final awayName = (fixture['away'] ?? '').toString();
    final leagueName = (fixture['league'] ?? '').toString();
    final homeHistory = _recentTeamForm(homeName, leagueName, kickOff, historicalResults);
    final awayHistory = _recentTeamForm(awayName, leagueName, kickOff, historicalResults);
    final parsedHome = _parseForm(pre, 'casa');
    final parsedAway = _parseForm(pre, 'ospiti');
    // Prefer a larger verified score history when available. A three-match
    // feed summary is useful as fallback, but must not hide four-to-six actual
    // results that provide a better estimate of scoring strength.
    final homeHistoryGames = _integer(homeHistory?['games']) ?? 0;
    final awayHistoryGames = _integer(awayHistory?['games']) ?? 0;
    final homeForm = homeHistory != null && homeHistoryGames >= 4
        ? homeHistory
        : (parsedHome != null && (parsedHome['games'] as int) >= 3
            ? parsedHome : (homeHistory ?? parsedHome));
    final awayForm = awayHistory != null && awayHistoryGames >= 4
        ? awayHistory
        : (parsedAway != null && (parsedAway['games'] as int) >= 3
            ? parsedAway : (awayHistory ?? parsedAway));
    if (homeForm == null || awayForm == null) return null;
    final homeGames = homeForm['games'] as int;
    final awayGames = awayForm['games'] as int;
    if (homeGames < 2 || awayGames < 2) return null;

    final rawHomeAttack = _formAverage(homeForm, 'gf');
    final rawHomeConceded = _formAverage(homeForm, 'ga');
    final rawAwayAttack = _formAverage(awayForm, 'gf');
    final rawAwayConceded = _formAverage(awayForm, 'ga');
    if (rawHomeAttack == null || rawHomeConceded == null ||
        rawAwayAttack == null || rawAwayConceded == null) return null;

    // Empirical-Bayes shrinkage: a 2–3 match sample is noisy and must not
    // dominate the forecast. Five neutral pseudo-matches pull small samples
    // toward broad scoring priors; the observed form gains influence as n grows.
    // These are conservative priors, not claimed league-specific statistics.
    final homeAttack = _shrinkRate(rawHomeAttack, homeGames, 1.42);
    final homeConceded = _shrinkRate(rawHomeConceded, homeGames, 1.28);
    final awayAttack = _shrinkRate(rawAwayAttack, awayGames, 1.18);
    final awayConceded = _shrinkRate(rawAwayConceded, awayGames, 1.42);

    var baseHome = ((homeAttack * 0.58) + (awayConceded * 0.42)) * 1.06;
    var baseAway = ((awayAttack * 0.58) + (homeConceded * 0.42)) * 0.94;
    final h2h = _recentHeadToHead(homeName, awayName, leagueName, kickOff, historicalResults);
    if ((h2h['games'] as int) >= 3) {
      final h2hHome = h2h['homeGF'] as double;
      final h2hAway = h2h['awayGF'] as double;
      baseHome = baseHome * 0.88 + h2hHome * 0.12;
      baseAway = baseAway * 0.88 + h2hAway * 0.12;
    }

    // The published feed may include the bookmaker's total-goals line. It is
    // not a match result or a guarantee, but it is a useful independent prior
    // when it is present. Blend gently with the historical goal model instead
    // of letting a small three-game sample dominate every score prediction.
    final marketTotal = _marketExpectedTotal(pre);
    if (marketTotal != null) {
      final currentTotal = baseHome + baseAway;
      if (currentTotal > 0) {
        final blendedTotal = currentTotal * 0.75 + marketTotal * 0.25;
        final scale = (blendedTotal / currentTotal).clamp(0.82, 1.22).toDouble();
        baseHome *= scale;
        baseAway *= scale;
      }
    }

    final homeKey = _teamKey(homeName);
    final awayKey = _teamKey(awayName);
    var homeLambda =
        (baseHome + (_teamGoalBias[homeKey] ?? 0.0)).clamp(0.10, 4.0).toDouble();
    var awayLambda =
        (baseAway + (_teamGoalBias[awayKey] ?? 0.0)).clamp(0.10, 4.0).toDouble();

    // Use pre-match shot data only when the feed provides both teams' values.
    // Historical shots on target are a small, capped signal; they must not
    // overpower verified goals or manufacture a prediction from missing data.
    final rawStats = fixture['stats'];
    final stats = rawStats is Map
        ? Map<String, dynamic>.from(rawStats)
        : <String, dynamic>{};
    final homeOnTarget = _double(stats['homeOn']);
    final awayOnTarget = _double(stats['awayOn']);
    if (homeOnTarget != null && awayOnTarget != null &&
        homeOnTarget >= 0 && awayOnTarget >= 0 &&
        homeOnTarget <= 20 && awayOnTarget <= 20) {
      final homeShotFactor =
          (1.0 + (homeOnTarget - 3.5) * 0.025).clamp(0.90, 1.10).toDouble();
      final awayShotFactor =
          (1.0 + (awayOnTarget - 3.5) * 0.025).clamp(0.90, 1.10).toDouble();
      homeLambda = (homeLambda * homeShotFactor).clamp(0.10, 4.0).toDouble();
      awayLambda = (awayLambda * awayShotFactor).clamp(0.10, 4.0).toDouble();
    }

    // If ESPN provides an identifiable favourite and its actual moneyline,
    // gently reconcile the goal model with that independent market signal.
    // Never infer the favourite from a bare, side-less odds number.
    final marketSignal = _marketFavoriteSignal(
      pre, homeName, awayName,
      (fixture['proposals'] as List? ?? const <dynamic>[]),
    );
    if (marketSignal != null) {
      final initial = _oneXtwo(homeLambda, awayLambda);
      final side = marketSignal['side'] as String;
      final currentProbability = (initial[side] ?? 0.0) / 100.0;
      final impliedProbability = marketSignal['implied'] as double;
      final targetProbability = (currentProbability +
              ((impliedProbability - currentProbability) * 0.35)
                  .clamp(-0.15, 0.15))
          .clamp(0.05, 0.90)
          .toDouble();
      final totalGoals = homeLambda + awayLambda;
      var bestDistance = double.infinity;
      var bestHome = homeLambda;
      var bestAway = awayLambda;
      // Preserve the total-goals estimate while shifting expected goals toward
      // the favourite. This keeps 1X2, exact scores and goal markets coherent.
      for (var homeShare = 0.05; homeShare <= 0.9501; homeShare += 0.005) {
        final candidateHome = totalGoals * homeShare;
        final candidateAway = totalGoals - candidateHome;
        final probabilities = _oneXtwo(candidateHome, candidateAway);
        final distance = (((probabilities[side] ?? 0.0) / 100.0) - targetProbability).abs();
        if (distance < bestDistance) {
          bestDistance = distance;
          bestHome = candidateHome;
          bestAway = candidateAway;
        }
      }
      homeLambda = bestHome.clamp(0.10, 4.0).toDouble();
      awayLambda = bestAway.clamp(0.10, 4.0).toDouble();
    }

    // One normalized joint score distribution powers every displayed market.
    // Dixon-Coles low-score correction handles the common 0-0/1-0/0-1/1-1
    // dependence that independent Poisson misses. It is conservative and does
    // not claim to know a league-specific rho without enough verified data.
    final half = _bestExactScore(homeLambda * _halfTimeFraction,
        awayLambda * _halfTimeFraction);
    final full = _bestExactScore(homeLambda, awayLambda);
    final scoreMatrix = _scoreMatrix(homeLambda, awayLambda, 8);
    final oneXtwo = _oneXtwo(homeLambda, awayLambda);
    var over15 = 0.0, over25 = 0.0, under35 = 0.0, bothScore = 0.0;
    for (final row in scoreMatrix) {
      final h = row['home'] as int;
      final a = row['away'] as int;
      final probability = row['probability'] as double;
      if (h + a >= 2) over15 += probability;
      if (h + a >= 3) over25 += probability;
      if (h + a <= 3) under35 += probability;
      if (h > 0 && a > 0) bothScore += probability;
    }
    final alternatives = _topScores(homeLambda, awayLambda, 4);
    final sampleMin = math.min(homeGames, awayGames);
    final h2hGames = h2h['games'] as int;
    final dataQuality = sampleMin >= 7 && h2hGames >= 2
        ? 'Buona' : (sampleMin >= 5 ? 'Media' : 'Limitata');
    final sampleReliability = (sampleMin / (sampleMin + 5.0)).clamp(0.0, 1.0);

    final relevantForm = pre.where((line) =>
        line.toLowerCase().startsWith('forma casa:') ||
        line.toLowerCase().startsWith('forma ospiti:')).toList();
    final signature = jsonEncode(<dynamic>[
      // Bump model version so forecasts saved under the unshrunk model
      // are recalculated on the next app update.
      'score-model-v12-league-specific-h2h',
      relevantForm,
      homeForm['gfAvg'], homeForm['gaAvg'], homeGames,
      awayForm['gfAvg'], awayForm['gaAvg'], awayGames,
      h2h['games'], h2h['homeGF'], h2h['awayGF'],
      _marketExpectedTotal(pre),
      _double(stats['homeOn']),
      _double(stats['awayOn']),
      _double(stats['homeShots']),
      _double(stats['awayShots']),
      (fixture['proposals'] as List? ?? const <dynamic>[])
          .map((item) => item.toString()).toList(),
      // Include all sourced market signals; otherwise stored predictions
      // can remain frozen even after a new model starts using those signals.
      pre.where((line) => line.toLowerCase().startsWith('moneyline:') ||
          line.toLowerCase().startsWith('moneyline favorito:') ||
          line.toLowerCase().startsWith('mercato favorito:') ||
          line.toLowerCase().startsWith('totale gol:')).toList(),
      _teamGoalBias[homeKey] ?? 0.0,
      _teamGoalBias[awayKey] ?? 0.0,
      _halfTimeFraction,
    ]);

    return <String, dynamic>{
      'id': _integer(fixture['id']),
      'home': homeName.isEmpty ? 'Casa' : homeName,
      'away': awayName.isEmpty ? 'Ospite' : awayName,
      'league': (fixture['league'] ?? 'Calcio').toString(),
      'time': (fixture['time'] ?? '--:--').toString(),
      'date': _fixtureDate(fixture),
      'timestamp': kickOff,
      'predHTHome': half['home'],
      'predHTAway': half['away'],
      'probHTExact': half['probability'],
      'predFTHome': full['home'],
      'predFTAway': full['away'],
      'probFTExact': full['probability'],
      'probHome': oneXtwo['home'],
      'probDraw': oneXtwo['draw'],
      'probAway': oneXtwo['away'],
      'probOver15': over15 * 100.0,
      'probOver25': over25 * 100.0,
      'probUnder35': under35 * 100.0,
      'probBTTSYes': bothScore * 100.0,
      'probBTTSNo': (1.0 - bothScore) * 100.0,
      'topScores': alternatives,
      'dataQuality': dataQuality,
      'sampleMin': sampleMin,
      'sampleReliability': sampleReliability,
      'lambdaHome': homeLambda,
      'lambdaAway': awayLambda,
      'htFraction': _halfTimeFraction,
      'evidence': <String, dynamic>{
        'homeGames': homeGames,
        'awayGames': awayGames,
        'homeGF': homeForm['gfAvg'],
        'homeGA': homeForm['gaAvg'],
        'awayGF': awayForm['gfAvg'],
        'awayGA': awayForm['gaAvg'],
        'homeSource': homeForm['source'] ?? 'Forma aggregata feed',
        'awaySource': awayForm['source'] ?? 'Forma aggregata feed',
        'h2hGames': h2h['games'],
        'h2hHomeGF': h2h['homeGF'],
        'h2hAwayGF': h2h['awayGF'],
      },
      'basis':
          'Gol recenti verificati, fattore casa e H2H solo quando la competizione è identificata; ' +
          (marketSignal != null
              ? 'probabilità riconciliate con il moneyline del favorito.'
              : 'nessun aggiustamento moneyline applicato: lato/quotazione non verificabili.'),
      'signature': signature,
      'updatedAt': DateTime.now().toIso8601String(),
    };
  }

  Map<String, dynamic>? _marketFavoriteSignal(
    List<String> lines, String homeName, String awayName,
    [List<dynamic> proposals = const <dynamic>[]]) {
    String? favorite;
    double? moneyline;
    double? genericMoneyline;
    for (final line in lines) {
      final lower = line.toLowerCase();
      if (lower.startsWith('mercato favorito:')) {
        favorite = line.substring(line.indexOf(':') + 1).trim();
      } else if (lower.startsWith('moneyline favorito:')) {
        final match = RegExp(r'[+-]?\d+(?:[.,]\d+)?')
            .firstMatch(line.substring(line.indexOf(':') + 1));
        if (match != null) {
          moneyline = double.tryParse(match.group(0)!.replaceAll(',', '.'));
        }
      } else if (lower.startsWith('moneyline:')) {
        final match = RegExp(r'[+-]?\d+(?:[.,]\d+)?')
            .firstMatch(line.substring(line.indexOf(':') + 1));
        if (match != null) {
          genericMoneyline = double.tryParse(match.group(0)!.replaceAll(',', '.'));
        }
      }
    }
    // The feed's proposal is itself sourced from the odds provider. Preserve
    // its named winner as a fallback when preMatchStats was rebuilt from form
    // and accidentally dropped the "Mercato favorito" metadata.
    if (favorite == null) {
      for (final raw in proposals) {
        final line = raw.toString();
        if (!line.toLowerCase().startsWith('winner') ||
            line.toLowerCase().contains('conflitto')) continue;
        if (_similarTeamNames(homeName, line)) {
          favorite = homeName;
          break;
        }
        if (_similarTeamNames(awayName, line)) {
          favorite = awayName;
          break;
        }
      }
    }
    // A generic moneyline has no side by itself. It is usable only after
    // an explicit named favorite has been recovered from the feed's Winner
    // proposal; otherwise it remains intentionally ignored.
    moneyline ??= favorite == null ? null : genericMoneyline;
    if (favorite == null || moneyline == null ||
        !moneyline.isFinite || moneyline.abs() < 20 || moneyline.abs() > 5000) {
      return null;
    }
    final side = _similarTeamNames(favorite, homeName)
        ? 'home'
        : (_similarTeamNames(favorite, awayName) ? 'away' : '');
    if (side.isEmpty) return null;
    final implied = moneyline < 0
        ? -moneyline / (-moneyline + 100.0)
        : 100.0 / (moneyline + 100.0);
    if (!implied.isFinite || implied < 0.05 || implied > 0.98) return null;
    return <String, dynamic>{'side': side, 'implied': implied};
  }

  double? _marketExpectedTotal(List<String> lines) {
    for (final line in lines) {
      final match = RegExp(
        r'^\s*Totale\s+gol\s*:\s*(\d+(?:[.,]\d+)?)',
        caseSensitive: false,
      ).firstMatch(line);
      if (match == null) continue;
      final lineValue = double.tryParse((match.group(1) ?? '').replaceAll(',', '.'));
      if (lineValue == null || !lineValue.isFinite ||
          lineValue < 1.5 || lineValue > 5.5) return null;
      // A quoted line (e.g. 2.5/3.5) is a threshold, not the exact expected
      // goal total. Use a conservative offset and a limited 25% blend.
      return (lineValue - 0.20).clamp(1.3, 4.8).toDouble();
    }
    return null;
  }

  double _shrinkRate(double observed, int games, double prior) {
    // Two prior-equivalent matches temper short samples without flattening
    // every team's attack and defence toward nearly identical averages.
    const priorGames = 2.0;
    final n = games.clamp(0, 100).toDouble();
    return ((observed * n) + (prior * priorGames)) / (n + priorGames);
  }

  double? _formAverage(Map<String, dynamic> form, String key) {
    final direct = _double(form[key + 'Avg']);
    if (direct != null) return direct;
    final games = _integer(form['games']) ?? 0;
    final total = _double(form[key]);
    if (games <= 0 || total == null) return null;
    return total / games;
  }

  String _leagueKey(String value) {
    final normalized = value
        .toLowerCase()
        .replaceAll(RegExp(r"[^a-z0-9]+"), " ")
        .trim()
        .replaceAll(RegExp(r"\s+"), " ");
    final compact = normalized.replaceAll(" ", "");
    const aliases = <String, String>{
      "englishpremierleague": "premier league",
      "epl": "premier league",
      "eflchampionship": "championship",
      "skybetchampionship": "championship",
      "eflleagueone": "league one",
      "eflleaguetwo": "league two",
      "nationalleagueengland": "national league",
      "spanishlaliga": "la liga",
      "laligasantander": "la liga",
      "segundadivision": "segunda",
      "laligahypermotion": "segunda",
      "italianseriea": "serie a",
      "italianserieb": "serie b",
      "germanbundesliga": "bundesliga",
      "zweitebundesliga": "2 bundesliga",
      "frenchligue1": "ligue 1",
      "frenchligue2": "ligue 2",
      "turkishsuperlig": "turkish super lig",
      "superlig": "turkish super lig",
      "uefachampionsleague": "uefa champions league",
      "championsleague": "uefa champions league",
      "uefaeuropaleague": "uefa europa league",
      "europaleague": "uefa europa league",
      "uefaconferenceleague": "uefa conference league",
      "conferenceleague": "uefa conference league",
    };
    return aliases[compact] ?? normalized;
  }

  Map<String, dynamic>? _recentTeamForm(
    String team,
    String fixtureLeague,
    int kickOff,
    List<Map<String, dynamic>> history,
  ) {
    if (team.trim().isEmpty || kickOff <= 0) return null;
    final targetLeague = _leagueKey(fixtureLeague);
    if (targetLeague.isEmpty) return null;
    final rows = <Map<String, dynamic>>[];
    final earliest = kickOff - const Duration(days: 120).inSeconds;
    for (final result in history) {
      final status = (result['status'] ?? '').toString().toUpperCase();
      if (status != 'FT' && status != 'FINISHED') continue;
      // Historical feeds can label unrelated competitions simply "Football".
      // Do not use those rows for team form: names like Liverpool are not unique.
      final league = (result['league'] ?? '').toString().trim().toLowerCase();
      if (league.isEmpty || const {'football', 'soccer', 'calcio'}.contains(league)) continue;
      // Do not mix a team's cup/international results with its league form.
      // Cross-competition rows can distort goal rates and repeatedly pull
      // unrelated fixtures toward the same low-scoring exact score.
      if (_leagueKey(league) != targetLeague) continue;
      final timestamp = _integer(result['timestamp']) ?? 0;
      if (timestamp <= earliest || timestamp >= kickOff) continue;
      final homeGoals = _integer(result['scoreHome']);
      final awayGoals = _integer(result['scoreAway']);
      if (homeGoals == null || awayGoals == null) continue;
      final home = (result['home'] ?? '').toString();
      final away = (result['away'] ?? '').toString();
      if (_similarTeamNames(team, home)) {
        rows.add(<String, dynamic>{'timestamp': timestamp, 'gf': homeGoals, 'ga': awayGoals});
      } else if (_similarTeamNames(team, away)) {
        rows.add(<String, dynamic>{'timestamp': timestamp, 'gf': awayGoals, 'ga': homeGoals});
      }
    }
    rows.sort((a, b) =>
        (_integer(b['timestamp']) ?? 0).compareTo(_integer(a['timestamp']) ?? 0));
    if (rows.length < 3) return null;
    final recent = rows.take(10).toList();
    var weightedGoals = 0.0;
    var weightedAllowed = 0.0;
    var weightTotal = 0.0;
    var goalsTotal = 0;
    var allowedTotal = 0;
    for (var i = 0; i < recent.length; i++) {
      final weight = math.pow(0.86, i).toDouble();
      final goals = _integer(recent[i]['gf']) ?? 0;
      final allowed = _integer(recent[i]['ga']) ?? 0;
      weightedGoals += goals * weight;
      weightedAllowed += allowed * weight;
      weightTotal += weight;
      goalsTotal += goals;
      allowedTotal += allowed;
    }
    if (weightTotal <= 0) return null;
    return <String, dynamic>{
      'games': recent.length,
      'gf': goalsTotal,
      'ga': allowedTotal,
      'gfAvg': weightedGoals / weightTotal,
      'gaAvg': weightedAllowed / weightTotal,
      'source': 'Risultati verificati recenti',
    };
  }

  Map<String, dynamic> _recentHeadToHead(
    String homeName,
    String awayName,
    String fixtureLeague,
    int kickOff,
    List<Map<String, dynamic>> history,
  ) {
    if (kickOff <= 0 || _leagueKey(fixtureLeague).isEmpty) {
      return <String, dynamic>{'games': 0, 'homeGF': 0.0, 'awayGF': 0.0};
    }
    final targetLeague = _leagueKey(fixtureLeague);
    final rows = <Map<String, dynamic>>[];
    final earliest = kickOff - const Duration(days: 365).inSeconds;
    for (final result in history) {
      final status = (result['status'] ?? '').toString().toUpperCase();
      if (status != 'FT' && status != 'FINISHED') continue;
      if (_leagueKey((result['league'] ?? '').toString()) != targetLeague) continue;
      final timestamp = _integer(result['timestamp']) ?? 0;
      if (timestamp <= earliest || timestamp >= kickOff) continue;
      final homeGoals = _integer(result['scoreHome']);
      final awayGoals = _integer(result['scoreAway']);
      if (homeGoals == null || awayGoals == null) continue;
      final eventHome = (result['home'] ?? '').toString();
      final eventAway = (result['away'] ?? '').toString();
      if (_similarTeamNames(homeName, eventHome) && _similarTeamNames(awayName, eventAway)) {
        rows.add(<String, dynamic>{'timestamp': timestamp, 'homeGF': homeGoals, 'awayGF': awayGoals});
      } else if (_similarTeamNames(homeName, eventAway) && _similarTeamNames(awayName, eventHome)) {
        rows.add(<String, dynamic>{'timestamp': timestamp, 'homeGF': awayGoals, 'awayGF': homeGoals});
      }
    }
    rows.sort((a, b) =>
        (_integer(b['timestamp']) ?? 0).compareTo(_integer(a['timestamp']) ?? 0));
    final recent = rows.take(5).toList();
    if (recent.isEmpty) return <String, dynamic>{'games': 0, 'homeGF': 0.0, 'awayGF': 0.0};
    return <String, dynamic>{
      'games': recent.length,
      'homeGF': recent.fold<double>(0, (sum, item) => sum + (_integer(item['homeGF']) ?? 0)) / recent.length,
      'awayGF': recent.fold<double>(0, (sum, item) => sum + (_integer(item['awayGF']) ?? 0)) / recent.length,
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

  List<Map<String, dynamic>> _scoreMatrix(
      double homeLambda, double awayLambda, int maxGoals) {
    final home = _poisson(homeLambda, maxGoals);
    final away = _poisson(awayLambda, maxGoals);
    // Conservative Dixon-Coles correction for low-score dependence.
    const rho = -0.02;
    final rows = <Map<String, dynamic>>[];
    var total = 0.0;
    for (var h = 0; h < home.length; h++) {
      for (var a = 0; a < away.length; a++) {
        var tau = 1.0;
        if (h == 0 && a == 0) {
          tau = 1.0 - homeLambda * awayLambda * rho;
        } else if (h == 0 && a == 1) {
          tau = 1.0 + homeLambda * rho;
        } else if (h == 1 && a == 0) {
          tau = 1.0 + awayLambda * rho;
        } else if (h == 1 && a == 1) {
          tau = 1.0 - rho;
        }
        final probability = (home[h] * away[a] * math.max(0.01, tau)).toDouble();
        rows.add(<String, dynamic>{
          'home': h,
          'away': a,
          'probability': probability,
        });
        total += probability;
      }
    }
    if (total <= 0) return rows;
    for (final row in rows) {
      row['probability'] = (row['probability'] as double) / total;
    }
    return rows;
  }

  Map<String, dynamic> _bestExactScore(double homeLambda, double awayLambda) {
    final scores = _scoreMatrix(homeLambda, awayLambda, 8);
    scores.sort((a, b) => (b['probability'] as double)
        .compareTo(a['probability'] as double));
    final best = scores.first;
    return <String, dynamic>{
      'home': best['home'],
      'away': best['away'],
      'probability': (best['probability'] as double) * 100.0,
    };
  }

  List<Map<String, dynamic>> _topScores(
      double homeLambda, double awayLambda, int count) {
    final scores = _scoreMatrix(homeLambda, awayLambda, 8);
    scores.sort((a, b) => (b['probability'] as double)
        .compareTo(a['probability'] as double));
    return scores.take(count).map((score) => <String, dynamic>{
      'home': score['home'],
      'away': score['away'],
      'probability': (score['probability'] as double) * 100.0,
    }).toList();
  }

  List<double> _poisson(double lambda, int maxGoals) {
    final values = <double>[math.exp(-lambda)];
    for (var goals = 1; goals <= maxGoals; goals++) {
      values.add(values[goals - 1] * lambda / goals);
    }
    return values;
  }

  Map<String, double> _oneXtwo(double homeLambda, double awayLambda) {
    final matrix = _scoreMatrix(homeLambda, awayLambda, 8);
    var home = 0.0, draw = 0.0, away = 0.0;
    for (final row in matrix) {
      final h = row['home'] as int;
      final a = row['away'] as int;
      final probability = row['probability'] as double;
      if (h > a) {
        home += probability;
      } else if (h == a) {
        draw += probability;
      } else {
        away += probability;
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
      final actualOutcome = _outcome(actualHome, actualAway);
      final pHome = (_double(forecast['probHome']) ?? 0.0) / 100.0;
      final pDraw = (_double(forecast['probDraw']) ?? 0.0) / 100.0;
      final pAway = (_double(forecast['probAway']) ?? 0.0) / 100.0;
      forecast['brier1X2'] =
          math.pow(pHome - (actualOutcome == '1' ? 1.0 : 0.0), 2) +
          math.pow(pDraw - (actualOutcome == 'X' ? 1.0 : 0.0), 2) +
          math.pow(pAway - (actualOutcome == '2' ? 1.0 : 0.0), 2);
      forecast['goalError'] =
          (_integer(forecast['predFTHome'])! - actualHome).abs() +
          (_integer(forecast['predFTAway'])! - actualAway).abs();
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