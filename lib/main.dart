import 'package:flutter/material.dart';

void main() => runApp(const MatchAIProApp());

class MatchAIProApp extends StatelessWidget {
  const MatchAIProApp({super.key});
  @override Widget build(BuildContext context) => MaterialApp(
    title: 'Match AI Pro', debugShowCheckedModeBanner: false,
    theme: ThemeData(brightness: Brightness.dark, useMaterial3: true, colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF00C896), brightness: Brightness.dark), scaffoldBackgroundColor: const Color(0xFF07110F)),
    home: const HomePage(),
  );
}

class MatchData {
  final String home, away, time, league; final bool live;
  final int homeShots, awayShots, homeOn, awayOn, homeCorners, awayCorners, homeFouls, awayFouls, homeCards, awayCards, homeThrow, awayThrow, homeSaves, awaySaves;
  const MatchData({required this.home, required this.away, required this.time, required this.league, required this.live, required this.homeShots, required this.awayShots, required this.homeOn, required this.awayOn, required this.homeCorners, required this.awayCorners, required this.homeFouls, required this.awayFouls, required this.homeCards, required this.awayCards, required this.homeThrow, required this.awayThrow, required this.homeSaves, required this.awaySaves});
}

const matches = <MatchData>[
  MatchData(home:'Inter', away:'Milan', time:'20:45', league:'Serie A', live:false, homeShots:14, awayShots:9, homeOn:6, awayOn:3, homeCorners:7, awayCorners:4, homeFouls:10, awayFouls:13, homeCards:2, awayCards:3, homeThrow:16, awayThrow:19, homeSaves:3, awaySaves:5),
  MatchData(home:'Barcelona', away:'Atletico Madrid', time:'21:00', league:'La Liga', live:true, homeShots:11, awayShots:12, homeOn:5, awayOn:6, homeCorners:5, awayCorners:6, homeFouls:8, awayFouls:15, homeCards:1, awayCards:4, homeThrow:14, awayThrow:18, homeSaves:4, awaySaves:3),
  MatchData(home:'Bayern', away:'Dortmund', time:'18:30', league:'Bundesliga', live:false, homeShots:17, awayShots:8, homeOn:8, awayOn:3, homeCorners:8, awayCorners:2, homeFouls:7, awayFouls:11, homeCards:1, awayCards:2, homeThrow:12, awayThrow:20, homeSaves:2, awaySaves:7),
];

class HomePage extends StatefulWidget { const HomePage({super.key}); @override State<HomePage> createState()=>_HomePageState(); }
class _HomePageState extends State<HomePage> {
  int tab=0;
  @override Widget build(BuildContext context){
    final pages=[_matches(),_proposals(),_center()];
    return Scaffold(appBar:AppBar(title:const Row(children:[Icon(Icons.sports_soccer,color:Color(0xFF00C896)),SizedBox(width:10),Text('MATCH AI PRO',style:TextStyle(fontWeight:FontWeight.w900))]),actions:[IconButton(onPressed:()=>setState((){}),icon:const Icon(Icons.refresh))]),body:pages[tab],bottomNavigationBar:NavigationBar(selectedIndex:tab,onDestinationSelected:(i)=>setState(()=>tab=i),destinations:const[NavigationDestination(icon:Icon(Icons.calendar_today),label:'Giornata'),NavigationDestination(icon:Icon(Icons.auto_awesome),label:'Proposte IA'),NavigationDestination(icon:Icon(Icons.psychology),label:'AI Center')]));
  }
  Widget _header(String title,String sub)=>Container(padding:const EdgeInsets.all(20),decoration:BoxDecoration(borderRadius:BorderRadius.circular(22),gradient:const LinearGradient(colors:[Color(0xFF12382E),Color(0xFF0D201B)])),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[Text(title,style:const TextStyle(fontSize:24,fontWeight:FontWeight.w900)),const SizedBox(height:6),Text(sub,style:const TextStyle(color:Colors.white70))]));
  Widget _matches()=>ListView(padding:const EdgeInsets.all(16),children:[_header('PARTITE DELLA GIORNATA','Statistiche e analisi IA'),const SizedBox(height:16),...matches.map((m)=>Padding(padding:const EdgeInsets.only(bottom:12),child:InkWell(onTap:()=>_open(m),child:_card(m))))]);
  Widget _proposals()=>ListView(padding:const EdgeInsets.all(16),children:[_header('PROPOSTE IA','Lettura automatica dei dati disponibili'),const SizedBox(height:16),...matches.map((m)=>Card(child:Padding(padding:const EdgeInsets.all(16),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[Text(m.home+' — '+m.away,style:const TextStyle(fontSize:18,fontWeight:FontWeight.w800)),const SizedBox(height:10),Text(_analysis(m),style:const TextStyle(color:Colors.white70,height:1.4)),const SizedBox(height:10),Wrap(spacing:8,children:[_tag('Tiri '+(m.homeShots+m.awayShots).toString()),_tag('Corner '+(m.homeCorners+m.awayCorners).toString()),_tag('Cartellini '+(m.homeCards+m.awayCards).toString())])]))))]);
  Widget _center() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _header('AI CENTER', 'Confronta qualsiasi partita'),
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
                const Text('Apri una partita per visualizzare il confronto completo tra tiri, corner, falli, cartellini, rimesse e parate.', style: TextStyle(color: Colors.white70)),
                const SizedBox(height: 16),
                ...matches.map((m) => Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: OutlinedButton.icon(
                    onPressed: () => _open(m),
                    icon: const Icon(Icons.analytics_outlined),
                    label: Text('\${m.home} — \${m.away}'),
                  ),
                )),
              ],
            ),
          ),
        ),
      ],
    );
  }
  void _open(MatchData m)=>showModalBottomSheet(context:context,isScrollControlled:true,backgroundColor:const Color(0xFF07110F),builder:(_)=>MatchDetail(match:m));
  Widget _card(MatchData m)=>Card(shape:RoundedRectangleBorder(borderRadius:BorderRadius.circular(18)),child:Padding(padding:const EdgeInsets.all(16),child:Column(children:[Row(children:[Text(m.league,style:const TextStyle(color:Colors.white54)),const Spacer(),m.live?const _Live():Text(m.time,style:const TextStyle(fontWeight:FontWeight.w800))]),const SizedBox(height:14),Row(children:[Expanded(child:Text(m.home,textAlign:TextAlign.center,style:const TextStyle(fontSize:17,fontWeight:FontWeight.w800))),const Text('VS',style:TextStyle(color:Colors.white38)),Expanded(child:Text(m.away,textAlign:TextAlign.center,style:const TextStyle(fontSize:17,fontWeight:FontWeight.w800)))]),const SizedBox(height:14),Row(mainAxisAlignment:MainAxisAlignment.spaceAround,children:[_stat('Tiri',m.homeShots,m.awayShots,Icons.sports_soccer),_stat('Corner',m.homeCorners,m.awayCorners,Icons.flag),_stat('Cartellini',m.homeCards,m.awayCards,Icons.style),_stat('Falli',m.homeFouls,m.awayFouls,Icons.front_hand)])])));
  Widget _stat(String l,int a,int b,IconData i)=>Column(children:[Icon(i,size:18,color:Colors.white54),Text(a.toString()+':'+b.toString(),style:const TextStyle(fontWeight:FontWeight.w800)),Text(l,style:const TextStyle(fontSize:9,color:Colors.white38))]);
  Widget _tag(String s)=>Container(padding:const EdgeInsets.symmetric(horizontal:10,vertical:7),decoration:BoxDecoration(color:const Color(0xFF17352C),borderRadius:BorderRadius.circular(20)),child:Text(s,style:const TextStyle(fontSize:12)));
  String _analysis(MatchData m){final shots=m.homeShots+m.awayShots;final corners=m.homeCorners+m.awayCorners;final cards=m.homeCards+m.awayCards;final level=shots>=25?'alta':shots>=16?'media':'contenuta';return 'Intensità '+level+'. Sono registrati '+shots.toString()+' tiri, '+corners.toString()+' corner e '+cards.toString()+' cartellini. Il motore confronta volume offensivo, pressione e disciplina.';}
}

class MatchDetail extends StatelessWidget {
  final MatchData match; const MatchDetail({super.key,required this.match});
  @override Widget build(BuildContext context)=>SafeArea(child:DraggableScrollableSheet(expand:false,initialChildSize:.88,minChildSize:.55,maxChildSize:.96,builder:(_,c)=>ListView(controller:c,padding:const EdgeInsets.all(18),children:[Row(children:[Expanded(child:Text(match.home+' — '+match.away,style:const TextStyle(fontSize:23,fontWeight:FontWeight.w900))),if(match.live)const _Live()]),const SizedBox(height:6),Text(match.league,style:const TextStyle(color:Colors.white54)),const SizedBox(height:18),_row('Tiri',match.homeShots,match.awayShots,Icons.sports_soccer),_row('Tiri in porta',match.homeOn,match.awayOn,Icons.gps_fixed),_row('Corner',match.homeCorners,match.awayCorners,Icons.flag),_row('Falli',match.homeFouls,match.awayFouls,Icons.front_hand),_row('Cartellini',match.homeCards,match.awayCards,Icons.style),_row('Rimesse',match.homeThrow,match.awayThrow,Icons.compare_arrows),_row('Parate',match.homeSaves,match.awaySaves,Icons.pan_tool_alt),const SizedBox(height:12),Card(child:Padding(padding:const EdgeInsets.all(16),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[const Text('AI MATCH ANALYSIS',style:TextStyle(color:Color(0xFF00C896),fontWeight:FontWeight.w900)),const SizedBox(height:8),Text('Confronto automatico: '+match.home+' ha '+(match.homeShots>match.awayShots?'più':'meno')+' tiri. I dati vengono mostrati separatamente per evitare conclusioni non supportate.',style:const TextStyle(height:1.45))]))) ])));
  Widget _row(String n,int a,int b,IconData i)=>Card(margin:const EdgeInsets.only(bottom:9),child:Padding(padding:const EdgeInsets.all(14),child:Row(children:[Icon(i,size:20,color:Colors.white54),const SizedBox(width:10),Expanded(child:Text(n,style:const TextStyle(fontWeight:FontWeight.w700))),Text(a.toString(),style:const TextStyle(fontSize:18,fontWeight:FontWeight.w900)),const SizedBox(width:28),Text(b.toString(),style:const TextStyle(fontSize:18,fontWeight:FontWeight.w900))])));
}
class _Live extends StatelessWidget {const _Live();@override Widget build(BuildContext context)=>Container(padding:const EdgeInsets.symmetric(horizontal:9,vertical:5),decoration:BoxDecoration(color:Colors.redAccent.withValues(alpha:.15),borderRadius:BorderRadius.circular(20)),child:const Text('LIVE',style:TextStyle(color:Colors.redAccent,fontWeight:FontWeight.w900,fontSize:11)));}