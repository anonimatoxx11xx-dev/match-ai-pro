// ignore_for_file: prefer_interpolation_to_compose_strings
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

const apiFootballKey = String.fromEnvironment('API_FOOTBALL_KEY');
const footballDataKey = String.fromEnvironment('API_FOOTBALDATA_KEY');
const rapidApiKey = String.fromEnvironment('APP_RAPIDAPI_KEY');

void main() => runApp(const MatchAIProApp());

class MatchAIProApp extends StatelessWidget {
  const MatchAIProApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'Match AI Pro',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          brightness: Brightness.dark,
          useMaterial3: true,
          colorScheme: ColorScheme.fromSeed(
            seedColor: const Color(0xFF00C896),
            brightness: Brightness.dark,
          ),
          scaffoldBackgroundColor: const Color(0xFF07110F),
        ),
        home: const HomePage(),
      );
}

class MatchData {
  final int id;
  final String home, away, time, league, status;
  final bool live;
  final int? scoreHome, scoreAway;
  final int homeShots, awayShots, homeOn, awayOn, homeCorners, awayCorners;
  final int homeFouls, awayFouls, homeCards, awayCards, homeThrow, awayThrow;
  final int homeSaves, awaySaves;

  const MatchData({
    required this.id,
    required this.home,
    required this.away,
    required this.time,
    required this.league,
    required this.status,
    required this.live,
    required this.scoreHome,
    required this.scoreAway,
    required this.homeShots,
    required this.awayShots,
    required this.homeOn,
    required this.awayOn,
    required this.homeCorners,
    required this.awayCorners,
    required this.homeFouls,
    required this.awayFouls,
    required this.homeCards,
    required this.awayCards,
    required this.homeThrow,
    required this.awayThrow,
    required this.homeSaves,
    required this.awaySaves,
  });

  bool get hasStats =>
      homeShots + awayShots + homeCorners + awayCorners + homeFouls +
      awayFouls + homeCards + awayCards + homeSaves + awaySaves > 0;

  MatchData copyWith({
    int? homeShots, int? awayShots, int? homeOn, int? awayOn,
    int? homeCorners, int? awayCorners, int? homeFouls, int? awayFouls,
    int? homeCards, int? awayCards, int? homeThrow, int? awayThrow,
    int? homeSaves, int? awaySaves,
  }) => MatchData(
        id: id, home: home, away: away, time: time, league: league,
        status: status, live: live, scoreHome: scoreHome, scoreAway: scoreAway,
        homeShots: homeShots ?? this.homeShots,
        awayShots: awayShots ?? this.awayShots,
        homeOn: homeOn ?? this.homeOn, awayOn: awayOn ?? this.awayOn,
        homeCorners: homeCorners ?? this.homeCorners,
        awayCorners: awayCorners ?? this.awayCorners,
        homeFouls: homeFouls ?? this.homeFouls,
        awayFouls: awayFouls ?? this.awayFouls,
        homeCards: homeCards ?? this.homeCards,
        awayCards: awayCards ?? this.awayCards,
        homeThrow: homeThrow ?? this.homeThrow,
        awayThrow: awayThrow ?? this.awayThrow,
        homeSaves: homeSaves ?? this.homeSaves,
        awaySaves: awaySaves ?? this.awaySaves,
      );
}

class ApiFootballService {
  static const base = 'https://v3.football.api-sports.io';

  Map<String, String> get headers => {
        'x-apisports-key': apiKey,
        'Accept': 'application/json',
      };

  Future<List<MatchData>> today() async {
    final now = DateTime.now();
    final date = now.year.toString().padLeft(4, '0') + '-' +
        now.month.toString().padLeft(2, '0') + '-' +
        now.day.toString().padLeft(2, '0');
    final uri = Uri.parse('$base/fixtures?date=$date&timezone=Europe%2FZurich');
    final response = await http.get(uri, headers: headers);
    if (response.statusCode != 200) {
      throw Exception('API ${response.statusCode}: ${response.body}');
    }
    final json = jsonDecode(response.body) as Map<String, dynamic>;
    final errors = json['errors'];
    if (errors is Map && errors.isNotEmpty) throw Exception(errors.values.join(' '));
    final raw = (json['response'] as List?) ?? [];
    final result = raw.map((e) => _fixtureToMatch(e as Map<String, dynamic>)).toList();
    result.sort((a, b) {
      if (a.live != b.live) return a.live ? -1 : 1;
      return a.time.compareTo(b.time);
    });
    return result.take(100).toList();
  }

  MatchData _fixtureToMatch(Map<String, dynamic> f) {
    final fixture = f['fixture'] as Map<String, dynamic>;
    final teams = f['teams'] as Map<String, dynamic>;
    final home = teams['home'] as Map<String, dynamic>;
    final away = teams['away'] as Map<String, dynamic>;
    final league = f['league'] as Map<String, dynamic>;
    final goals = (f['goals'] as Map<String, dynamic>?) ?? {};
    final status = (fixture['status'] as Map<String, dynamic>?) ?? {};
    final short = (status['short'] ?? 'TBD').toString();
    final date = DateTime.tryParse((fixture['date'] ?? '').toString());
    return MatchData(
      id: (fixture['id'] as num).toInt(),
      home: (home['name'] ?? 'Home').toString(),
      away: (away['name'] ?? 'Away').toString(),
      time: date == null ? '--:--' : date.hour.toString().padLeft(2, '0') + ':' +
          date.minute.toString().padLeft(2, '0'),
      league: (league['name'] ?? 'Football').toString(),
      status: short,
      live: const {'1H', 'HT', '2H', 'ET', 'BT', 'P'}.contains(short),
      scoreHome: (goals['home'] as num?)?.toInt(),
      scoreAway: (goals['away'] as num?)?.toInt(),
      homeShots: 0, awayShots: 0, homeOn: 0, awayOn: 0,
      homeCorners: 0, awayCorners: 0, homeFouls: 0, awayFouls: 0,
      homeCards: 0, awayCards: 0, homeThrow: 0, awayThrow: 0,
      homeSaves: 0, awaySaves: 0,
    );
  }

  Future<MatchData> details(MatchData match) async {
    final uri = Uri.parse('$base/fixtures/statistics?fixture=${match.id}');
    final response = await http.get(uri, headers: headers);
    if (response.statusCode != 200) {
      throw Exception('API ${response.statusCode}: ${response.body}');
    }
    final json = jsonDecode(response.body) as Map<String, dynamic>;
    final raw = (json['response'] as List?) ?? [];
    if (raw.isEmpty) return match;
    final homeId = _teamId(match.home, raw);
    final home = raw.firstWhere(
      (x) => (x['team']['id'] as num?)?.toInt() == homeId,
      orElse: () => raw.first,
    );
    final away = raw.length > 1
        ? raw.firstWhere(
            (x) => (x['team']['id'] as num?)?.toInt() != homeId,
            orElse: () => raw[1],
          )
        : raw.first;
    return match.copyWith(
      homeShots: _stat(home, 'Total Shots'), awayShots: _stat(away, 'Total Shots'),
      homeOn: _stat(home, 'Shots on Goal'), awayOn: _stat(away, 'Shots on Goal'),
      homeCorners: _stat(home, 'Corner Kicks'), awayCorners: _stat(away, 'Corner Kicks'),
      homeFouls: _stat(home, 'Fouls'), awayFouls: _stat(away, 'Fouls'),
      homeCards: _stat(home, 'Yellow Cards') + _stat(home, 'Red Cards'),
      awayCards: _stat(away, 'Yellow Cards') + _stat(away, 'Red Cards'),
      homeThrow: _stat(home, 'Throw-ins'), awayThrow: _stat(away, 'Throw-ins'),
      homeSaves: _stat(home, 'Goalkeeper Saves'), awaySaves: _stat(away, 'Goalkeeper Saves'),
    );
  }

  int _teamId(String name, List<dynamic> raw) {
    for (final item in raw) {
      final team = item['team'];
      if (team is Map && team['name'] == name) return (team['id'] as num).toInt();
    }
    return (raw.first['team']['id'] as num).toInt();
  }

  int _stat(dynamic teamBlock, String type) {
    final list = (teamBlock['statistics'] as List?) ?? [];
    for (final item in list) {
      if (item is Map && item['type'] == type) {
        final value = item['value'];
        if (value is num) return value.toInt();
        if (value is String) {
          final parsed = int.tryParse(value.replaceAll('%', ''));
          if (parsed != null) return parsed;
        }
      }
    }
    return 0;
  }
}

class FootballDataService {
  static const base = 'https://api.football-data.org/v4';

  Future<List<MatchData>> today() async {
    final now = DateTime.now().toUtc();
    final date = now.year.toString().padLeft(4, '0') + '-' +
        now.month.toString().padLeft(2, '0') + '-' +
        now.day.toString().padLeft(2, '0');

    final uri = Uri.parse('$base/matches?dateFrom=$date&dateTo=$date');
    final response = await http.get(uri, headers: {
      'X-Auth-Token': footballDataKey,
      'Accept': 'application/json',
    });

    if (response.statusCode != 200) {
      throw Exception('Football-Data API ' + response.statusCode.toString() + ': ' + response.body);
    }

    final json = jsonDecode(response.body) as Map<String, dynamic>;
    final raw = (json['matches'] as List?) ?? [];
    final result = raw.map((e) {
      final f = e as Map<String, dynamic>;
      final home = (f['homeTeam'] as Map<String, dynamic>?) ?? {};
      final away = (f['awayTeam'] as Map<String, dynamic>?) ?? {};
      final score = (f['score'] as Map<String, dynamic>?) ?? {};
      final fullTime = (score['fullTime'] as Map<String, dynamic>?) ?? {};
      final status = (f['status'] ?? 'SCHEDULED').toString();
      final utcDate = DateTime.tryParse((f['utcDate'] ?? '').toString());

      return MatchData(
        id: ((f['id'] as num?) ?? 0).toInt(),
        home: (home['name'] ?? 'Home').toString(),
        away: (away['name'] ?? 'Away').toString(),
        time: utcDate == null ? '--:--' : utcDate.toLocal().hour.toString().padLeft(2, '0') + ':' + utcDate.toLocal().minute.toString().padLeft(2, '0'),
        league: ((f['competition'] as Map<String, dynamic>?)?['name'] ?? 'Football').toString(),
        status: status,
        live: const {'IN_PLAY', 'PAUSED'}.contains(status),
        scoreHome: (fullTime['home'] as num?)?.toInt(),
        scoreAway: (fullTime['away'] as num?)?.toInt(),
        homeShots: 0, awayShots: 0, homeOn: 0, awayOn: 0,
        homeCorners: 0, awayCorners: 0, homeFouls: 0, awayFouls: 0,
        homeCards: 0, awayCards: 0, homeThrow: 0, awayThrow: 0,
        homeSaves: 0, awaySaves: 0,
      );
    }).toList();

    result.sort((a, b) {
      if (a.live != b.live) return a.live ? -1 : 1;
      return a.time.compareTo(b.time);
    });
    return result;
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});
  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  int tab = 0;
  bool loading = true;
  String? error;
  List<MatchData> matches = [];
  final api = ApiFootballService();
  final footballData = FootballDataService();

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (apiFootballKey.isEmpty && footballDataKey.isEmpty) {
      setState(() { loading = false; error = 'Nessuna API calcistica configurata'; });
      return;
    }
    setState(() { loading = true; error = null; });
    try {
      List<MatchData> data;
      if (apiFootballKey.isNotEmpty) {
        try {
          data = await api.today();
        } catch (_) {
          if (footballDataKey.isEmpty) rethrow;
          data = await footballData.today();
        }
      } else {
        data = await footballData.today();
      }
      if (!mounted) return;
      setState(() { matches = data; loading = false; });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        loading = false;
        error = e.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  Future<void> _open(MatchData m) async {
    MatchData current = m;
    final canLoadStats = m.live || m.status == 'FT' || m.status == 'AET' || m.status == 'PEN';
    if (!m.hasStats && canLoadStats) {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (_) => const Center(child: CircularProgressIndicator()),
      );
      try {
        current = await api.details(m);
        final index = matches.indexWhere((x) => x.id == m.id);
        if (index >= 0) setState(() => matches[index] = current);
      } catch (_) {
      } finally {
        if (mounted) Navigator.of(context).pop();
      }
    }
    if (!mounted) return;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF07110F),
      builder: (_) => MatchDetail(match: current),
    );
  }

  @override
  Widget build(BuildContext context) {
    final pages = [_matches(), _proposals(), _center()];
    return Scaffold(
      appBar: AppBar(
        title: const Row(
          children: [
            Icon(Icons.sports_soccer, color: Color(0xFF00C896)),
            SizedBox(width: 10),
            Text('MATCH AI PRO', style: TextStyle(fontWeight: FontWeight.w900)),
          ],
        ),
        actions: [
          IconButton(
            onPressed: _load,
            icon: const Icon(Icons.refresh),
            tooltip: 'Aggiorna dati reali',
          ),
        ],
      ),
      body: pages[tab],
      bottomNavigationBar: NavigationBar(
        selectedIndex: tab,
        onDestinationSelected: (i) => setState(() => tab = i),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.calendar_today), label: 'Giornata'),
          NavigationDestination(icon: Icon(Icons.auto_awesome), label: 'Proposte IA'),
          NavigationDestination(icon: Icon(Icons.psychology), label: 'AI Center'),
        ],
      ),
    );
  }

  Widget _header(String title, String sub) => Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(22),
          gradient: const LinearGradient(
            colors: [Color(0xFF12382E), Color(0xFF0D201B)],
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w900)),
            const SizedBox(height: 6),
            Text(sub, style: const TextStyle(color: Colors.white70)),
          ],
        ),
      );

  Widget _state(String title, String message, {bool setup = false}) => Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(22),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(setup ? Icons.key : Icons.cloud_off, size: 48, color: const Color(0xFF00C896)),
                  const SizedBox(height: 14),
                  Text(title, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900)),
                  const SizedBox(height: 8),
                  Text(message, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white70, height: 1.4)),
                  if (setup) ...[
                    const SizedBox(height: 14),
                    const Text(
                      'Configura il secret GitHub API_FOOTBALL_KEY e ricompila l’APK.',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      );

  Widget _matches() {
    if (loading) return const Center(child: CircularProgressIndicator());
    if (error != null) {
      return _state(
        error == 'Nessuna API calcistica configurata' ? 'Configurazione richiesta' : 'Dati non disponibili',
        error!,
        setup: error == 'API key non configurata',
      );
    }
    if (matches.isEmpty) {
      return _state('Nessuna partita', 'Non risultano partite per oggi nel feed del provider.');
    }
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _header('PARTITE DELLA GIORNATA', 'Dati reali aggiornati dal provider'),
        const SizedBox(height: 8),
        const Text(
          'Tocca una partita live o terminata per caricare le statistiche reali.',
          style: TextStyle(color: Colors.white54),
        ),
        const SizedBox(height: 14),
        ...matches.map(
          (m) => Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: InkWell(onTap: () => _open(m), child: _card(m)),
          ),
        ),
      ],
    );
  }

  Widget _proposals() => ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _header('PROPOSTE IA', 'Lettura automatica dei dati reali disponibili'),
          const SizedBox(height: 16),
          if (matches.isEmpty)
            const Card(
              child: Padding(
                padding: EdgeInsets.all(18),
                child: Text('Carica prima le partite reali dalla scheda Giornata.'),
              ),
            )
          else
            ...matches.take(20).map(
              (m) => Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(m.home + ' — ' + m.away, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
                      const SizedBox(height: 10),
                      Text(_analysis(m), style: const TextStyle(color: Colors.white70, height: 1.4)),
                      if (m.hasStats) ...[
                        const SizedBox(height: 10),
                        Wrap(
                          spacing: 8,
                          children: [
                            _tag('Tiri ' + (m.homeShots + m.awayShots).toString()),
                            _tag('Corner ' + (m.homeCorners + m.awayCorners).toString()),
                            _tag('Cartellini ' + (m.homeCards + m.awayCards).toString()),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
        ],
      );

  Widget _center() => ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _header('AI CENTER', 'Confronta qualsiasi partita reale'),
          const SizedBox(height: 16),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.psychology_alt, size: 42, color: Color(0xFF00C896)),
                  const SizedBox(height: 10),
                  const Text('Analisi interattiva', style: TextStyle(fontSize: 21, fontWeight: FontWeight.w800)),
                  const SizedBox(height: 8),
                  const Text(
                    'Apri una partita per caricare statistiche reali come tiri, corner, falli, cartellini e parate.',
                    style: TextStyle(color: Colors.white70),
                  ),
                  const SizedBox(height: 16),
                  ...matches.take(30).map(
                    (m) => Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: OutlinedButton.icon(
                        onPressed: () => _open(m),
                        icon: const Icon(Icons.analytics_outlined),
                        label: Text(m.home + ' — ' + m.away),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      );

  Widget _card(MatchData m) => Card(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              Row(
                children: [
                  Expanded(child: Text(m.league, style: const TextStyle(color: Colors.white54))),
                  if (m.live)
                    const _Live()
                  else
                    Text(
                      m.scoreHome != null ? m.scoreHome.toString() + ' : ' + m.scoreAway.toString() : m.time,
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                ],
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(child: Text(m.home, textAlign: TextAlign.center, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800))),
                  Column(
                    children: [
                      Text(
                        m.scoreHome != null && m.scoreAway != null
                            ? m.scoreHome.toString() + ' - ' + m.scoreAway.toString()
                            : 'VS',
                        style: const TextStyle(fontWeight: FontWeight.w900, color: Colors.white54),
                      ),
                      if (m.live)
                        Text(m.status, style: const TextStyle(fontSize: 10, color: Color(0xFF00C896))),
                    ],
                  ),
                  Expanded(child: Text(m.away, textAlign: TextAlign.center, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800))),
                ],
              ),
              const SizedBox(height: 14),
              if (m.hasStats)
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    _stat('Tiri', m.homeShots, m.awayShots, Icons.sports_soccer),
                    _stat('Corner', m.homeCorners, m.awayCorners, Icons.flag),
                    _stat('Cartellini', m.homeCards, m.awayCards, Icons.style),
                    _stat('Falli', m.homeFouls, m.awayFouls, Icons.front_hand),
                  ],
                )
              else
                const Text('Statistiche: apri la partita', style: TextStyle(color: Colors.white38, fontSize: 12)),
            ],
          ),
        ),
      );

  Widget _stat(String l, int a, int b, IconData i) => Column(
        children: [
          Icon(i, size: 18, color: Colors.white54),
          Text(a.toString() + ':' + b.toString(), style: const TextStyle(fontWeight: FontWeight.w800)),
          Text(l, style: const TextStyle(fontSize: 9, color: Colors.white38)),
        ],
      );

  Widget _tag(String s) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        decoration: BoxDecoration(color: const Color(0xFF17352C), borderRadius: BorderRadius.circular(20)),
        child: Text(s, style: const TextStyle(fontSize: 12)),
      );

  String _analysis(MatchData m) {
    if (!m.hasStats) {
      return 'Partita reale. Le statistiche dettagliate vengono richieste quando apri il match, così evitiamo chiamate inutili e consumi eccessivi del piano gratuito.';
    }
    final shots = m.homeShots + m.awayShots;
    final corners = m.homeCorners + m.awayCorners;
    final cards = m.homeCards + m.awayCards;
    final level = shots >= 25 ? 'alta' : shots >= 16 ? 'media' : 'contenuta';
    return 'Intensità ' + level + '. Dati reali: ' + shots.toString() + ' tiri, ' +
        corners.toString() + ' corner e ' + cards.toString() +
        ' cartellini. L’analisi confronta volume offensivo, pressione e disciplina senza inventare valori mancanti.';
  }
}

class MatchDetail extends StatelessWidget {
  final MatchData match;
  const MatchDetail({super.key, required this.match});

  @override
  Widget build(BuildContext context) => SafeArea(
        child: DraggableScrollableSheet(
          expand: false,
          initialChildSize: .88,
          minChildSize: .55,
          maxChildSize: .96,
          builder: (_, c) => ListView(
            controller: c,
            padding: const EdgeInsets.all(18),
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(match.home + ' — ' + match.away, style: const TextStyle(fontSize: 23, fontWeight: FontWeight.w900)),
                  ),
                  if (match.live) const _Live(),
                ],
              ),
              const SizedBox(height: 6),
              Text(match.league, style: const TextStyle(color: Colors.white54)),
              if (match.scoreHome != null && match.scoreAway != null) ...[
                const SizedBox(height: 12),
                Center(
                  child: Text(
                    match.scoreHome.toString() + ' - ' + match.scoreAway.toString(),
                    style: const TextStyle(fontSize: 34, fontWeight: FontWeight.w900),
                  ),
                ),
              ],
              const SizedBox(height: 18),
              _row('Tiri', match.homeShots, match.awayShots, Icons.sports_soccer),
              _row('Tiri in porta', match.homeOn, match.awayOn, Icons.gps_fixed),
              _row('Corner', match.homeCorners, match.awayCorners, Icons.flag),
              _row('Falli', match.homeFouls, match.awayFouls, Icons.front_hand),
              _row('Cartellini', match.homeCards, match.awayCards, Icons.style),
              _row('Rimesse', match.homeThrow, match.awayThrow, Icons.compare_arrows),
              _row('Parate', match.homeSaves, match.awaySaves, Icons.pan_tool_alt),
              const SizedBox(height: 12),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('AI MATCH ANALYSIS', style: TextStyle(color: Color(0xFF00C896), fontWeight: FontWeight.w900)),
                      const SizedBox(height: 8),
                      Text(
                        match.hasStats
                            ? 'Analisi basata esclusivamente sulle statistiche ricevute dal provider per questa partita.'
                            : 'Per questa partita non sono ancora disponibili statistiche dettagliate.',
                        style: const TextStyle(height: 1.45),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      );

  Widget _row(String n, int a, int b, IconData i) => Card(
        margin: const EdgeInsets.only(bottom: 9),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Icon(i, size: 20, color: Colors.white54),
              const SizedBox(width: 10),
              Expanded(child: Text(n, style: const TextStyle(fontWeight: FontWeight.w700))),
              Text(a.toString(), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
              const SizedBox(width: 28),
              Text(b.toString(), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
            ],
          ),
        ),
      );
}

class _Live extends StatelessWidget {
  const _Live();
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
        decoration: BoxDecoration(
          color: Colors.redAccent.withValues(alpha: .15),
          borderRadius: BorderRadius.circular(20),
        ),
        child: const Text('LIVE', style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.w900, fontSize: 11)),
      );
}
