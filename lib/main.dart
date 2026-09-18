// ignore_for_file: prefer_interpolation_to_compose_strings
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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


class FotMobService {
  static const base = 'https://www.fotmob.com/api';

  Future<List<MatchData>> today() async {
    final now = DateTime.now();
    final date = now.year.toString().padLeft(4, '0') +
        now.month.toString().padLeft(2, '0') +
        now.day.toString().padLeft(2, '0');
    final response = await http.get(
      Uri.parse('$base/data/matches?date=$date&timezone=Europe%2FZurich&ccode3=ITA'),
      headers: {
        'Accept': 'application/json',
        'User-Agent': 'Mozilla/5.0 (Linux; Android 14) MatchAIPro/1.0',
      },
    ).timeout(const Duration(seconds: 15));
    if (response.statusCode != 200) {
      throw Exception('FotMob HTTP '+response.statusCode.toString());
    }
    final json = jsonDecode(response.body) as Map<String, dynamic>;
    final result = <MatchData>[];
    for (final league in (json['leagues'] as List?) ?? []) {
      if (league is! Map) continue;
      final leagueName = (league['name'] ?? 'Football').toString();
      for (final item in (league['matches'] as List?) ?? []) {
        if (item is! Map) continue;
        final home = (item['home'] as Map?) ?? {};
        final away = (item['away'] as Map?) ?? {};
        final status = (item['status'] as Map?) ?? {};
        final utc = DateTime.tryParse((status['utcTime'] ?? '').toString());
        final local = utc?.toLocal();
        final started = status['started'] == true;
        final finished = status['finished'] == true;
        final cancelled = status['cancelled'] == true;
        final live = started && !finished && !cancelled;
        result.add(MatchData(
          id: ((item['id'] as num?) ?? 0).toInt(),
          home: (home['name'] ?? 'Home').toString(),
          away: (away['name'] ?? 'Away').toString(),
          time: local == null ? (item['time'] ?? '--:--').toString() :
              local.hour.toString().padLeft(2, '0') + ':' +
              local.minute.toString().padLeft(2, '0'),
          league: leagueName,
          status: live ? 'LIVE' : finished ? 'FT' : cancelled ? 'CANCELLED' : 'NS',
          live: live,
          scoreHome: (home['score'] as num?)?.toInt(),
          scoreAway: (away['score'] as num?)?.toInt(),
          homeShots: 0, awayShots: 0, homeOn: 0, awayOn: 0,
          homeCorners: 0, awayCorners: 0, homeFouls: 0, awayFouls: 0,
          homeCards: 0, awayCards: 0, homeThrow: 0, awayThrow: 0,
          homeSaves: 0, awaySaves: 0,
        ));
      }
    }
    if (result.isEmpty) throw Exception('FotMob non ha restituito partite per oggi');
    result.sort((a, b) {
      if (a.live != b.live) return a.live ? -1 : 1;
      return a.time.compareTo(b.time);
    });
    return result.take(150).toList();
  }

  Future<MatchData> details(MatchData match) async {
    final response = await http.get(
      Uri.parse('$base/data/matchDetails?matchId=${match.id}'),
      headers: {
        'Accept': 'application/json',
        'User-Agent': 'Mozilla/5.0 (Linux; Android 14) MatchAIPro/1.0',
      },
    ).timeout(const Duration(seconds: 15));
    if (response.statusCode != 200) {
      throw Exception('FotMob HTTP '+response.statusCode.toString());
    }
    final json = jsonDecode(response.body) as Map<String, dynamic>;
    final content = (json['content'] as Map?) ?? {};
    final statsRoot = (content['stats'] as Map?) ?? {};
    final periods = (statsRoot['Periods'] as Map?) ?? {};
    final all = (periods['All'] as Map?) ?? {};
    final items = (all['stats'] as List?) ?? [];
    int pair(String title, bool home) {
      final needle = title.toLowerCase();
      for (final item in items.whereType<Map>()) {
        final name = (item['title'] ?? '').toString().toLowerCase();
        if (!name.contains(needle)) continue;
        final values = item['stats'];
        if (values is List && values.length >= 2) {
          final value = values[home ? 0 : 1];
          if (value is num) return value.toInt();
          return int.tryParse(value.toString().replaceAll('%', '').trim()) ?? 0;
        }
      }
      return 0;
    }
    return match.copyWith(
      homeShots: pair('total shots', true), awayShots: pair('total shots', false),
      homeOn: pair('shots on target', true), awayOn: pair('shots on target', false),
      homeCorners: pair('corners', true), awayCorners: pair('corners', false),
      homeFouls: pair('fouls', true), awayFouls: pair('fouls', false),
      homeCards: pair('yellow cards', true) + pair('red cards', true),
      awayCards: pair('yellow cards', false) + pair('red cards', false),
      homeThrow: pair('throw-ins', true), awayThrow: pair('throw-ins', false),
      homeSaves: pair('saves', true), awaySaves: pair('saves', false),
    );
  }
}

class GitHubFeedService {
  static const endpoints = [
    'https://raw.githubusercontent.com/anonimatoxx11xx-dev/match-ai-pro/main/data/latest.json',
    'https://cdn.jsdelivr.net/gh/anonimatoxx11xx-dev/match-ai-pro@main/data/latest.json',
  ];

  Future<List<MatchData>> today() async {
    Object? lastError;
    final cacheBust = DateTime.now().millisecondsSinceEpoch.toString();

    for (final endpoint in endpoints) {
      try {
        final separator = endpoint.contains('?') ? '&' : '?';
        final uri = Uri.parse('$endpoint$separator' + 'v=' + cacheBust);
        final response = await http
            .get(uri, headers: {'Accept': 'application/json'})
            .timeout(const Duration(seconds: 12));
        if (response.statusCode != 200) {
          throw Exception('Feed HTTP ' + response.statusCode.toString());
        }
        final json = jsonDecode(response.body) as Map<String, dynamic>;
        final feedDate = (json['date'] ?? '').toString();
        final raw = (json['matches'] as List?) ?? [];
        final result = raw
            .whereType<Map<String, dynamic>>()
            .map(_decodeMatch)
            .toList();
        if (result.isEmpty) {
          throw Exception('Feed vuoto' + (feedDate.isEmpty ? '' : ' per ' + feedDate));
        }
        result.sort((a, b) {
          if (a.live != b.live) return a.live ? -1 : 1;
          return a.time.compareTo(b.time);
        });
        return result.take(150).toList();
      } catch (e) {
        lastError = e;
      }
    }

    throw Exception('Feed GitHub non raggiungibile' +
        (lastError == null ? '' : ': ' + lastError.toString()));
  }

  Future<List<MatchData>> bundled() async {
    final body = await rootBundle.loadString('data/latest.json');
    final json = jsonDecode(body) as Map<String, dynamic>;
    final raw = (json['matches'] as List?) ?? [];
    final result = raw
        .whereType<Map<String, dynamic>>()
        .map(_decodeMatch)
        .toList();
    if (result.isEmpty) throw Exception('Feed locale vuoto');
    result.sort((a, b) {
      if (a.live != b.live) return a.live ? -1 : 1;
      return a.time.compareTo(b.time);
    });
    return result.take(150).toList();
  }

  MatchData _decodeMatch(Map<String, dynamic> m) {
    final stats = (m['stats'] as Map?) ?? {};
    int value(String key) => (stats[key] as num?)?.toInt() ?? 0;
    return MatchData(
      id: ((m['id'] as num?) ?? 0).toInt(),
      home: (m['home'] ?? 'Home').toString(),
      away: (m['away'] ?? 'Away').toString(),
      time: (m['time'] ?? '--:--').toString(),
      league: (m['league'] ?? 'Football').toString(),
      status: (m['status'] ?? 'NS').toString(),
      live: m['live'] == true,
      scoreHome: (m['scoreHome'] as num?)?.toInt(),
      scoreAway: (m['scoreAway'] as num?)?.toInt(),
      homeShots: value('homeShots'),
      awayShots: value('awayShots'),
      homeOn: value('homeOn'),
      awayOn: value('awayOn'),
      homeCorners: value('homeCorners'),
      awayCorners: value('awayCorners'),
      homeFouls: value('homeFouls'),
      awayFouls: value('awayFouls'),
      homeCards: value('homeCards'),
      awayCards: value('awayCards'),
      homeThrow: value('homeThrow'),
      awayThrow: value('awayThrow'),
      homeSaves: value('homeSaves'),
      awaySaves: value('awaySaves'),
    );
  }
}

class SofaScoreService {
  static const base = 'https://api.sofascore.com/api/v1';
  Future<List<MatchData>> today() async {
    final now = DateTime.now();
    final date = now.year.toString().padLeft(4, '0') + '-' + now.month.toString().padLeft(2, '0') + '-' + now.day.toString().padLeft(2, '0');
    final response = await http.get(Uri.parse('$base/sport/football/scheduled-events/$date'), headers: {'Accept':'application/json','User-Agent':'Mozilla/5.0'});
    if (response.statusCode != 200) throw Exception('SofaScore HTTP ${response.statusCode}');
    final json = jsonDecode(response.body) as Map<String, dynamic>;
    final raw = (json['events'] as List?) ?? [];
    final result = raw.whereType<Map<String,dynamic>>().where((e)=>e['homeTeam'] is Map && e['awayTeam'] is Map).map(_eventToMatch).toList();
    if (result.isEmpty) throw Exception('SofaScore non ha restituito partite per oggi');
    result.sort((a,b){ if(a.live!=b.live)return a.live?-1:1; return a.time.compareTo(b.time);});
    return result.take(150).toList();
  }
  MatchData _eventToMatch(Map<String,dynamic> e) {
    final home=(e['homeTeam'] as Map?)??{}, away=(e['awayTeam'] as Map?)??{}, tournament=(e['tournament'] as Map?)??{}, category=(tournament['category'] as Map?)??{}, status=(e['status'] as Map?)??{};
    final type=(status['type']??'notstarted').toString();
    final ts=(e['startTimestamp'] as num?)?.toInt();
    final date=ts==null?null:DateTime.fromMillisecondsSinceEpoch(ts*1000).toLocal();
    final hs=(e['homeScore'] as Map?)??{}, as=(e['awayScore'] as Map?)??{};
    final live={'inprogress','halftime','extra_time','penalties'}.contains(type);
    final finished=type=='finished';
    return MatchData(id:((e['id'] as num?)??0).toInt(),home:(home['name']??'Home').toString(),away:(away['name']??'Away').toString(),
      time:date==null?'--:--':date.hour.toString().padLeft(2,'0')+':'+date.minute.toString().padLeft(2,'0'),
      league:(tournament['name']??category['name']??'Football').toString(),status:live?'LIVE':finished?'FT':'NS',live:live,
      scoreHome:(hs['current'] as num?)?.toInt(),scoreAway:(as['current'] as num?)?.toInt(),
      homeShots:0,awayShots:0,homeOn:0,awayOn:0,homeCorners:0,awayCorners:0,homeFouls:0,awayFouls:0,homeCards:0,awayCards:0,homeThrow:0,awayThrow:0,homeSaves:0,awaySaves:0);
  }
  Future<MatchData> details(MatchData match) async {
    final response=await http.get(Uri.parse('$base/event/${match.id}/statistics'),headers:{'Accept':'application/json','User-Agent':'Mozilla/5.0'});
    if(response.statusCode!=200)throw Exception('SofaScore HTTP ${response.statusCode}');
    final json=jsonDecode(response.body) as Map<String,dynamic>;
    final periods=(json['statistics'] as List?)??[]; Map all={};
    for(final p in periods.whereType<Map>()){if(p['period']=='ALL'){all=p;break;}}
    if(all.isEmpty&&periods.isNotEmpty&&periods.first is Map)all=periods.first as Map;
    final groups=(all['groups'] as List?)??[]; final home=<String,int>{},away=<String,int>{};
    for(final group in groups.whereType<Map>()){final items=(group['statisticsItems'] as List?)??[];for(final item in items.whereType<Map>()){
      final name=(item['name']??'').toString().toLowerCase(); final h=_number(item['home']),a=_number(item['away']); if(h!=null)home[name]=h;if(a!=null)away[name]=a;}}
    return match.copyWith(homeShots:_value(home,['total shots','shots']),awayShots:_value(away,['total shots','shots']),
      homeOn:_value(home,['shots on target','shots on goal']),awayOn:_value(away,['shots on target','shots on goal']),
      homeCorners:_value(home,['corner kicks','corners']),awayCorners:_value(away,['corner kicks','corners']),
      homeFouls:_value(home,['fouls']),awayFouls:_value(away,['fouls']),
      homeCards:_value(home,['yellow cards'])+_value(home,['red cards']),awayCards:_value(away,['yellow cards'])+_value(away,['red cards']),
      homeThrow:_value(home,['throw-ins','throw ins']),awayThrow:_value(away,['throw-ins','throw ins']),
      homeSaves:_value(home,['goalkeeper saves','saves']),awaySaves:_value(away,['goalkeeper saves','saves']));
  }
  int? _number(dynamic v){if(v is num)return v.toInt();if(v is String)return int.tryParse(v.replaceAll('%','').trim());return null;}
  int _value(Map<String,int> m,List<String> names){for(final n in names){final v=m[n];if(v!=null)return v;}return 0;}
}

class EspnService {
  static const base='https://site.api.espn.com/apis/site/v2/sports/soccer';
  static const leagues=['ita.1','eng.1','esp.1','ger.1','fra.1','uefa.champions','uefa.europa','uefa.europa.conf','usa.1','ned.1','por.1','bel.1','sco.1','tur.1','bra.1','arg.1','mex.1','sau.1','fifa.world'];
  Future<List<MatchData>> today() async {
    final now=DateTime.now(); final date=now.year.toString().padLeft(4,'0')+now.month.toString().padLeft(2,'0')+now.day.toString().padLeft(2,'0'); final all=<MatchData>[];
    for(final league in leagues){try{final response=await http.get(Uri.parse('$base/$league/scoreboard?dates=$date'),headers:{'Accept':'application/json'});if(response.statusCode!=200)continue;
      final json=jsonDecode(response.body) as Map<String,dynamic>;final events=(json['events'] as List?)??[];for(final e in events.whereType<Map<String,dynamic>>()){final m=_eventToMatch(e);if(m!=null)all.add(m);}}catch(_){}}
    final unique=<int,MatchData>{};for(final m in all)unique[m.id]=m;final result=unique.values.toList();result.sort((a,b)=>a.time.compareTo(b.time));
    if(result.isEmpty)throw Exception('ESPN non ha restituito partite per oggi');return result.take(150).toList();
  }
  MatchData? _eventToMatch(Map<String,dynamic> event){
    final competitions=(event['competitions'] as List?)??[];if(competitions.isEmpty||competitions.first is! Map)return null;final comp=competitions.first as Map;final competitors=(comp['competitors'] as List?)??[];if(competitors.length<2)return null;
    Map home={},away={};for(final x in competitors.whereType<Map>()){if(x['homeAway']=='home')home=x;if(x['homeAway']=='away')away=x;}
    final ht=(home['team'] as Map?)??{},at=(away['team'] as Map?)??{},status=(comp['status'] as Map?)??{},type=(status['type'] as Map?)??{},state=(type['state']??'').toString();final date=DateTime.tryParse((event['date']??'').toString())?.toLocal();
    return MatchData(id:int.tryParse((event['id']??'').toString())??0,home:(ht['displayName']??ht['name']??'Home').toString(),away:(at['displayName']??at['name']??'Away').toString(),
      time:date==null?'--:--':date.hour.toString().padLeft(2,'0')+':'+date.minute.toString().padLeft(2,'0'),league:((event['league'] as Map?)?['name']??'Football').toString(),
      status:state=='in'?'LIVE':state=='post'?'FT':'NS',live:state=='in',scoreHome:int.tryParse((home['score']??'').toString()),scoreAway:int.tryParse((away['score']??'').toString()),
      homeShots:0,awayShots:0,homeOn:0,awayOn:0,homeCorners:0,awayCorners:0,homeFouls:0,awayFouls:0,homeCards:0,awayCards:0,homeThrow:0,awayThrow:0,homeSaves:0,awaySaves:0);
  }
}

class ApiFootballService {
  static const base = 'https://v3.football.api-sports.io';
  final bool rapidApi;

  const ApiFootballService({this.rapidApi = false});

  Map<String, String> get headers => rapidApi
      ? {
          'x-rapidapi-key': rapidApiKey,
          'x-rapidapi-host': 'v3.football.api-sports.io',
          'Accept': 'application/json',
        }
      : {
          'x-apisports-key': apiFootballKey,
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
  final fotMob = FotMobService();
  final sofaScore = SofaScoreService();
  final espn = EspnService();
  final api = const ApiFootballService();
  final rapidApi = const ApiFootballService(rapidApi: true);
  final footballData = FootballDataService();

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      loading = true;
      error = null;
    });

    final feed = GitHubFeedService();

    // Mostra subito il feed incorporato nell'APK. In questo modo l'app
    // funziona anche quando il DNS/rete del telefono non riesce a risolvere
    // i provider esterni.
    List<MatchData>? bundledData;
    try {
      bundledData = await feed.bundled();
      if (!mounted) return;
      setState(() {
        matches = bundledData!;
        loading = false;
      });
    } catch (_) {
      // Se l'asset locale non è disponibile, lasciamo il tentativo remoto.
    }

    // Aggiorna con i dati remoti in background, senza mai cancellare un feed
    // locale valido solo perché il telefono non ha accesso al DNS.
    try {
      final remoteData = await feed.today();
      if (!mounted) return;
      setState(() {
        matches = remoteData;
        loading = false;
        error = null;
      });
    } catch (remoteError) {
      if (!mounted) return;
      if (matches.isEmpty) {
        setState(() {
          loading = false;
          error = 'Nessun feed disponibile.\n\n' +
              remoteError.toString().replaceFirst('Exception: ', '');
        });
      } else {
        setState(() {
          loading = false;
          error = null;
        });
      }
    }
  }

  Future<void> _open(MatchData m) async {
    if (!mounted) return;

    // Mostra immediatamente la partita dal feed locale/remoto. Le statistiche
    // dettagliate vengono aggiornate solo se un provider risponde.
    var detailed = m;
    try {
      detailed = await fotMob.details(m).timeout(const Duration(seconds: 5));
    } catch (_) {
      try {
        detailed = await sofaScore.details(m).timeout(const Duration(seconds: 5));
      } catch (_) {}
    }

    if (!mounted) return;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF07110F),
      builder: (_) => MatchDetail(match: detailed),
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
          NavigationDestination(
            icon: Icon(Icons.calendar_today),
            label: 'Giornata',
          ),
          NavigationDestination(
            icon: Icon(Icons.auto_awesome),
            label: 'Proposte IA',
          ),
          NavigationDestination(
            icon: Icon(Icons.psychology),
            label: 'AI Center',
          ),
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
        'Dati non disponibili',
        error!,
        setup: false,
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
          'Dati e statistiche arrivano dal feed remoto aggiornato automaticamente.',
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
      return 'Partita reale. Le statistiche dettagliate vengono aggiornate automaticamente dal feed remoto quando disponibili.';
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
