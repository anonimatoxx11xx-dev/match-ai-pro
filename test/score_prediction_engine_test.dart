import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:match_ai_pro/score_prediction_engine.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  test('forecasts use competition aliases and return normalized 1X2 probabilities', () async {
    final engine = ScorePredictionEngine();
    const kickoff = 1800000000;
    final history = <Map<String, dynamic>>[
      _result('Team Alpha', 'Rival One', 3, 0, kickoff - 20 * 86400),
      _result('Team Alpha', 'Rival Two', 2, 0, kickoff - 16 * 86400),
      _result('Team Alpha', 'Rival Three', 4, 1, kickoff - 12 * 86400),
      _result('Team Alpha', 'Rival Four', 3, 1, kickoff - 8 * 86400),
      _result('Rival Five', 'Team Beta', 2, 0, kickoff - 19 * 86400),
      _result('Rival Six', 'Team Beta', 3, 1, kickoff - 15 * 86400),
      _result('Rival Seven', 'Team Beta', 1, 0, kickoff - 11 * 86400),
      _result('Rival Eight', 'Team Beta', 4, 1, kickoff - 7 * 86400),
    ];

    final fixture = _fixture(1001, kickoff, 8, 1);
    await engine.update(
      fixtures: <Map<String, dynamic>>[fixture],
      historicalResults: history,
    );

    final first = engine.records.singleWhere((item) => item['id'] == 1001);
    final firstHomeLambda = (first['lambdaHome'] as num).toDouble();
    final firstAwayLambda = (first['lambdaAway'] as num).toDouble();
    final home = (first['probHome'] as num).toDouble();
    final draw = (first['probDraw'] as num).toDouble();
    final away = (first['probAway'] as num).toDouble();
    expect(home, greaterThan(0));
    expect(draw, greaterThan(0));
    expect(away, greaterThan(0));
    expect(home + draw + away, closeTo(100, 0.2));
    expect(firstHomeLambda, greaterThan(0));
    expect(firstAwayLambda, greaterThan(0));

    await engine.update(
      fixtures: <Map<String, dynamic>>[_fixture(1001, kickoff, 1, 8)],
      historicalResults: history,
    );
    final revised = engine.records.singleWhere((item) => item['id'] == 1001);
    expect(revised['lambdaHome'], isNot(firstHomeLambda));
    expect(revised['lambdaAway'], isNot(firstAwayLambda));
  });
}

Map<String, dynamic> _fixture(int id, int timestamp, double homeOn, double awayOn) => <String, dynamic>{
  'id': id,
  'home': 'Team Alpha',
  'away': 'Team Beta',
  'league': 'Premier League',
  'time': '15:00',
  'timestamp': timestamp,
  'status': 'NS',
  'preMatchStats': <String>[
    'Forma casa: 3V 0N 1P · 12-2 gol · 9/12 pt',
    'Forma ospiti: 0V 0N 4P · 2-10 gol · 0/12 pt',
    'Totale gol: 2.5',
  ],
  'stats': <String, dynamic>{
    'homeOn': homeOn,
    'awayOn': awayOn,
    'homeShots': homeOn * 3,
    'awayShots': awayOn * 3,
  },
  'proposals': <String>[],
};

Map<String, dynamic> _result(String home, String away, int homeGoals, int awayGoals, int timestamp) => <String, dynamic>{
  'home': home,
  'away': away,
  'league': 'English Premier League',
  'status': 'FT',
  'scoreHome': homeGoals,
  'scoreAway': awayGoals,
  'timestamp': timestamp,
};
