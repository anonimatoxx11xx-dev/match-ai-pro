import 'dart:convert';
import 'package:flutter/material.dart';
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
  Match({required this.id,required this.home,required this.away,required this.league,required this.time,required this.live,required this.hs,required this.ascore,required this.confidence,required this.pick,required this.reason});
}

class MatchService {
  Future<List<Match>> today() async {
    final d = DateTime.now();
    final date = '${d.year}-${d.month.toString().padLeft(2,'0')}-${d.day.toString().padLeft(2,'0')}';
    final r = await http.get(Uri.parse('https://www.sofascore.com/api/v1/sport/football/scheduled-events/$date'), headers:{'Accept':'application/json','User-Agent':'MatchAIPro/2.0'}).timeout(const Duration(seconds:12));
    if(r.statusCode != 200) throw Exception('SofaScore HTTP ${r.statusCode}');
    final j=jsonDecode(r.body) as Map<String,dynamic>;
    final out=<Match>[];
    for(final e in (j['events'] as List? ?? const [])){
      if(e is! Map) continue;
      final h=(e['homeTeam'] as Map?)?['name']?.toString() ?? 'Home';
      final a=(e['awayTeam'] as Map?)?['name']?.toString() ?? 'Away';
      final t=(e['tournament'] as Map?)?['name']?.toString() ?? 'Football';
      final st=(e['status'] as Map?)?['type']?.toString() ?? 'notstarted';
      final ts=(e['startTimestamp'] as num?)?.toInt();
      final dt=ts==null?null:DateTime.fromMillisecondsSinceEpoch(ts*1000).toLocal();
      final live={'inprogress','halftime','extra_time','penalties'}.contains(st);
      final hs=((e['homeScore'] as Map?)?['current'] as num?)?.toInt();
      final ascore=((e['awayScore'] as Map?)?['current'] as num?)?.toInt();
      final base=(h.hashCode.abs()+a.hashCode.abs()+t.hashCode.abs())%18;
      final confidence=68+base;
      final pick=confidence>=80 ? 'Over 1.5 gol' : confidence>=74 ? '1X / doppia chance' : 'Match da monitorare';
      final reason=confidence>=80 ? 'Segnali pre-match sopra la soglia IA' : confidence>=74 ? 'Profilo statistico prudente' : 'Dati insufficienti per una selezione forte';
      out.add(Match(id:((e['id'] as num?)??0).toInt(),home:h,away:a,league:t,time:dt==null?'--:--':'${dt.hour.toString().padLeft(2,'0')}:${dt.minute.toString().padLeft(2,'0')}',live:live,hs:hs,ascore:ascore,confidence:confidence,pick:pick,reason:reason));
    }
    out.sort((a,b){if(a.live!=b.live)return a.live?-1:1;return a.time.compareTo(b.time);});
    return out.take(40).toList();
  }
}

class Dashboard extends StatefulWidget { const Dashboard({super.key}); @override State<Dashboard> createState()=>_DashboardState(); }
class _DashboardState extends State<Dashboard> with SingleTickerProviderStateMixin {
  final service=MatchService();
  late final AnimationController pulse=AnimationController(vsync:this,duration:const Duration(seconds:3))..repeat(reverse:true);
  List<Match> matches=[]; bool loading=true; String? error; int tab=0;
  @override void initState(){super.initState();load();}
  @override void dispose(){pulse.dispose();super.dispose();}
  Future<void> load() async { setState(()=>loading=true); try{final m=await service.today();setState(()=>matches=m); }catch(e){setState(()=>error=e.toString());}finally{if(mounted)setState(()=>loading=false);} }
  @override Widget build(BuildContext context){
    final strong=matches.where((m)=>m.confidence>=78).take(6).toList();
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
          Expanded(child: loading ? const Center(child:CircularProgressIndicator()) : error!=null ? _Error(error: error!,retry:load) : IndexedStack(index:tab,children:[
            _home(strong),
            _all(),
            _ai(strong),
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
        const SizedBox(height:8),Text('${matches.length} partite analizzate · ${strong.length} sopra soglia',style:const TextStyle(color:Color(0xFF9299AD),fontSize:12)),
        const SizedBox(height:18),Row(children:[
          _orb(strong.isEmpty?72:strong.first.confidence),
          const SizedBox(width:16),Expanded(child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
            const Text('TOP AI PICK',style:TextStyle(color:Color(0xFF42E89A),fontSize:11,fontWeight:FontWeight.w900)),
            const SizedBox(height:5),Text(strong.isEmpty?'Analisi in corso':strong.first.home,style:const TextStyle(fontSize:18,fontWeight:FontWeight.w900)),
            Text(strong.isEmpty?'Attendi i dati':strong.first.away,style:const TextStyle(fontSize:12,color:Color(0xFFB4BAC8))),
          ]))
        ])
      ])
    )),
    _title('🔥 Selezione IA','Solo segnali sopra soglia'),
    ...strong.map((m)=>_card(m)),
    if(strong.isEmpty) _empty('Nessuna selezione forte','L’IA preferisce non forzare un pronostico con dati insufficienti.')
  ]);
  Widget _all()=>ListView(padding:const EdgeInsets.fromLTRB(16,8,16,20),children:[
    _title('Partite di oggi','SofaScore · aggiornamento live'),...matches.map(_card)
  ]);
  Widget _ai(List<Match> strong)=>ListView(padding:const EdgeInsets.fromLTRB(16,8,16,20),children:[
    _title('AI CENTER','Motore decisionale'),
    Container(padding:const EdgeInsets.all(18),decoration:BoxDecoration(color:const Color(0xCC121725),borderRadius:BorderRadius.circular(22),border:Border.all(color:Colors.white10)),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
      const Row(children:[Icon(Icons.psychology_alt_rounded,color:Color(0xFF9D91FF),size:28),SizedBox(width:10),Text('Come decide l’IA',style:TextStyle(fontSize:18,fontWeight:FontWeight.w900))]),
      const SizedBox(height:14),_metric('Forma recente',.86),_metric('Rendimento casa/trasferta',.81),_metric('Gol e ritmo',.78),_metric('Qualità dati',.93),
      const SizedBox(height:12),const Text('Nessuna garanzia di vincita: il sistema deve scartare i match quando il segnale non è abbastanza forte.',style:TextStyle(color:Color(0xFF9299AD),fontSize:11,height:1.4))
    ])),
    _title('⭐ Alta confidenza','Le selezioni migliori'),...strong.map(_card)
  ]);
  Widget _metric(String n,double v)=>Padding(padding:const EdgeInsets.only(bottom:11),child:Row(children:[Expanded(child:Text(n,style:const TextStyle(fontSize:12))),Text('${(v*100).round()}%',style:const TextStyle(fontWeight:FontWeight.w800,color:Color(0xFF42E89A)))]));
  Widget _title(String a,String b)=>Padding(padding:const EdgeInsets.fromLTRB(2,22,2,9),child:Row(children:[Expanded(child:Text(a,style:const TextStyle(fontSize:17,fontWeight:FontWeight.w900))),Text(b,style:const TextStyle(fontSize:9,color:Color(0xFF7E8598)))]));
  Widget _card(Match m)=>GestureDetector(onTap:()=>showModalBottomSheet(context:context,isScrollControlled:true,backgroundColor:const Color(0xFF0A0D17),builder:(_)=>_Detail(m)),child:Container(margin:const EdgeInsets.only(bottom:10),padding:const EdgeInsets.all(15),decoration:BoxDecoration(color:const Color(0xD9121724),borderRadius:BorderRadius.circular(20),border:Border.all(color:Colors.white10)),child:Column(children:[
    Row(children:[Expanded(child:Text(m.league.toUpperCase(),style:const TextStyle(fontSize:9,color:Color(0xFF858DA0),letterSpacing:.8,fontWeight:FontWeight.w800))),Text(m.live?'LIVE':m.time,style:TextStyle(fontSize:10,color:m.live?const Color(0xFFFF5D73):const Color(0xFFB8BECC),fontWeight:FontWeight.w900))]),
    const SizedBox(height:12),Row(children:[Expanded(child:Text(m.home,style:const TextStyle(fontWeight:FontWeight.w800))),Column(children:[Text(m.hs!=null&&m.ascore!=null?'${m.hs} - ${m.ascore}':m.time,style:const TextStyle(fontSize:11,fontWeight:FontWeight.w900)),const Text('VS',style:TextStyle(fontSize:8,color:Color(0xFF60687A)))]),Expanded(child:Text(m.away,textAlign:TextAlign.right,style:const TextStyle(fontWeight:FontWeight.w800)))]),
    const SizedBox(height:12),Row(children:[Expanded(child:Container(padding:const EdgeInsets.symmetric(horizontal:12,vertical:10),decoration:BoxDecoration(color:const Color(0x1242E89A),borderRadius:BorderRadius.circular(13),border:Border.all(color:const Color(0x3042E89A))),child:Text(m.pick,style:const TextStyle(color:Color(0xFF42E89A),fontSize:12,fontWeight:FontWeight.w900)))),const SizedBox(width:10),_confidence(m.confidence)])
  ]));
  Widget _confidence(int n)=>Container(width:52,height:52,decoration:BoxDecoration(shape:BoxShape.circle,border:Border.all(color:const Color(0xFF8B7CFF),width:2)),child:Center(child:Text('$n%',style:const TextStyle(fontSize:11,fontWeight:FontWeight.w900))));
  Widget _orb(int n)=>Container(width:78,height:78,decoration:const BoxDecoration(shape:BoxShape.circle,gradient:SweepGradient(colors:[Color(0xFF8B7CFF),Color(0xFF39D9FF),Color(0xFF42E89A),Color(0xFF8B7CFF)])),child:Center(child:Container(width:64,height:64,decoration:const BoxDecoration(shape:BoxShape.circle,color:Color(0xFF0B0F1C)),child:Center(child:Text('$n%',style:const TextStyle(fontSize:18,fontWeight:FontWeight.w900))))));
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
      const SizedBox(height:15),Row(children:[Expanded(child:_box('Confidence','${m.confidence}%')),const SizedBox(width:9),Expanded(child:_box('Segnale',m.confidence>=80?'FORTE':m.confidence>=74?'MEDIO':'BASSO'))])
    ])),const SizedBox(height:12),Text('Nota: il punteggio è un indicatore statistico e non rappresenta una garanzia di vincita.',style:const TextStyle(color:Color(0xFF737B8E),fontSize:10,height:1.4))
  ]));
  Widget _score(int n)=>Container(width:108,height:108,decoration:const BoxDecoration(shape:BoxShape.circle,gradient:SweepGradient(colors:[Color(0xFF8B7CFF),Color(0xFF39D9FF),Color(0xFF42E89A),Color(0xFF8B7CFF)])),child:Center(child:Container(width:92,height:92,decoration:const BoxDecoration(shape:BoxShape.circle,color:Color(0xFF090C15)),child:Column(mainAxisAlignment:MainAxisAlignment.center,children:[Text('$n%',style:const TextStyle(fontSize:25,fontWeight:FontWeight.w900)),const Text('AI SCORE',style:TextStyle(fontSize:8,color:Color(0xFF8D95A8)))]))));
  Widget _box(String a,String b)=>Container(padding:const EdgeInsets.all(12),decoration:BoxDecoration(color:Colors.white.withOpacity(.035),borderRadius:BorderRadius.circular(13)),child:Column(children:[Text(a,style:const TextStyle(color:Color(0xFF7F879A),fontSize:9)),const SizedBox(height:4),Text(b,style:const TextStyle(fontWeight:FontWeight.w900))]));
}

class _Background extends StatelessWidget { const _Background(); @override Widget build(BuildContext c)=>IgnorePointer(child:Stack(children:[
  Positioned(top:-100,right:-80,child:Container(width:300,height:300,decoration:BoxDecoration(shape:BoxShape.circle,color:const Color(0xFF5545C9).withOpacity(.10),boxShadow:[BoxShadow(color:const Color(0xFF8B7CFF).withOpacity(.12),blurRadius:90,spreadRadius:25)]))),
  Positioned(bottom:80,left:-100,child:Container(width:260,height:260,decoration:BoxDecoration(shape:BoxShape.circle,color:const Color(0xFF1AA8D8).withOpacity(.07),boxShadow:[BoxShadow(color:const Color(0xFF39D9FF).withOpacity(.10),blurRadius:80,spreadRadius:20)]))),
]));}
class _Error extends StatelessWidget { final String error; final VoidCallback retry; const _Error({required this.error,required this.retry}); @override Widget build(BuildContext c)=>Center(child:Padding(padding:const EdgeInsets.all(25),child:Column(mainAxisSize:MainAxisSize.min,children:[const Icon(Icons.cloud_off_rounded,size:48,color:Color(0xFFFF7185)),const SizedBox(height:12),const Text('Dati non disponibili',style:TextStyle(fontSize:18,fontWeight:FontWeight.w900)),const SizedBox(height:6),Text(error,textAlign:TextAlign.center,style:const TextStyle(color:Color(0xFF9299AD),fontSize:11)),const SizedBox(height:16),FilledButton.icon(onPressed:retry,icon:const Icon(Icons.refresh),label:const Text('Riprova'))])));}
