import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:async';
import 'package:http/http.dart' as http;

// Match AI Pro live build marker
// Curated men's + women's competition feed

List<Match> globalCalendarMatches=[];

void main() => runApp(const MatchAIPro());

class MatchAIPro extends StatelessWidget {
  const MatchAIPro({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    title: 'Match AI Pro',
    theme: ThemeData(
      brightness: Brightness.dark,
      useMaterial3: true,
      scaffoldBackgroundColor: const Color(0xFF070914),
      colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF8B7CFF), brightness: Brightness.dark),
      fontFamily: 'sans',
    ),
    home: const Dashboard(),
  );
}

class Match {
  final int id;
  final String home, away, league, time;
  final bool live;
  final int? hs, ascore;
  final String status;
  final int confidence;
  final String pick;
  final String reason;
  final List<String> proposals;
  final List<String> preMatchStats;
  final Map<String,dynamic> stats;
  final String updatedAt;
  final String source;
  final int? homeTeamId, awayTeamId;
  Match({
    required this.id,
    required this.home,
    required this.away,
    required this.league,
    required this.time,
    required this.live,
    required this.hs,
    required this.ascore,
    required this.status,
    required this.confidence,
    required this.pick,
    required this.reason,
    required this.proposals,
    required this.preMatchStats,
    required this.stats,
    required this.updatedAt,
    required this.source,
    this.homeTeamId,
    this.awayTeamId,
  });
}

class MatchService {
  bool lastFeedWasValid=false;
  static const _feedUrl = 'https://raw.githubusercontent.com/anonimatoxx11xx-dev/match-ai-pro/main/data/latest.json';
  static const _calendarUrl = 'https://raw.githubusercontent.com/anonimatoxx11xx-dev/match-ai-pro/main/data/calendar.json';

  Future<List<Match>> calendar() async {
    final stamp=DateTime.now().millisecondsSinceEpoch;
    try {
      final response=await http.get(Uri.parse('$_calendarUrl?t=$stamp')).timeout(const Duration(seconds:15));
      if(response.statusCode==200){
        final decoded=jsonDecode(response.body);
        if(decoded is Map && decoded['matches'] is List){
          return (decoded['matches'] as List).whereType<Map>().map((m)=>_fromFeed(m,decoded['updatedAt']?.toString()??'')).whereType<Match>().toList();
        }
      }
    } catch (_) {}
    return <Match>[];
  }

  Future<List<Match>> today() async {
    final errors=<String>[];
    final urls = <String>[
      '$_feedUrl?t=${DateTime.now().millisecondsSinceEpoch}',
      _sofaUrl(),
      _sofaApiUrl(),
    ];

    for (final url in urls) {
      try {
        final response = await http.get(
          Uri.parse(url),
          headers: const {
            'Accept': 'application/json, text/plain, */*',
            'Accept-Language': 'it-IT,it;q=0.9,en-US;q=0.8',
            'User-Agent': 'Mozilla/5.0 (Linux; Android 16) AppleWebKit/537.36 Chrome/140 Mobile Safari/537.36',
            'Referer': 'https://www.sofascore.com/',
            'Origin': 'https://www.sofascore.com',
            'X-Requested-With': 'XMLHttpRequest',
            'Cache-Control': 'no-cache',
          },
        ).timeout(const Duration(seconds: 10));

        if (response.statusCode != 200) {
          errors.add('$url -> HTTP ${response.statusCode}');
          continue;
        }

        final decoded = jsonDecode(response.body);
        final matches = _parsePayload(decoded);
        if (decoded is Map && decoded['matches'] is List) {
          lastFeedWasValid = true;
          return matches;
        }
        if (matches.isNotEmpty) return matches;
        errors.add('$url -> feed vuoto');
      } catch (e) {
        errors.add('$url -> ${e.runtimeType}');
      }
    }

    try {
      final local = await rootBundle.loadString('data/latest.json');
      final localDecoded = jsonDecode(local);
      final matches = _parsePayload(localDecoded);
      if (localDecoded is Map && localDecoded['matches'] is List) {
        lastFeedWasValid = true;
        return matches;
      }
      if (matches.isNotEmpty) return matches;
    } catch (_) {
      // Last-resort local feed is optional during development.
    }

    throw Exception('Nessun feed disponibile${errors.isEmpty ? '' : ': ${errors.last}'}');
  }

  String _date() {
    final d=DateTime.now();
    return '${d.year}-${d.month.toString().padLeft(2,'0')}-${d.day.toString().padLeft(2,'0')}';
  }

  String _sofaUrl() => 'https://www.sofascore.com/api/v1/sport/football/scheduled-events/${_date()}';
  String _sofaApiUrl() => 'https://api.sofascore.com/api/v1/sport/football/scheduled-events/${_date()}';

  List<Match> _parsePayload(dynamic decoded) {
    if (decoded is! Map) return <Match>[];
    final rawMatches = decoded['matches'];
    if (rawMatches is List) {
      final updatedAt = decoded['updatedAt']?.toString() ?? '';
      decodedSource = decoded['source']?.toString() ?? 'SofaScore';
      const allowed = {
        'serie a','serie b',
        'premier league','championship','league one','league two','national league',
        'la liga','segunda','segunda división','segunda division',
        'ligue 1','ligue 2','eredivisie','turkish super lig',
        'bundesliga','2. bundesliga',
        'uefa champions league','uefa europa league','uefa conference league',
        'uefa women’s champions league','uefa women\'s champions league',
        'fa cup','efl cup','community shield','copa del rey','supercopa de españa','supercopa de espana',
        'german dfb pokal','coppa italia','coupe de france','knvb cup','turkish cup',
        'women\'s super league','liga f','vrouwen eredivisie','frauen-bundesliga','première ligue','premiere ligue',
        'serie a femminile',
        'international friendly','international friendlies','uefa nations league','fifa world cup qualifying',
        'world cup qualifying - uefa','world cup qualifying - conmebol','world cup qualifying - concacaf',
        'world cup qualifying - afc','world cup qualifying - caf','world cup qualifying - ofc',
        'concacaf nations league','copa america','afc asian cup','africa cup of nations','gold cup',
      };
      bool isAllowed(Map m){
        final v=(m['league']?.toString()??'').trim().toLowerCase();
        return allowed.contains(v) || (v.endsWith(' women') && allowed.contains(v.substring(0,v.length-6).trim()));
      }
      return rawMatches.whereType<Map>().where(isAllowed).map((m) => _fromFeed(m, updatedAt)).whereType<Match>().toList();
    }

    final events = decoded['events'];
    if (events is List) {
      return events.whereType<Map>().map((e) => _fromEvent(e)).whereType<Match>().toList();
    }
    return <Match>[];
  }

  String decodedSource = 'SofaScore';

  Match? _fromFeed(Map m, String updatedAt) {
    final id = _int(m['id']) ?? 0;
    if (id == 0) return null;
    final proposals = (m['proposals'] as List? ?? const [])
        .map((x) => x.toString().trim())
        .where((x) => x.isNotEmpty)
        .toList();
    final pre = (m['preMatchStats'] as List? ?? const [])
        .map((x) => x.toString().trim())
        .where((x) => x.isNotEmpty)
        .toList();
    final score = (_int(m['proposalScore']) ?? 0).clamp(0, 100);
    final confidence = score > 0 ? score : (proposals.isNotEmpty ? 50 : 0);
    return Match(
      id:id,
      home:m['home']?.toString() ?? 'Home',
      away:m['away']?.toString() ?? 'Away',
      league:m['league']?.toString() ?? 'Football',
      time:m['time']?.toString() ?? '--:--',
      live:m['live'] == true || m['status']?.toString() == 'LIVE',
      hs:_int(m['scoreHome']),
      ascore:_int(m['scoreAway']),
      status:m['status']?.toString() ?? 'NS',
      confidence:confidence,
      pick:proposals.isNotEmpty ? proposals.first : (m['status']?.toString() == 'LIVE' ? 'Live • dati in aggiornamento' : 'Nessuna proposta forte'),
      reason:pre.isNotEmpty ? pre.join(' • ') : (proposals.isNotEmpty ? 'Proposta disponibile nel feed statistico.' : (m['status']?.toString() == 'LIVE' ? 'Il punteggio live non è ancora disponibile nel feed corrente.' : 'Dati insufficienti per una selezione affidabile.')),
      proposals:proposals,
      preMatchStats:pre,
      stats:_map(m['stats']),
      updatedAt:updatedAt,
      source:decodedSource,
      homeTeamId:_int(m['homeTeamId']),
      awayTeamId:_int(m['awayTeamId']),
    );
  }

  Match? _fromEvent(Map e) {
    final id=_int(e['id']) ?? 0;
    if (id == 0) return null;
    final h=_map(e['homeTeam']);
    final a=_map(e['awayTeam']);
    final t=_map(e['tournament']);
    final status=_map(e['status'])['type']?.toString() ?? 'notstarted';
    final ts=_int(e['startTimestamp']);
    final dt=ts==null?null:DateTime.fromMillisecondsSinceEpoch(ts*1000).toLocal();
    final live={'inprogress','halftime','extra_time','penalties','interrupted'}.contains(status);
    final finished={'finished','ended','afterextra','afterpenalties'}.contains(status);
    return Match(
      id:id,
      home:h['name']?.toString() ?? 'Home',
      away:a['name']?.toString() ?? 'Away',
      league:t['name']?.toString() ?? 'Football',
      time:dt==null?'--:--':'${dt.hour.toString().padLeft(2,'0')}:${dt.minute.toString().padLeft(2,'0')}',
      live:live,
      hs:_int(_map(e['homeScore'])['current']),
      ascore:_int(_map(e['awayScore'])['current']),
      status:live ? 'LIVE' : (finished ? 'FT' : 'NS'),
      confidence:0,
      pick:finished ? 'Partita terminata' : 'Dati live SofaScore',
      reason:finished ? 'Risultato aggiornato da SofaScore.' : 'Evento live ricevuto da SofaScore.',
      proposals:const [],
      preMatchStats:const [],
      stats:const {},
      updatedAt:'',
      source:'SofaScore',
      homeTeamId:_int(h['id']),
      awayTeamId:_int(a['id']),
    );
  }

  int? _int(dynamic v) {
    if (v is num) return v.toInt();
    return int.tryParse(v?.toString() ?? '');
  }

  Map<String,dynamic> _map(dynamic value) =>
      value is Map ? Map<String,dynamic>.from(value) : <String,dynamic>{};
}

class Dashboard extends StatefulWidget { const Dashboard({super.key}); @override State<Dashboard> createState()=>_DashboardState(); }
class _DashboardState extends State<Dashboard> with SingleTickerProviderStateMixin {
  final service=MatchService();
  late final AnimationController pulse=AnimationController(vsync:this,duration:const Duration(seconds:3))..repeat(reverse:true);
  List<Match> matches=[]; List<Match> calendarMatches=[]; bool loading=true; bool calendarLoading=true; String? error; int tab=0; Timer? refreshTimer;
  @override void initState(){super.initState();load(); refreshTimer=Timer.periodic(const Duration(minutes:1), (_) => load());}
  @override void dispose(){refreshTimer?.cancel(); pulse.dispose(); super.dispose();}
  Future<void> load() async {
    if(mounted)setState(()=>loading=true);
    try{
      final results=await Future.wait([service.today(),service.calendar()]);
      if(!mounted)return;
      globalCalendarMatches=results[1]; setState(() { matches=results[0]; calendarMatches=results[1]; error=null; });
    }catch(_){if(!mounted)return;setState(()=>error=null);}
    finally{if(mounted)setState(()=>loading=false);}
  }
  @override Widget build(BuildContext context){
    bool marketSignal(Match m)=>m.proposals.isNotEmpty && m.proposals.every((p)=>p.contains('(market signal)')); bool conflictSignal(Match m)=>m.proposals.isNotEmpty && m.proposals.every((p)=>p.contains('Conflitto evidenze')); final upcomingFeed=matches.isNotEmpty && matches.any((m)=>m.status=='NS' && m.time.contains('|')); final aiSignals=matches.where((m)=>m.status=='NS' && m.proposals.isNotEmpty && m.confidence>=60 && !marketSignal(m) && !conflictSignal(m)).toList()..sort((a,b)=>b.confidence.compareTo(a.confidence)); final marketSignals=matches.where((m)=>m.status=='NS' && marketSignal(m)).toList()..sort((a,b)=>b.confidence.compareTo(a.confidence)); final strong=aiSignals.where((m)=>m.confidence>=80).toList(); final top=strong.take(6).toList(); final medium=aiSignals.where((m)=>m.confidence<80).take(6).toList();
    return Scaffold(
      body: Stack(children:[
        const _Background(),
        SafeArea(child:Column(children:[
          Padding(padding:const EdgeInsets.fromLTRB(18,14,18,8),child:Row(children:[
            Container(width:42,height:42,decoration:BoxDecoration(gradient:const LinearGradient(colors:[Color(0xFF8B7CFF),Color(0xFF3AD8FF)]),borderRadius:BorderRadius.circular(14)),child:const Icon(Icons.auto_awesome,color:Colors.white)),
            const SizedBox(width:12),
            const Expanded(child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[Text('MATCH AI PRO',style:TextStyle(fontWeight:FontWeight.w900,fontSize:18,letterSpacing:.5)),Text('AI FOOTBALL INTELLIGENCE',style:TextStyle(fontSize:9,color:Color(0xFF9299AD),letterSpacing:1.3))])),
            IconButton(onPressed:load,icon:const Icon(Icons.refresh_rounded,color:Color(0xFFAAA1FF)))
          ])),
          Expanded(child: loading ? const Center(child:CircularProgressIndicator()) : IndexedStack(index:tab,children:[
            _home(top, medium, aiSignals, strong, marketSignals, upcomingFeed),
            _calendar(),
            _all(upcomingFeed),
            _ai(aiSignals, strong, marketSignals, upcomingFeed),
          ])),
          _nav(),
        ]))
      ])
    );
  }
  Widget _home(List<Match> top, List<Match> medium, List<Match> signals, List<Match> strong, List<Match> marketSignals, bool upcomingFeed)=>ListView(padding:const EdgeInsets.fromLTRB(16,8,16,20),children:[
    if(matches.isEmpty && calendarMatches.isNotEmpty) _upcomingHome(),
    if(matches.isNotEmpty) AnimatedBuilder(animation:pulse,builder:(_,__)=>Container(
      padding:const EdgeInsets.all(20),decoration:BoxDecoration(
        borderRadius:BorderRadius.circular(28),
        gradient:LinearGradient(colors:[const Color(0xFF171A30).withValues(alpha:.96),const Color(0xFF0E1525).withValues(alpha:.96)]),
        border:Border.all(color:const Color(0xFF8B7CFF).withValues(alpha:.22)),
        boxShadow:[BoxShadow(color:const Color(0xFF8B7CFF).withValues(alpha:.08+pulse.value*.08),blurRadius:35,spreadRadius:2)]
      ),
      child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
        const Text('AI SCANNER',style:TextStyle(color:Color(0xFFA9A0FF),fontSize:10,fontWeight:FontWeight.w900,letterSpacing:2)),
        const SizedBox(height:7),Text(upcomingFeed?'Le migliori prossime\npartite.':'Le migliori partite\ndi oggi.',style:const TextStyle(fontSize:30,fontWeight:FontWeight.w900,height:1.02)),
        const SizedBox(height:8),Text('${matches.length} partite · ${signals.length} proposte IA · ${marketSignals.length} mercato · ${strong.length} forti · ${matches.isEmpty ? '—' : matches.first.source}',style:const TextStyle(color:Color(0xFF9299AD),fontSize:12)),
        const SizedBox(height:18),Row(children:[
          _orb(top.isNotEmpty ? top.first.confidence : (medium.isNotEmpty ? medium.first.confidence : 0)),
          const SizedBox(width:16),Expanded(child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
            Text(top.isNotEmpty ? 'TOP AI SIGNAL' : (medium.isNotEmpty ? 'TOP AI SIGNAL' : (marketSignals.isNotEmpty ? 'TOP MARKET SIGNAL' : 'TOP SIGNAL')),style:const TextStyle(color:Color(0xFF42E89A),fontSize:11,fontWeight:FontWeight.w900)),
            const SizedBox(height:5),Text(top.isNotEmpty ? top.first.home : (medium.isNotEmpty ? medium.first.home : (marketSignals.isNotEmpty ? marketSignals.first.home : 'Feed disponibile')),style:const TextStyle(fontSize:18,fontWeight:FontWeight.w900)),
            Text(top.isNotEmpty ? top.first.away : (medium.isNotEmpty ? medium.first.away : (marketSignals.isNotEmpty ? marketSignals.first.away : 'Nessuna proposta disponibile')),style:const TextStyle(fontSize:12,color:Color(0xFFB4BAC8))),
          ]))
        ])
      ])
    )),
    _title('🔥 Proposte IA',upcomingFeed?'Analisi delle prossime partite':'Selezione multi-fonte'),
    ..._leagueSections(top, _card),
    if(top.isEmpty && medium.isNotEmpty) ...[
      _title('📊 Segnali monitorati','Confidenza media · non forti'),
      ..._leagueSections(medium, _card),
    ],
    if(top.isEmpty && medium.isEmpty && matches.isNotEmpty) _empty('Nessuna proposta IA forte','Il motore ha solo segnali di mercato o conflitti di evidenza; non li presenta come previsione IA.'),
    if(marketSignals.isNotEmpty) ...[
      _title('📈 Segnali mercato','Separati dalle proposte IA'),
      ..._leagueSections(marketSignals.take(3).toList(), _card),
    ],
    if(matches.isEmpty && calendarMatches.isEmpty) _empty('Feed in aggiornamento','Riprova tra poco: il calendario e il feed vengono aggiornati automaticamente.')
  ]);
  Widget _upcomingHome()=>Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
    const Text('Prossime partite selezionate',style:TextStyle(fontSize:30,fontWeight:FontWeight.w900,height:1.05)),
    const SizedBox(height:7),
    const Text('Il feed di oggi è vuoto: ecco i prossimi incontri dei campionati che hai scelto.',style:TextStyle(color:Color(0xFF9299AD),fontSize:12)),
    const SizedBox(height:14),
    ...calendarMatches.take(6).map(_calendarCard),
  ]);
  Widget _calendarCard(Match m){
    final parts=m.time.split('|');
    final date=parts.length>1 ? parts.first : '';
    final time=parts.length>1 ? parts.last : m.time;
    return Container(margin:const EdgeInsets.only(bottom:10),padding:const EdgeInsets.all(15),decoration:BoxDecoration(color:const Color(0xD9121724),borderRadius:BorderRadius.circular(20),border:Border.all(color:Colors.white10)),child:Row(children:[
      SizedBox(width:70,child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
        if(date.isNotEmpty) Text(date,style:const TextStyle(color:Color(0xFF9B92FF),fontSize:10,fontWeight:FontWeight.w800)),
        const SizedBox(height:3),
        Text(time,style:const TextStyle(color:Color(0xFFA9A0FF),fontSize:14,fontWeight:FontWeight.w900)),
      ])),
      Expanded(child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
        Text(m.league.toUpperCase(),style:const TextStyle(fontSize:8,color:Color(0xFF858DA0),letterSpacing:.8,fontWeight:FontWeight.w800)),
        const SizedBox(height:4),Text(m.home,style:const TextStyle(fontWeight:FontWeight.w800)),Text(m.away,style:const TextStyle(fontWeight:FontWeight.w800)),
      ])),
    ]));
  }
  Widget _all(bool upcomingFeed)=>ListView(padding:const EdgeInsets.fromLTRB(16,8,16,20),children:[
    _title(upcomingFeed?'Prossime partite':'Partite di oggi',matches.isEmpty?'Nessuna partita selezionata oggi':'Feed ${matches.first.source} · refresh automatico'),
    if(matches.isNotEmpty) ..._leagueSections(matches, _card),
    if(matches.isEmpty && calendarMatches.isNotEmpty) ...[
      _title('Prossime partite','Calendario selezionato'),
      ..._leagueSections(calendarMatches.take(20).toList(), _calendarCard),
    ],
  ]);
  Widget _ai(List<Match> signals, List<Match> strong, List<Match> marketSignals, bool upcomingFeed){
    final total=matches.length;
    final withData=matches.where((m)=>m.stats.isNotEmpty || m.preMatchStats.isNotEmpty).length;
    final updated=matches.isEmpty?null:DateTime.tryParse(matches.first.updatedAt)?.toLocal();
    final age=updated==null?999:DateTime.now().difference(updated).inMinutes.abs();
    final freshness=age<=15?1.0:(age<=60 ? .9 : .65);
    final source=matches.isEmpty?'Feed':matches.first.source;
    return ListView(padding:const EdgeInsets.fromLTRB(16,8,16,20),children:[
      _title('AI CENTER',upcomingFeed?'Analisi prossime partite':'Analisi e qualità dati'),
      Container(padding:const EdgeInsets.all(18),decoration:BoxDecoration(color:const Color(0xCC121725),borderRadius:BorderRadius.circular(22),border:Border.all(color:Colors.white10)),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
        Row(children:[const Icon(Icons.psychology_alt_rounded,color:Color(0xFF9D91FF),size:28),const SizedBox(width:10),Text(source.toUpperCase().contains('ESPN')?'Motore decisionale + multi-fonte':'Motore decisionale',style:const TextStyle(fontSize:18,fontWeight:FontWeight.w900))]),
        const SizedBox(height:14),
        _metric('Proposte IA',total==0?0:signals.length/total),
        _metric('Dati partita',total==0?0:withData/total),
        _metric('Feed aggiornato',freshness),
        const SizedBox(height:12),
        Text(marketSignals.isNotEmpty?'I segnali di mercato sono mostrati separatamente. Le proposte IA richiedono evidenze statistiche/forma e non vengono confuse con quote di mercato.':'Le proposte combinano dati disponibili, forma recente e mercato quando presente. Nessuna previsione è una garanzia di risultato.',style:const TextStyle(color:Color(0xFF9299AD),fontSize:11,height:1.4))
      ])),
      _title(strong.isNotEmpty?'⭐ Alta confidenza':'📊 Segnali migliori',strong.isNotEmpty?'Selezioni con evidenza forte':'Segnali disponibili · confidenza non forte'),
      if(strong.isNotEmpty) ..._leagueSections(strong, _card) else ..._leagueSections(signals.take(6).toList(), _card),
      if(marketSignals.isNotEmpty) ...[
        _title('📈 Segnali mercato','Non classificati come IA forte'),
        ..._leagueSections(marketSignals.take(4).toList(), _card),
      ],
      if(matches.isEmpty && calendarMatches.isNotEmpty) ...[
        _title('📅 Prossime analisi','Partite selezionate'),
        _empty('Nessuna proposta per oggi','Il motore aspetta dati statistici sufficienti. Le prossime partite sono già nel calendario e verranno analizzate quando il feed sarà disponibile.'),
        ...calendarMatches.take(8).map(_calendarCard),
      ],
    ]);
  }
  List<Widget> _leagueSections(List<Match> items, Widget Function(Match) builder){
    final groups=<String,List<Match>>{};
    for(final m in items){ groups.putIfAbsent(m.league,()=>[]).add(m); }
    final leagues=groups.keys.toList()..sort();
    final out=<Widget>[];
    for(final league in leagues){
      out.add(Padding(padding:const EdgeInsets.fromLTRB(2,12,2,7),child:Row(children:[
        const Icon(Icons.emoji_events_rounded,size:15,color:Color(0xFFA9A0FF)),
        const SizedBox(width:7),
        Expanded(child:Text(league.toUpperCase(),style:const TextStyle(fontSize:11,color:Color(0xFF9C96B8),fontWeight:FontWeight.w900,letterSpacing:.7))),
        Text(groups[league]!.length.toString()+' partite',style:const TextStyle(fontSize:9,color:Color(0xFF6F7687))),
      ])));
      out.addAll(groups[league]!.map(builder));
    }
    return out;
  }
  Widget _metric(String n,double v)=>Padding(padding:const EdgeInsets.only(bottom:11),child:Row(children:[Expanded(child:Text(n,style:const TextStyle(fontSize:12))),Text('${(v*100).round()}%',style:const TextStyle(fontWeight:FontWeight.w800,color:Color(0xFF42E89A)))]));
  Widget _title(String a,String b)=>Padding(padding:const EdgeInsets.fromLTRB(2,22,2,9),child:Row(children:[Expanded(child:Text(a,style:const TextStyle(fontSize:17,fontWeight:FontWeight.w900))),Text(b,style:const TextStyle(fontSize:9,color:Color(0xFF7E8598)))]));
  Widget _card(Match m){
    final parts=m.time.split('|');
    final displayDate=parts.length>1 ? parts.first : '';
    final displayTime=parts.length>1 ? parts.last : m.time;
    final headerTime=m.live ? 'LIVE' : (m.status=='FT' ? 'FT' : (displayDate.isNotEmpty ? '$displayDate $displayTime' : displayTime));
    final scoreText=m.status!='NS' && m.hs!=null && m.ascore!=null ? '${m.hs} - ${m.ascore}' : displayTime;
    return GestureDetector(
      onTap:()=>showModalBottomSheet(
        context:context,
        isScrollControlled:true,
        backgroundColor:const Color(0xFF0A0D17),
        builder:(_)=>_Detail(m),
      ),
      child:Container(
        margin:const EdgeInsets.only(bottom:10),
        padding:const EdgeInsets.all(15),
        decoration:BoxDecoration(
          color:const Color(0xD9121724),
          borderRadius:BorderRadius.circular(20),
          border:Border.all(color:Colors.white10),
        ),
        child:Column(
          children:[
            Row(
              children:[
                Expanded(
                  child:Text(
                    m.league.toUpperCase(),
                    style:const TextStyle(fontSize:9,color:Color(0xFF858DA0),letterSpacing:.8,fontWeight:FontWeight.w800),
                  ),
                ),
                Text(
                  headerTime,
                  style:TextStyle(
                    fontSize:10,
                    color:m.live?const Color(0xFFFF5D73):const Color(0xFFB8BECC),
                    fontWeight:FontWeight.w900,
                  ),
                ),
              ],
            ),
            const SizedBox(height:12),
            Row(
              children:[
                Expanded(
                  child:Text(m.home,style:const TextStyle(fontWeight:FontWeight.w800)),
                ),
                Column(
                  children:[
                    Text(scoreText,style:const TextStyle(fontSize:11,fontWeight:FontWeight.w900)),
                    const Text('VS',style:TextStyle(fontSize:8,color:Color(0xFF60687A))),
                  ],
                ),
                Expanded(
                  child:Text(
                    m.away,
                    textAlign:TextAlign.right,
                    style:const TextStyle(fontWeight:FontWeight.w800),
                  ),
                ),
              ],
            ),
            const SizedBox(height:12),
            Row(
              children:[
                Expanded(
                  child:Container(
                    padding:const EdgeInsets.symmetric(horizontal:12,vertical:10),
                    decoration:BoxDecoration(
                      color:m.proposals.isEmpty?const Color(0x121AA8D8):const Color(0x1242E89A),
                      borderRadius:BorderRadius.circular(13),
                      border:Border.all(
                        color:m.proposals.isEmpty?const Color(0x3039D9FF):const Color(0x3042E89A),
                      ),
                    ),
                    child:Text(
                      m.pick,
                      style:TextStyle(
                        color:m.proposals.isEmpty?const Color(0xFF7FDBFF):const Color(0xFF42E89A),
                        fontSize:12,
                        fontWeight:FontWeight.w900,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width:10),
                _confidence(m.confidence),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _confidence(int n){ final color=n>=80?const Color(0xFF42E89A):(n>=60?const Color(0xFFFFC857):const Color(0xFF8B7CFF)); return Container(width:52,height:52,decoration:BoxDecoration(shape:BoxShape.circle,border:Border.all(color:color,width:2)),child:Center(child:Column(mainAxisAlignment:MainAxisAlignment.center,children:[Text(n==0?'—':'$n',style:TextStyle(fontSize:12,fontWeight:FontWeight.w900,color:color)),Text(n==0?'INDEX':n>=80?'FORTE':n>=60?'MEDIA':'BASSA',style:TextStyle(fontSize:6,color:color,fontWeight:FontWeight.w800))]))); }
  Widget _orb(int n)=>Container(width:78,height:78,decoration:const BoxDecoration(shape:BoxShape.circle,gradient:SweepGradient(colors:[Color(0xFF8B7CFF),Color(0xFF39D9FF),Color(0xFF42E89A),Color(0xFF8B7CFF)])),child:Center(child:Container(width:64,height:64,decoration:const BoxDecoration(shape:BoxShape.circle,color:Color(0xFF0B0F1C)),child:Column(mainAxisAlignment:MainAxisAlignment.center,children:[Text(n==0?'—':'$n',style:const TextStyle(fontSize:18,fontWeight:FontWeight.w900)),const Text('AI INDEX',style:TextStyle(fontSize:7,color:Color(0xFF8D95A8)))]))));
  Widget _empty(String a,String b)=>Container(margin:const EdgeInsets.only(top:10),padding:const EdgeInsets.all(22),decoration:BoxDecoration(color:const Color(0xCC121725),borderRadius:BorderRadius.circular(20)),child:Column(children:[const Icon(Icons.shield_outlined,color:Color(0xFF8B7CFF),size:38),const SizedBox(height:9),Text(a,style:const TextStyle(fontWeight:FontWeight.w900)),const SizedBox(height:5),Text(b,textAlign:TextAlign.center,style:const TextStyle(color:Color(0xFF9299AD),fontSize:11))]));
  Widget _nav()=>Container(padding:const EdgeInsets.fromLTRB(6,7,6,7),decoration:BoxDecoration(color:const Color(0xE80A0D17),border:Border(top:BorderSide(color:Colors.white10))),child:Row(children:[_navButton(0,Icons.home_rounded,'Oggi'),_navButton(1,Icons.calendar_month_rounded,'Calendario'),_navButton(2,Icons.sports_soccer_rounded,'Partite'),_navButton(3,Icons.auto_awesome,'AI')]));

  Widget _navButton(int i,IconData icon,String label)=>Expanded(child:GestureDetector(onTap:()=>setState(()=>tab=i),child:Container(padding:const EdgeInsets.symmetric(vertical:8),decoration:BoxDecoration(color:tab==i?const Color(0x188B7CFF):Colors.transparent,borderRadius:BorderRadius.circular(14)),child:Column(children:[Icon(icon,size:20,color:tab==i?const Color(0xFFA9A0FF):const Color(0xFF6F7687)),const SizedBox(height:3),Text(label,style:TextStyle(fontSize:9,color:tab==i?const Color(0xFFA9A0FF):const Color(0xFF6F7687),fontWeight:FontWeight.w800))]))));

  Widget _calendar(){
    final groups=<String,List<Match>>{};
    for(final m in globalCalendarMatches){
      if(m.status=='FT') continue;
      final raw=m.time.split('|').first;
      if(!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(raw)) continue;
      groups.putIfAbsent(raw,()=>[]).add(m);
    }
    final days=groups.keys.toList()..sort();
    return ListView(padding:const EdgeInsets.fromLTRB(16,8,16,20),children:[
      const Text('Calendario',style:TextStyle(fontSize:26,fontWeight:FontWeight.w900)),
      const SizedBox(height:4),
      const Text('Prossime partite dei campionati selezionati',style:TextStyle(color:Color(0xFF9299AD),fontSize:12)),
      const SizedBox(height:4),
      const Text('Oggi + prossimi 14 giorni',style:TextStyle(color:Color(0xFF6F7687),fontSize:10)),
      const SizedBox(height:14),
      if(days.isEmpty) const Padding(padding:EdgeInsets.only(top:80),child:Center(child:Text('Nessuna prossima partita disponibile',style:TextStyle(fontWeight:FontWeight.w800)))),
      for(final day in days)...[
        Padding(padding:const EdgeInsets.only(top:14,bottom:8),child:Text(day,style:const TextStyle(color:Color(0xFFA9A0FF),fontWeight:FontWeight.w900))),
        ...groups[day]!.map((m){
          final parts=m.time.split('|');
          final time=parts.length>1 ? parts.last : m.time;
          return Container(margin:const EdgeInsets.only(bottom:8),padding:const EdgeInsets.all(14),decoration:BoxDecoration(color:const Color(0xFF0F1422),borderRadius:BorderRadius.circular(18)),child:Row(children:[
            SizedBox(width:60,child:Text(time,style:const TextStyle(color:Color(0xFFA9A0FF),fontWeight:FontWeight.w900))),
            Expanded(child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
              Text(m.league.toUpperCase(),style:const TextStyle(fontSize:8,color:Color(0xFF7F879B),fontWeight:FontWeight.w800)),
              const SizedBox(height:4),Text(m.home,style:const TextStyle(fontWeight:FontWeight.w800)),Text(m.away,style:const TextStyle(fontWeight:FontWeight.w800))
            ]))
          ]));
        })
      ]
    ]);
  }
}

class _Detail extends StatefulWidget {
  final Match m;
  const _Detail(this.m);
  @override State<_Detail> createState()=>_DetailState();
}

class _DetailState extends State<_Detail> {
  bool loadingStats=true;
  Map<String,dynamic> detailStats={};
  String statsSource='';

  @override void initState(){ super.initState(); _loadStats(); }

  Future<void> _loadStats() async {
    if(mounted)setState(()=>loadingStats=true);
    var result=await _fetchStats(widget.m);
    if((result['stats'] is! Map || (result['stats'] as Map).isEmpty) && widget.m.status=='NS'){
      result=await _fetchHistoricalStats(widget.m);
    }
    if(!mounted)return;
    setState((){
      detailStats=result['stats'] is Map ? Map<String,dynamic>.from(result['stats']) : <String,dynamic>{};
      statsSource=result['source']?.toString()??'';
      loadingStats=false;
    });
  }

  Future<Map<String,dynamic>> _fetchHistoricalStats(Match m) async {
    final stats=<String,dynamic>{};
    const slugs=<String,String>{
      'premier league':'eng.1','championship':'eng.2','league one':'eng.3','league two':'eng.4','national league':'eng.5',
      'serie a':'ita.1','serie b':'ita.2','la liga':'esp.1','segunda':'esp.2','ligue 1':'fra.1','ligue 2':'fra.2',
      'eredivisie':'ned.1','turkish super lig':'tur.1','bundesliga':'ger.1','2. bundesliga':'ger.2',
      'uefa champions league':'uefa.champions','uefa europa league':'uefa.europa','uefa conference league':'uefa.europa.conf',
    };
    final slug=slugs[m.league.toLowerCase().trim()]??'';
    if(slug.isEmpty || m.homeTeamId==null || m.awayTeamId==null)return {'stats':stats,'source':''};

    Future<List<int>> recentIds(int teamId) async {
      try{
        final url='https://site.api.espn.com/apis/site/v2/sports/soccer/'+slug+'/teams/'+teamId.toString()+'/schedule?limit=10';
        final res=await http.get(Uri.parse(url),headers:const {'Accept':'application/json'}).timeout(const Duration(seconds:10));
        if(res.statusCode!=200)return <int>[];
        final data=jsonDecode(res.body);
        final events=data is Map ? data['events'] : null;
        if(events is! List)return <int>[];
        final rows=<Map<String,dynamic>>[];
        for(final e in events){
          if(e is! Map)continue;
          final id=int.tryParse(e['id']?.toString()??'');
          final type=e['status'] is Map ? e['status']['type'] : null;
          final state=type is Map ? type['state'].toString().toLowerCase() : '';
          final completed=type is Map && (type['completed']==true || state=='post' || state=='final');
          if(id!=null && id!=m.id && completed)rows.add({'id':id,'date':e['date']??''});
        }
        rows.sort((a,b)=>b['date'].toString().compareTo(a['date'].toString()));
        return rows.take(5).map((e)=>e['id'] as int).toList();
      }catch(_){ return <int>[]; }
    }

    Future<Map<String,double>> oneGame(int eventId,int teamId) async {
      final out=<String,double>{};
      try{
        final url='https://site.api.espn.com/apis/site/v2/sports/soccer/'+slug+'/summary?event='+eventId.toString();
        final res=await http.get(Uri.parse(url),headers:const {'Accept':'application/json'}).timeout(const Duration(seconds:10));
        if(res.statusCode!=200)return out;
        final data=jsonDecode(res.body);
        final box=data is Map ? data['boxscore'] : null;
        final teams=box is Map ? box['teams'] : null;
        if(teams is! List)return out;
        for(final team in teams){
          if(team is! Map)continue;
          final teamObj=team['team'];
          final id=int.tryParse((teamObj is Map ? teamObj['id'] : null)?.toString()??'');
          if(id!=teamId)continue;
          final list=team['statistics'] is List ? team['statistics'] as List : const [];
          for(final item in list){
            if(item is! Map)continue;
            final key=(item['name']??'').toString().toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'),'');
            final raw=(item['displayValue']??item['value'])?.toString()??'';
            final number=double.tryParse(raw.replaceAll('%','').replaceAll(',','.'));
            if(number==null)continue;
            if(key=='shots' || key.contains('totalshots'))out['shots']=number;
            else if(key.contains('shotsontarget'))out['on']=number;
            else if(key.contains('corner'))out['corners']=number;
            else if(key.contains('foul'))out['fouls']=number;
            else if(key.contains('throw'))out['throw']=number;
            else if(key.contains('save'))out['saves']=number;
            else if(key.contains('yellow'))out['yellow']=number;
            else if(key.contains('red'))out['red']=number;
            else if(key.contains('possession'))out['possession']=number;
          }
        }
      }catch(_){ }
      return out;
    }

    final homeIds=await recentIds(m.homeTeamId!);
    final awayIds=await recentIds(m.awayTeamId!);
    final jobs=<Future<Map<String,double>>>[];
    for(final id in homeIds)jobs.add(oneGame(id,m.homeTeamId!));
    for(final id in awayIds)jobs.add(oneGame(id,m.awayTeamId!));
    final rows=await Future.wait(jobs);
    final homeRows=rows.take(homeIds.length).where((x)=>x.isNotEmpty).toList();
    final awayRows=rows.skip(homeIds.length).where((x)=>x.isNotEmpty).toList();
    void average(List<Map<String,double>> input,String prefix){
      for(final key in const ['shots','on','corners','fouls','throw','saves','yellow','red','possession']){
        final values=input.map((x)=>x[key]).whereType<double>().toList();
        if(values.isEmpty)continue;
        final avg=values.reduce((a,b)=>a+b)/values.length;
        stats[prefix+key[0].toUpperCase()+key.substring(1)]=double.parse(avg.toStringAsFixed(1));
      }
    }
    average(homeRows,'home');
    average(awayRows,'away');
    final games=homeRows.length<awayRows.length?homeRows.length:awayRows.length;
    if(stats.isEmpty)return {'stats':stats,'source':''};
    return {'stats':stats,'source':'ESPN · medie ultime '+games.toString()+' gare'};
  }
  Future<Map<String,dynamic>> _fetchStats(Match m) async {
    final stats=<String,dynamic>{};
    var source='';
    final map=<String,String>{
      'premier league':'eng.1','championship':'eng.2','league one':'eng.3','league two':'eng.4','national league':'eng.5',
      'serie a':'ita.1','serie b':'ita.2','la liga':'esp.1','segunda':'esp.2','ligue 1':'fra.1','ligue 2':'fra.2',
      'eredivisie':'ned.1','turkish super lig':'tur.1','bundesliga':'ger.1','2. bundesliga':'ger.2',
      'uefa champions league':'uefa.champions','uefa europa league':'uefa.europa','uefa conference league':'uefa.europa.conf',
    };
    if(m.source.toUpperCase().contains('ESPN')){
      final slug=map[m.league.toLowerCase().trim()]??'';
      if(slug.isNotEmpty){
        try{
          final url='https://site.api.espn.com/apis/site/v2/sports/soccer/'+slug+'/summary?event='+m.id.toString();
          final res=await http.get(Uri.parse(url),headers:const {'Accept':'application/json'}).timeout(const Duration(seconds:12));
          if(res.statusCode==200){
            final data=jsonDecode(res.body);
            final box=data is Map ? data['boxscore'] : null;
            final teams=box is Map ? box['teams'] : null;
            if(teams is List){
              for(final t in teams){
                if(t is! Map)continue;
                final side=t['homeAway']?.toString();
                final prefix=side=='home'?'home':'away';
                final list=t['statistics'] is List ? t['statistics'] as List : const [];
                for(final item in list){
                  if(item is! Map)continue;
                  final key=(item['name']??'').toString().toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'),'');
                  final value=item['displayValue']??item['value'];
                  if(key.contains('shotsontarget'))stats[prefix+'On']=value;
                  else if(key=='shots' || key.contains('totalshots'))stats[prefix+'Shots']=value;
                  else if(key.contains('corner'))stats[prefix+'Corners']=value;
                  else if(key.contains('foul'))stats[prefix+'Fouls']=value;
                  else if(key.contains('throw'))stats[prefix+'Throw']=value;
                  else if(key.contains('save'))stats[prefix+'Saves']=value;
                  else if(key.contains('yellow'))stats[prefix+'Yellow']=value;
                  else if(key.contains('red'))stats[prefix+'Red']=value;
                  else if(key.contains('possession'))stats[prefix+'Possession']=value;
                }
              }
              if(stats.isNotEmpty)source='ESPN';
            }
          }
        }catch(_){ }
      }
    }
    if(m.source.toUpperCase().contains('SOFASCORE') && m.id>0){
      for(final base in const ['https://api.sofascore.app/api/v1/event/','https://www.sofascore.com/api/v1/event/']){
        try{
          final res=await http.get(Uri.parse(base+m.id.toString()+'/statistics'),headers:const {'Accept':'application/json'}).timeout(const Duration(seconds:12));
          if(res.statusCode!=200)continue;
          final data=jsonDecode(res.body);
          final periods=data is Map ? data['statistics'] : null;
          if(periods is! List)continue;
          Map? all;
          for(final p in periods){ if(p is Map && p['period']=='ALL'){ all=p; break; } }
          if(all==null)continue;
          final items=<Map>[];
          final groups=all['groups'];
          if(groups is List){ for(final g in groups){ if(g is Map && g['statisticsItems'] is List){ items.addAll((g['statisticsItems'] as List).whereType<Map>()); } } }
          int? val(Map item,String side){ final raw=item[side+'Value']??item[side]; return raw is num ? raw.toInt() : int.tryParse(raw?.toString()??''); }
          void pair(Set<String> names,String h,String a){
            for(final item in items){
              final key=(item['key']??'').toString().toLowerCase();
              final name=(item['name']??'').toString().toLowerCase();
              if(names.any((n)=>key==n || name==n || key.contains(n) || name.contains(n))){
                final hv=val(item,'home'); final av=val(item,'away');
                if(hv!=null && av!=null){stats[h]=hv;stats[a]=av;}
                break;
              }
            }
          }
          pair({'totalshots','total shots','shots'},'homeShots','awayShots');
          pair({'shotsontarget','shots on target','shotsongoal'},'homeOn','awayOn');
          pair({'cornerkicks','corner kicks','corners'},'homeCorners','awayCorners');
          pair({'fouls'},'homeFouls','awayFouls');
          pair({'throwins','throw-ins','throw ins'},'homeThrow','awayThrow');
          pair({'goalkeepersaves','goalkeeper saves','saves'},'homeSaves','awaySaves');
          pair({'yellowcards','yellow cards'},'homeYellow','awayYellow');
          pair({'redcards','red cards'},'homeRed','awayRed');
          if(stats.isNotEmpty)source=source.isEmpty?'SofaScore':source+' + SofaScore';
          break;
        }catch(_){ }
      }
    }
    return {'stats':stats,'source':source};
  }

  @override Widget build(BuildContext context){
    final m=widget.m;
    return DraggableScrollableSheet(expand:false,initialChildSize:.88,minChildSize:.60,maxChildSize:.96,builder:(_,controller)=>ListView(controller:controller,padding:const EdgeInsets.fromLTRB(18,12,18,28),children:[
      Center(child:Container(width:40,height:4,decoration:BoxDecoration(color:Colors.white24,borderRadius:BorderRadius.circular(8)))),
      const SizedBox(height:18),
      Text(m.league.toUpperCase(),textAlign:TextAlign.center,style:const TextStyle(fontSize:9,color:Color(0xFF8B93A5),letterSpacing:1.2)),
      const SizedBox(height:8),
      Text(m.home+'  vs  '+m.away,textAlign:TextAlign.center,style:const TextStyle(fontSize:20,fontWeight:FontWeight.w900)),
      const SizedBox(height:5),
      Text(m.status=='NS' ? m.time.replaceAll('|',' ')+' · PRE-MATCH' : (m.live?'LIVE · dati in aggiornamento':'PARTITA TERMINATA'),textAlign:TextAlign.center,style:const TextStyle(color:Color(0xFF9A95B4),fontSize:10,fontWeight:FontWeight.w800)),
      const SizedBox(height:16),
      Row(children:[Expanded(child:_scoreBox(m.home,m.hs)),const Padding(padding:EdgeInsets.symmetric(horizontal:8),child:Text('VS',style:TextStyle(color:Color(0xFF60687A),fontWeight:FontWeight.w900))),Expanded(child:_scoreBox(m.away,m.ascore))]),
      const SizedBox(height:18),
      Row(children:[Expanded(child:Text(m.status=='NS'?'STATISTICHE PRE-MATCH':'STATISTICHE',style:const TextStyle(color:Color(0xFFA9A0FF),fontSize:11,fontWeight:FontWeight.w900,letterSpacing:1))),IconButton(onPressed:loadingStats?null:_loadStats,icon:Icon(Icons.refresh_rounded,color:loadingStats?const Color(0xFF555C70):const Color(0xFFA9A0FF)))]),
      if(loadingStats)const Padding(padding:EdgeInsets.symmetric(vertical:24),child:Center(child:CircularProgressIndicator())),
      if(!loadingStats && detailStats.isNotEmpty)..._statGrid(detailStats),
      if(!loadingStats && detailStats.isEmpty)_emptyStats(m.status=='NS'?'Nessun dato storico dettagliato disponibile dalla fonte corrente.':'La fonte corrente non ha restituito statistiche dettagliate.'),
      if(!loadingStats && detailStats.isNotEmpty && m.status=='NS')const Padding(padding:EdgeInsets.only(top:4,bottom:6),child:Text('Medie delle ultime gare · non sono i dati della partita in programma.',style:TextStyle(color:Color(0xFF7F879A),fontSize:9))),
      if(statsSource.isNotEmpty)Padding(padding:const EdgeInsets.only(top:6),child:Text('Fonte: '+statsSource,style:const TextStyle(color:Color(0xFF6F7687),fontSize:9))),
      if(m.preMatchStats.isNotEmpty)...[
        const SizedBox(height:18),
        const Text('DATI PRE-MATCH',style:TextStyle(color:Color(0xFF7F879A),fontSize:9,fontWeight:FontWeight.w900,letterSpacing:1)),
        const SizedBox(height:8),
        ...m.preMatchStats.map((s)=>Padding(padding:const EdgeInsets.only(bottom:6),child:Text(s,style:const TextStyle(color:Color(0xFFB4BAC8),fontSize:11,height:1.3)))),
      ],
      if(m.proposals.isNotEmpty)...[
        const SizedBox(height:16),
        const Text('PROPOSTA IA',style:TextStyle(color:Color(0xFF42E89A),fontSize:9,fontWeight:FontWeight.w900,letterSpacing:1)),
        const SizedBox(height:8),
        Container(padding:const EdgeInsets.all(14),decoration:BoxDecoration(color:const Color(0x1242E89A),borderRadius:BorderRadius.circular(14),border:Border.all(color:const Color(0x3042E89A))),child:Text(m.pick,style:const TextStyle(color:Color(0xFF42E89A),fontWeight:FontWeight.w900))),
      ],
      const SizedBox(height:12),
      Text('Nota: il punteggio è un indicatore statistico e non rappresenta una garanzia di risultato.',style:const TextStyle(color:Color(0xFF737B8E),fontSize:10,height:1.4)),
    ]));
  }

  Widget _scoreBox(String team,int? score)=>Container(padding:const EdgeInsets.all(14),decoration:BoxDecoration(color:const Color(0xFF121725),borderRadius:BorderRadius.circular(16)),child:Column(children:[Text(score==null?'—':'$score',style:const TextStyle(fontSize:25,fontWeight:FontWeight.w900)),Text(team,overflow:TextOverflow.ellipsis,style:const TextStyle(fontSize:10,color:Color(0xFF9299AD)))]));

  List<Widget> _statGrid(Map<String,dynamic> s){
    Widget cell(String label,String h,String a){
      if(!s.containsKey(h) || !s.containsKey(a))return const SizedBox.shrink();
      return Container(margin:const EdgeInsets.only(bottom:9),padding:const EdgeInsets.all(12),decoration:BoxDecoration(color:const Color(0xFF121725),borderRadius:BorderRadius.circular(14),border:Border.all(color:Colors.white10)),child:Column(children:[
        Row(children:[Expanded(child:Text(s[h].toString(),textAlign:TextAlign.center,style:const TextStyle(fontSize:17,fontWeight:FontWeight.w900))),Expanded(child:Text(s[a].toString(),textAlign:TextAlign.center,style:const TextStyle(fontSize:17,fontWeight:FontWeight.w900)))]),
        const SizedBox(height:5),Text(label,style:const TextStyle(color:Color(0xFF80889B),fontSize:9,fontWeight:FontWeight.w800)),
      ]));
    }
    return [cell('TIRI','homeShots','awayShots'),cell('TIRI IN PORTA','homeOn','awayOn'),cell('ANGOLI','homeCorners','awayCorners'),cell('FALLI','homeFouls','awayFouls'),cell('RIMESSE LATERALI','homeThrow','awayThrow'),cell('PARATE','homeSaves','awaySaves'),cell('CARTELLINI GIALLI','homeYellow','awayYellow'),cell('CARTELLINI ROSSI','homeRed','awayRed'),cell('POSSESSO','homePossession','awayPossession')].where((w)=>w is! SizedBox).toList();
  }

  Widget _emptyStats(String message)=>Container(padding:const EdgeInsets.all(16),decoration:BoxDecoration(color:const Color(0xFF121725),borderRadius:BorderRadius.circular(16)),child:Row(children:[const Icon(Icons.insights_rounded,color:Color(0xFF8B7CFF)),const SizedBox(width:10),Expanded(child:Text(message,style:const TextStyle(color:Color(0xFF9299AD),fontSize:11,height:1.4)))]));
}
class _Background extends StatelessWidget { const _Background(); @override Widget build(BuildContext c)=>IgnorePointer(child:Stack(children:[
  Positioned(top:-100,right:-80,child:Container(width:300,height:300,decoration:BoxDecoration(shape:BoxShape.circle,color:const Color(0xFF5545C9).withValues(alpha:.10),boxShadow:[BoxShadow(color:const Color(0xFF8B7CFF).withValues(alpha:.12),blurRadius:90,spreadRadius:25)]))),
  Positioned(bottom:80,left:-100,child:Container(width:260,height:260,decoration:BoxDecoration(shape:BoxShape.circle,color:const Color(0xFF1AA8D8).withValues(alpha:.07),boxShadow:[BoxShadow(color:const Color(0xFF39D9FF).withValues(alpha:.10),blurRadius:80,spreadRadius:20)]))),
]));}
