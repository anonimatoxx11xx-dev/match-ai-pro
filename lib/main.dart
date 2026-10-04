import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

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
  final int confidence;
  final String pick;
  final String reason;
  final List<String> proposals;
  final List<String> preMatchStats;
  final Map<String,dynamic> stats;
  final String updatedAt;
  Match({
    required this.id,
    required this.home,
    required this.away,
    required this.league,
    required this.time,
    required this.live,
    required this.hs,
    required this.ascore,
    required this.confidence,
    required this.pick,
    required this.reason,
    required this.proposals,
    required this.preMatchStats,
    required this.stats,
    required this.updatedAt,
  });
}

class MatchService {
  static const _feedUrl = 'https://raw.githubusercontent.com/anonimatoxx11xx-dev/match-ai-pro/main/data/latest.json';

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
        if (matches.isNotEmpty) return matches;
        errors.add('$url -> feed vuoto');
      } catch (e) {
        errors.add('$url -> ${e.runtimeType}');
      }
    }

    try {
      final local = await rootBundle.loadString('data/latest.json');
      final matches = _parsePayload(jsonDecode(local));
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
      return rawMatches.whereType<Map>().map((m) => _fromFeed(m, updatedAt)).whereType<Match>().toList();
    }

    final events = decoded['events'];
    if (events is List) {
      return events.whereType<Map>().map((e) => _fromEvent(e)).whereType<Match>().toList();
    }
    return <Match>[];
  }

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
      confidence:confidence,
      pick:proposals.isNotEmpty ? proposals.first : 'Nessuna proposta forte',
      reason:pre.isNotEmpty ? pre.join(' • ') : (proposals.isNotEmpty ? 'Proposta disponibile nel feed statistico.' : 'Dati insufficienti per una selezione affidabile.'),
      proposals:proposals,
      preMatchStats:pre,
      stats:_map(m['stats']),
      updatedAt:updatedAt,
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
      confidence:0,
      pick:finished ? 'Partita terminata' : 'Dati live SofaScore',
      reason:finished ? 'Risultato aggiornato da SofaScore.' : 'Evento live ricevuto da SofaScore.',
      proposals:const [],
      preMatchStats:const [],
      stats:const {},
      updatedAt:'',
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
  List<Match> matches=[]; bool loading=true; String? error; int tab=0;
  @override void initState(){super.initState();load();}
  @override void dispose(){pulse.dispose();super.dispose();}
  Future<void> load() async { if(mounted)setState(()=>loading=true); try{final m=await service.today(); if(!mounted)return; setState((){matches=m;error=null;});}catch(_){ if(!mounted)return; setState(()=>error=null); }finally{if(mounted)setState(()=>loading=false);} }
  @override Widget build(BuildContext context){
    final strong=matches.where((m)=>m.proposals.isNotEmpty).toList()..sort((a,b)=>b.confidence.compareTo(a.confidence)); final top=strong.take(6).toList();
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
          Expanded(child: loading ? const Center(child:CircularProgressIndicator()) : matches.isEmpty ? _NoData(retry:load) : IndexedStack(index:tab,children:[
            _home(top),
            _all(),
            _ai(top),
          ])),
          _nav(),
        ]))
      ])
    );
  }
  Widget _home(List<Match> strong)=>ListView(padding:const EdgeInsets.fromLTRB(16,8,16,20),children:[
    AnimatedBuilder(animation:pulse,builder:(_,__)=>Container(
      padding:const EdgeInsets.all(20),decoration:BoxDecoration(
        borderRadius:BorderRadius.circular(28),
        gradient:LinearGradient(colors:[const Color(0xFF171A30).withOpacity(.96),const Color(0xFF0E1525).withOpacity(.96)]),
        border:Border.all(color:const Color(0xFF8B7CFF).withOpacity(.22)),
        boxShadow:[BoxShadow(color:const Color(0xFF8B7CFF).withOpacity(.08+pulse.value*.08),blurRadius:35,spreadRadius:2)]
      ),
      child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
        const Text('AI SCANNER',style:TextStyle(color:Color(0xFFA9A0FF),fontSize:10,fontWeight:FontWeight.w900,letterSpacing:2)),
        const SizedBox(height:7),const Text('Le migliori partite\ndi oggi.',style:TextStyle(fontSize:30,fontWeight:FontWeight.w900,height:1.02)),
        const SizedBox(height:8),Text('${matches.length} partite nel feed · ${strong.length} con proposta',style:const TextStyle(color:Color(0xFF9299AD),fontSize:12)),
        const SizedBox(height:18),Row(children:[
          _orb(strong.isEmpty?0:strong.first.confidence),
          const SizedBox(width:16),Expanded(child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
            const Text('TOP AI SIGNAL',style:TextStyle(color:Color(0xFF42E89A),fontSize:11,fontWeight:FontWeight.w900)),
            const SizedBox(height:5),Text(strong.isEmpty?'Feed disponibile':strong.first.home,style:const TextStyle(fontSize:18,fontWeight:FontWeight.w900)),
            Text(strong.isEmpty?'Nessuna proposta affidabile':strong.first.away,style:const TextStyle(fontSize:12,color:Color(0xFFB4BAC8))),
          ]))
        ])
      ])
    )),
    _title('🔥 Proposte IA','Solo match con proposta'),
    ...strong.map((m)=>_card(m)),
    if(strong.isEmpty) _empty('Nessuna proposta forte','Il sistema preferisce non forzare una selezione con dati insufficienti.')
  ]);
  Widget _all()=>ListView(padding:const EdgeInsets.fromLTRB(16,8,16,20),children:[
    _title('Partite di oggi','Feed SofaScore · refresh automatico'),...matches.map(_card)
  ]);
  Widget _ai(List<Match> strong)=>ListView(padding:const EdgeInsets.fromLTRB(16,8,16,20),children:[
    _title('AI CENTER','Analisi e qualità dati'),
    Container(padding:const EdgeInsets.all(18),decoration:BoxDecoration(color:const Color(0xCC121725),borderRadius:BorderRadius.circular(22),border:Border.all(color:Colors.white10)),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
      const Row(children:[Icon(Icons.psychology_alt_rounded,color:Color(0xFF9D91FF),size:28),SizedBox(width:10),Text('Motore decisionale',style:TextStyle(fontSize:18,fontWeight:FontWeight.w900))]),
      const SizedBox(height:14),_metric('Match con proposta',strong.isEmpty?0:1),_metric('Dati disponibili',matches.isEmpty?0:1),_metric('Feed aggiornato',.95),
      const SizedBox(height:12),const Text('Le proposte provengono dal feed statistico. Nessuna previsione è una garanzia di risultato.',style:TextStyle(color:Color(0xFF9299AD),fontSize:11,height:1.4))
    ])),
    _title('⭐ Alta confidenza','Le selezioni migliori'),...strong.map(_card)
  ]);
  Widget _metric(String n,double v)=>Padding(padding:const EdgeInsets.only(bottom:11),child:Row(children:[Expanded(child:Text(n,style:const TextStyle(fontSize:12))),Text('${(v*100).round()}%',style:const TextStyle(fontWeight:FontWeight.w800,color:Color(0xFF42E89A)))]));
  Widget _title(String a,String b)=>Padding(padding:const EdgeInsets.fromLTRB(2,22,2,9),child:Row(children:[Expanded(child:Text(a,style:const TextStyle(fontSize:17,fontWeight:FontWeight.w900))),Text(b,style:const TextStyle(fontSize:9,color:Color(0xFF7E8598)))]));
  Widget _card(Match m)=>GestureDetector(onTap:()=>showModalBottomSheet(context:context,isScrollControlled:true,backgroundColor:const Color(0xFF0A0D17),builder:(_)=>_Detail(m)),child:Container(margin:const EdgeInsets.only(bottom:10),padding:const EdgeInsets.all(15),decoration:BoxDecoration(color:const Color(0xD9121724),borderRadius:BorderRadius.circular(20),border:Border.all(color:Colors.white10)),child:Column(children:[
    Row(children:[Expanded(child:Text(m.league.toUpperCase(),style:const TextStyle(fontSize:9,color:Color(0xFF858DA0),letterSpacing:.8,fontWeight:FontWeight.w800))),Text(m.live?'LIVE':m.time,style:TextStyle(fontSize:10,color:m.live?const Color(0xFFFF5D73):const Color(0xFFB8BECC),fontWeight:FontWeight.w900))]),
    const SizedBox(height:12),Row(children:[Expanded(child:Text(m.home,style:const TextStyle(fontWeight:FontWeight.w800))),Column(children:[Text(m.hs!=null&&m.ascore!=null?'${m.hs} - ${m.ascore}':m.time,style:const TextStyle(fontSize:11,fontWeight:FontWeight.w900)),const Text('VS',style:TextStyle(fontSize:8,color:Color(0xFF60687A)))]),Expanded(child:Text(m.away,textAlign:TextAlign.right,style:const TextStyle(fontWeight:FontWeight.w800)))]),
    const SizedBox(height:12),Row(children:[Expanded(child:Container(padding:const EdgeInsets.symmetric(horizontal:12,vertical:10),decoration:BoxDecoration(color:const Color(0x1242E89A),borderRadius:BorderRadius.circular(13),border:Border.all(color:const Color(0x3042E89A))),child:Text(m.pick,style:const TextStyle(color:Color(0xFF42E89A),fontSize:12,fontWeight:FontWeight.w900)))),const SizedBox(width:10),_confidence(m.confidence)])
  ])));
  Widget _confidence(int n)=>Container(width:52,height:52,decoration:BoxDecoration(shape:BoxShape.circle,border:Border.all(color:const Color(0xFF8B7CFF),width:2)),child:Center(child:Column(mainAxisAlignment:MainAxisAlignment.center,children:[Text(n==0?'—':'$n',style:const TextStyle(fontSize:12,fontWeight:FontWeight.w900)),const Text('INDEX',style:TextStyle(fontSize:7,color:Color(0xFF82899B)))])));
  Widget _orb(int n)=>Container(width:78,height:78,decoration:const BoxDecoration(shape:BoxShape.circle,gradient:SweepGradient(colors:[Color(0xFF8B7CFF),Color(0xFF39D9FF),Color(0xFF42E89A),Color(0xFF8B7CFF)])),child:Center(child:Container(width:64,height:64,decoration:const BoxDecoration(shape:BoxShape.circle,color:Color(0xFF0B0F1C)),child:Column(mainAxisAlignment:MainAxisAlignment.center,children:[Text(n==0?'—':'$n',style:const TextStyle(fontSize:18,fontWeight:FontWeight.w900)),const Text('AI INDEX',style:TextStyle(fontSize:7,color:Color(0xFF8D95A8)))]))));
  Widget _empty(String a,String b)=>Container(margin:const EdgeInsets.only(top:10),padding:const EdgeInsets.all(22),decoration:BoxDecoration(color:const Color(0xCC121725),borderRadius:BorderRadius.circular(20)),child:Column(children:[const Icon(Icons.shield_outlined,color:Color(0xFF8B7CFF),size:38),const SizedBox(height:9),Text(a,style:const TextStyle(fontWeight:FontWeight.w900)),const SizedBox(height:5),Text(b,textAlign:TextAlign.center,style:const TextStyle(color:Color(0xFF9299AD),fontSize:11))]));
  Widget _nav()=>Container(padding:const EdgeInsets.fromLTRB(8,7,8,7),decoration:BoxDecoration(color:const Color(0xE80A0D17),border:Border(top:BorderSide(color:Colors.white10))),child:Row(children:[
    _navButton(0,Icons.home_rounded,'Oggi'),_navButton(1,Icons.sports_soccer_rounded,'Partite'),_navButton(2,Icons.auto_awesome,'AI')
  ]));
  Widget _navButton(int i,IconData icon,String label)=>Expanded(child:GestureDetector(onTap:()=>setState(()=>tab=i),child:Container(padding:const EdgeInsets.symmetric(vertical:8),decoration:BoxDecoration(color:tab==i?const Color(0x188B7CFF):Colors.transparent,borderRadius:BorderRadius.circular(14)),child:Column(children:[Icon(icon,size:20,color:tab==i?const Color(0xFFA9A0FF):const Color(0xFF6F7687)),const SizedBox(height:3),Text(label,style:TextStyle(fontSize:9,color:tab==i?const Color(0xFFA9A0FF):const Color(0xFF6F7687),fontWeight:FontWeight.w800))]))));
}

class _Detail extends StatelessWidget {
  final Match m; const _Detail(this.m);
  @override Widget build(BuildContext context)=>DraggableScrollableSheet(expand:false,initialChildSize:.78,minChildSize:.55,maxChildSize:.94,builder:(_,c)=>ListView(controller:c,padding:const EdgeInsets.fromLTRB(18,12,18,28),children:[
    Center(child:Container(width:40,height:4,decoration:BoxDecoration(color:Colors.white24,borderRadius:BorderRadius.circular(8)))),const SizedBox(height:20),
    Text(m.league.toUpperCase(),textAlign:TextAlign.center,style:const TextStyle(fontSize:9,color:Color(0xFF8B93A5),letterSpacing:1.2)),
    const SizedBox(height:10),Text('${m.home}  vs  ${m.away}',textAlign:TextAlign.center,style:const TextStyle(fontSize:20,fontWeight:FontWeight.w900)),
    const SizedBox(height:18),Center(child:_score(m.confidence)),
    const SizedBox(height:18),Container(padding:const EdgeInsets.all(17),decoration:BoxDecoration(color:const Color(0xFF121725),borderRadius:BorderRadius.circular(20),border:Border.all(color:Colors.white10)),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
      const Text('PERCHÉ L’IA LO PROPONE',style:TextStyle(color:Color(0xFFA9A0FF),fontSize:10,fontWeight:FontWeight.w900,letterSpacing:1)),
      const SizedBox(height:10),Text(m.reason,style:const TextStyle(fontSize:14,height:1.4)),
      const SizedBox(height:15),Row(children:[Expanded(child:_box('AI Index',m.confidence==0?'—':'${m.confidence}/100')),const SizedBox(width:9),Expanded(child:_box('Proposta',m.proposals.isNotEmpty?'DISPONIBILE':'NESSUNA'))])
    ])),const SizedBox(height:12),Text('Nota: il punteggio è un indicatore statistico e non rappresenta una garanzia di vincita.',style:const TextStyle(color:Color(0xFF737B8E),fontSize:10,height:1.4))
  ]));
  Widget _score(int n)=>Container(width:108,height:108,decoration:const BoxDecoration(shape:BoxShape.circle,gradient:SweepGradient(colors:[Color(0xFF8B7CFF),Color(0xFF39D9FF),Color(0xFF42E89A),Color(0xFF8B7CFF)])),child:Center(child:Container(width:92,height:92,decoration:const BoxDecoration(shape:BoxShape.circle,color:Color(0xFF090C15)),child:Column(mainAxisAlignment:MainAxisAlignment.center,children:[Text(n==0?'—':'$n',style:const TextStyle(fontSize:25,fontWeight:FontWeight.w900)),const Text('AI INDEX',style:TextStyle(fontSize:8,color:Color(0xFF8D95A8)))]))));
  Widget _box(String a,String b)=>Container(padding:const EdgeInsets.all(12),decoration:BoxDecoration(color:Colors.white.withOpacity(.035),borderRadius:BorderRadius.circular(13)),child:Column(children:[Text(a,style:const TextStyle(color:Color(0xFF7F879A),fontSize:9)),const SizedBox(height:4),Text(b,style:const TextStyle(fontWeight:FontWeight.w900))]));
}

class _Background extends StatelessWidget { const _Background(); @override Widget build(BuildContext c)=>IgnorePointer(child:Stack(children:[
  Positioned(top:-100,right:-80,child:Container(width:300,height:300,decoration:BoxDecoration(shape:BoxShape.circle,color:const Color(0xFF5545C9).withOpacity(.10),boxShadow:[BoxShadow(color:const Color(0xFF8B7CFF).withOpacity(.12),blurRadius:90,spreadRadius:25)]))),
  Positioned(bottom:80,left:-100,child:Container(width:260,height:260,decoration:BoxDecoration(shape:BoxShape.circle,color:const Color(0xFF1AA8D8).withOpacity(.07),boxShadow:[BoxShadow(color:const Color(0xFF39D9FF).withOpacity(.10),blurRadius:80,spreadRadius:20)]))),
]));}
class _NoData extends StatelessWidget {
  final VoidCallback retry;
  const _NoData({required this.retry});
  @override
  Widget build(BuildContext c)=>Center(child:Padding(padding:const EdgeInsets.all(25),child:Column(mainAxisSize:MainAxisSize.min,children:[
    const Icon(Icons.cloud_sync_rounded,size:48,color:Color(0xFFA9A0FF)),
    const SizedBox(height:12),
    const Text('Feed in aggiornamento',style:TextStyle(fontSize:18,fontWeight:FontWeight.w900)),
    const SizedBox(height:7),
    const Text('Riprova tra poco. L’app usa automaticamente il feed verificato e i dati locali di sicurezza.',textAlign:TextAlign.center,style:TextStyle(color:Color(0xFF9299AD),fontSize:11,height:1.4)),
    const SizedBox(height:16),
    FilledButton.icon(onPressed:retry,icon:const Icon(Icons.refresh_rounded),label:const Text('Aggiorna')),
  ])));
}
class _Error extends StatelessWidget { final String error; final VoidCallback retry; const _Error({required this.error,required this.retry}); @override Widget build(BuildContext c)=>Center(child:Padding(padding:const EdgeInsets.all(25),child:Column(mainAxisSize:MainAxisSize.min,children:[const Icon(Icons.cloud_off_rounded,size:48,color:Color(0xFFFF7185)),const SizedBox(height:12),const Text('Dati non disponibili',style:TextStyle(fontSize:18,fontWeight:FontWeight.w900)),const SizedBox(height:6),Text(error,textAlign:TextAlign.center,style:const TextStyle(color:Color(0xFF9299AD),fontSize:11)),const SizedBox(height:16),FilledButton.icon(onPressed:retry,icon:const Icon(Icons.refresh),label:const Text('Riprova'))])));}
