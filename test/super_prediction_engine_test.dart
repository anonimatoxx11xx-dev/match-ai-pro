import 'package:flutter_test/flutter_test.dart';
import 'package:match_ai_pro/super_prediction_engine.dart';

void main() {
  final engine = SuperPredictionEngine();

  test('1X2 probabilities are normalized and score markets are present', () {
    final result = engine.predict(
      fixtures: [_fixture(1, 1800000000)],
      history: _history(1800000000),
    ).single;
    final p = result['prediction'] as Map<String, dynamic>;
    final total = (p['home'] as num) + (p['draw'] as num) + (p['away'] as num);
    expect(total, closeTo(100, 2));
    expect(p['xgHome'], greaterThan(0));
    expect(p['xgAway'], greaterThan(0));
    expect(p['score'], matches(RegExp(r'^\d-\d$')));
    expect(p['over25'], inInclusiveRange(0, 100));
    expect(p['btts'], inInclusiveRange(0, 100));
    expect((p['scores'] as List), hasLength(5));
  });

  test('strong and weak samples produce different data-quality confidence', () {
    final weak = engine.predict(fixtures: [_fixture(2, 1800000000)], history: []).single['prediction'] as Map;
    final strong = engine.predict(fixtures: [_fixture(3, 1800000000)], history: _history(1800000000)).single['prediction'] as Map;
    expect(strong['quality'], greaterThan(weak['quality']));
    expect(weak['qualityLabel'], 'Limitata');
  });

  test('same-team form is scoped to the same competition', () {
    final history = _history(1800000000);
    history.add({
      'home': 'Team A', 'away': 'Team B', 'league': 'Cup Competition',
      'status': 'FT', 'scoreHome': 8, 'scoreAway': 0, 'timestamp': 1799900000,
    });
    final withCup = engine.predict(fixtures: [_fixture(4, 1800000000)], history: history).single['prediction'] as Map;
    final withoutCup = engine.predict(fixtures: [_fixture(5, 1800000000)], history: _history(1800000000)).single['prediction'] as Map;
    expect(withCup['xgHome'], withoutCup['xgHome']);
    expect(withCup['xgAway'], withoutCup['xgAway']);
  });
}

Map<String, dynamic> _fixture(int id, int timestamp) => {
  'id': id, 'home': 'Team A', 'away': 'Team B', 'league': 'Premier League',
  'timestamp': timestamp, 'time': '20:00', 'status': 'NS',
  'stats': {'homeShots': 14, 'awayShots': 8, 'homeOn': 5, 'awayOn': 2},
  'preMatchStats': ['Mercato favorito: Team A'],
};

List<Map<String, dynamic>> _history(int before) => [
  _result('Team A', 'Other 1', 3, 0, before - 1000),
  _result('Other 2', 'Team A', 0, 2, before - 2000),
  _result('Team A', 'Other 3', 2, 0, before - 3000),
  _result('Other 4', 'Team A', 1, 2, before - 4000),
  _result('Other 5', 'Team B', 2, 0, before - 5000),
  _result('Team B', 'Other 6', 0, 2, before - 6000),
  _result('Other 7', 'Team B', 3, 0, before - 7000),
  _result('Team B', 'Other 8', 1, 0, before - 8000),
  _result('Other 9', 'Other 10', 1, 1, before - 9000),
  _result('Other 11', 'Other 12', 2, 1, before - 10000),
];

Map<String, dynamic> _result(String home, String away, int sh, int sa, int timestamp) => {
  'home': home, 'away': away, 'league': 'Premier League',
  'status': 'FT', 'scoreHome': sh, 'scoreAway': sa, 'timestamp': timestamp,
};
