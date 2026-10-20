import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'super_prediction_engine.dart';

void main() => runApp(const SuperMatchApp());

const bg = Color(0xFF080D18);
const panel = Color(0xFF111B2B);
const line = Color(0xFF243247);
const lime = Color(0xFFB7F36B);
const cyan = Color(0xFF4DE1D2);
const muted = Color(0xFF8D9CB2);

class SuperMatchApp extends StatelessWidget {
  const SuperMatchApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Match AI Pro · Super Engine',
    debugShowCheckedModeBanner: false,
    theme: ThemeData(
      useMaterial3: true, brightness: Brightness.dark, scaffoldBackgroundColor: bg,
      colorScheme: ColorScheme.fromSeed(seedColor: lime, brightness: Brightness.dark),
      fontFamily: 'sans',
    ),
    home: const PredictionHome(),
  );
}

class PredictionHome extends StatefulWidget {
  const PredictionHome({super.key});
  @override
  State<PredictionHome> createState() => _PredictionHomeState();
}

class _PredictionHomeState extends State<PredictionHome> {
  final engine = SuperPredictionEngine();
  List<Map<String, dynamic>> matches = [];
  List<Map<String, dynamic>> history = [];
  bool loading = true;
  String feedStatus = 'CARICAMENTO';
  String source = 'Fonte da verificare';
  String filter = 'Tutte';
  int tab = 0;
  String error = '';

  @override
  void initState() { super.initState(); load(); }

  Future<void> load() async {
    setState(() { loading = true; error = ''; });
    try {
      final latestText = await rootBundle.loadString('data/latest.json');
      final historyText = await rootBundle.loadString('data/results.json');
      var latest = jsonDecode(latestText) as Map<String, dynamic>;
      var hist = jsonDecode(historyText) as Map<String, dynamic>;
      try {
        final response = await http.get(Uri.parse('https://raw.githubusercontent.com/anonimatoxx11xx-dev/match-ai-pro/main/data/latest.json')).timeout(const Duration(seconds: 8));
        if (response.statusCode == 200) latest = jsonDecode(response.body) as Map<String, dynamic>;
      } catch (_) {}
      try {
        final response = await http.get(Uri.parse('https://raw.githubusercontent.com/anonimatoxx11xx-dev/match-ai-pro/main/data/results.json')).timeout(const Duration(seconds: 8));
        if (response.statusCode == 200) hist = jsonDecode(response.body) as Map<String, dynamic>;
      } catch (_) {}
      final rawMatches = (latest['matches'] as List? ?? const []).whereType<Map>().map((e) => Map<String,dynamic>.from(e)).where((m) =>
        const {'NS','SCHEDULED','NOT STARTED'}.contains((m['status'] ?? '').toString().toUpperCase()) ||
        m['status'] == null).toList();
      final rawHistory = (hist['results'] as List? ?? const []).whereType<Map>().map((e) => Map<String,dynamic>.from(e)).toList();
      final predictions = engine.predict(fixtures: rawMatches, history: rawHistory);
      predictions.sort((a,b) {
        final pa = _prediction(a), pb = _prediction(b);
        final scoreA = ((_num(pa['quality']) ?? 0) * .45) + _topProb(pa) * .55;
        final scoreB = ((_num(pb['quality']) ?? 0) * .45) + _topProb(pb) * .55;
        return scoreB.compareTo(scoreA);
      });
      if (!mounted) return;
      setState(() {
        matches = predictions;
        history = rawHistory;
        feedStatus = (latest['feedStatus'] ?? 'SCONOSCIUTO').toString();
        source = (latest['source'] ?? 'Fonte non dichiarata').toString();
        loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() { loading = false; error = 'Impossibile leggere i dati della partita.'; });
    }
  }

  Map<String,dynamic> _prediction(Map<String,dynamic> m) => m['prediction'] is Map ? Map<String,dynamic>.from(m['prediction']) : <String,dynamic>{};
  double _topProb(Map<String,dynamic> p) => [_num(p['home']) ?? 0, _num(p['draw']) ?? 0, _num(p['away']) ?? 0].reduce((a,b) => a > b ? a : b);
  double? _num(dynamic v) => v is num ? v.toDouble() : double.tryParse(v?.toString() ?? '');
  String _s(dynamic v) => v?.toString() ?? '';
  List<String> get leagues => ['Tutte', ...matches.map((m) => _s(m['league'])).where((s) => s.isNotEmpty).toSet().toList()..sort()];
  List<Map<String,dynamic>> get filtered => filter == 'Tutte' ? matches : matches.where((m) => m['league'] == filter).toList();
  List<Map<String,dynamic>> get strongest => matches.where((m) => (_num(_prediction(m)['quality']) ?? 0) >= 45).take(6).toList();

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(child: RefreshIndicator(
      color: lime, backgroundColor: panel, onRefresh: load,
      child: CustomScrollView(slivers: [
        SliverToBoxAdapter(child: _header()),
        if (tab == 0) ...[
          SliverToBoxAdapter(child: _hero()),
          SliverToBoxAdapter(child: _sectionTitle('SELEZIONE DEL MOTORE', 'Partite con segnali più leggibili')),
          if (loading) const SliverToBoxAdapter(child: Padding(padding: EdgeInsets.all(30), child: Center(child: CircularProgressIndicator(color: lime)))),
          if (!loading && strongest.isEmpty) SliverToBoxAdapter(child: _empty('Nessuna partita con dati sufficienti', 'Aggiorna il feed o scegli una giornata con più dati verificati.')),
          SliverList(delegate: SliverChildBuilderDelegate((context, i) => _matchCard(strongest[i], featured: true), childCount: loading ? 0 : strongest.length)),
          SliverToBoxAdapter(child: _sectionTitle('IL RESTO DELLE PARTITE', 'Confronta probabilità e qualità dei dati')),
          SliverToBoxAdapter(child: _leagueFilter()),
          SliverList(delegate: SliverChildBuilderDelegate((context, i) => _matchCard(filtered[i]), childCount: filtered.length)),
        ] else if (tab == 1) ...[
          SliverToBoxAdapter(child: _sectionTitle('TUTTE LE PARTITE', matches.length.toString() + ' incontri nel feed')),
          SliverToBoxAdapter(child: _leagueFilter()),
          SliverList(delegate: SliverChildBuilderDelegate((context, i) => _matchCard(filtered[i]), childCount: filtered.length)),
        ] else ...[
          SliverToBoxAdapter(child: _methodPanel()),
        ],
        SliverToBoxAdapter(child: Padding(padding: const EdgeInsets.fromLTRB(20,18,20,34), child: Text('Le probabilità sono stime statistiche, non garanzie. Il motore riduce il livello di fiducia quando i dati sono incompleti.', style: TextStyle(color: muted, fontSize: 11, height: 1.45)))),
      ]),
    )),
    bottomNavigationBar: NavigationBar(
      backgroundColor: const Color(0xFF0D1523), indicatorColor: lime.withOpacity(.14),
      selectedIndex: tab, onDestinationSelected: (v) => setState(() => tab = v),
      destinations: const [
        NavigationDestination(icon: Icon(Icons.auto_awesome), label: 'Pronostici'),
        NavigationDestination(icon: Icon(Icons.sports_soccer), label: 'Partite'),
        NavigationDestination(icon: Icon(Icons.psychology_alt_outlined), label: 'Motore AI'),
      ],
    ),
  );

  Widget _header() => Padding(padding: const EdgeInsets.fromLTRB(20,16,20,10), child: Row(children: [
    Container(width: 44, height: 44, decoration: BoxDecoration(gradient: const LinearGradient(colors: [lime, cyan]), borderRadius: BorderRadius.circular(14)), child: const Icon(Icons.bolt, color: bg, size: 28)),
    const SizedBox(width: 12),
    const Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('MATCH AI PRO', style: TextStyle(letterSpacing: 2.2, fontWeight: FontWeight.w900, fontSize: 15)),
      Text('SUPER PREDICTION ENGINE', style: TextStyle(color: cyan, letterSpacing: 1.2, fontSize: 9, fontWeight: FontWeight.w800)),
    ])),
    IconButton(onPressed: load, icon: const Icon(Icons.refresh_rounded), tooltip: 'Aggiorna'),
  ]));

  Widget _hero() {
    final degraded = feedStatus.toUpperCase() != 'LIVE';
    return Container(
      margin: const EdgeInsets.fromLTRB(16,8,16,18), padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color(0xFF1C2B40), Color(0xFF101B2C), Color(0xFF132C32)]),
        border: Border.all(color: cyan.withOpacity(.28)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Expanded(child: Text('L’ANALISI PARTE DAI DATI', style: TextStyle(color: cyan, fontSize: 10, fontWeight: FontWeight.w900, letterSpacing: 1.3))),
          _pill(loading ? 'AGGIORNO' : (degraded ? 'FEED RIDOTTO' : 'FEED LIVE'), degraded ? const Color(0xFFFFC66D) : lime),
        ]),
        const SizedBox(height: 15),
        const Text('Meno rumore.\nPiù probabilità.', style: TextStyle(fontSize: 30, height: 1.05, fontWeight: FontWeight.w900, letterSpacing: -.8)),
        const SizedBox(height: 12),
        Text('Il motore confronta forma recente, gol, tiri in porta e segnali di mercato. Se il campione è debole, abbassa la fiducia invece di inventare certezze.', style: TextStyle(color: Colors.white.withOpacity(.72), fontSize: 13, height: 1.5)),
        const SizedBox(height: 18),
        Row(children: [
          _metric(matches.length.toString(), 'PARTITE'),
          const SizedBox(width: 22), _metric(history.length.toString(), 'RISULTATI'),
          const SizedBox(width: 22), _metric('SPE-1', 'MOTORE'),
        ]),
        if (error.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 12), child: Text(error, style: const TextStyle(color: Color(0xFFFF8888)))),
      ]),
    );
  }

  Widget _metric(String value, String label) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    Text(value, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: lime)),
    const SizedBox(height: 3), Text(label, style: TextStyle(color: muted, fontSize: 9, letterSpacing: 1.2, fontWeight: FontWeight.w800)),
  ]);

  Widget _sectionTitle(String title, String subtitle) => Padding(padding: const EdgeInsets.fromLTRB(20,12,20,12), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    Text(title, style: const TextStyle(fontSize: 11, letterSpacing: 1.4, color: cyan, fontWeight: FontWeight.w900)),
    const SizedBox(height: 5), Text(subtitle, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
  ]));

  Widget _leagueFilter() => SizedBox(height: 48, child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: 16), children: leagues.map((l) =>
    Padding(padding: const EdgeInsets.only(right: 8), child: ChoiceChip(label: Text(l), selected: filter == l, onSelected: (_) => setState(() => filter = l),
      selectedColor: lime.withOpacity(.18), backgroundColor: panel, side: BorderSide(color: filter == l ? lime.withOpacity(.6) : line),
      labelStyle: TextStyle(color: filter == l ? lime : Colors.white70, fontSize: 11, fontWeight: FontWeight.w700)))).toList()));

  Widget _matchCard(Map<String,dynamic> m, {bool featured = false}) {
    final p = _prediction(m);
    final home = _s(m['home']), away = _s(m['away']);
    final h = _num(p['home']) ?? 0, d = _num(p['draw']) ?? 0, a = _num(p['away']) ?? 0;
    final pick = _s(p['pick']), quality = _num(p['quality']) ?? 0;
    return InkWell(onTap: () => _showDetails(m), borderRadius: BorderRadius.circular(20), child: Container(
      margin: const EdgeInsets.fromLTRB(16,4,16,10), padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: featured ? const Color(0xFF142233) : panel, borderRadius: BorderRadius.circular(20), border: Border.all(color: featured ? cyan.withOpacity(.32) : line)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(child: Text(_s(m['league']).toUpperCase(), maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: muted, fontSize: 9, letterSpacing: 1.1, fontWeight: FontWeight.w900))),
          _pill(_s(p['qualityLabel']).toUpperCase() + ' ' + quality.round().toString() + '%', _qualityColor(quality)),
        ]),
        const SizedBox(height: 13),
        Row(children: [
          Expanded(child: Text(home, maxLines: 2, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14))),
          Column(children: [
            Text(_s(m['time']), style: TextStyle(color: muted, fontSize: 10)),
            const SizedBox(height: 3), Text(_s(p['score']), style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w900, color: lime)),
          ]),
          Expanded(child: Text(away, textAlign: TextAlign.end, maxLines: 2, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14))),
        ]),
        const SizedBox(height: 15),
        Row(children: [
          _prob('1', h, pick == '1'), const SizedBox(width: 7),
          _prob('X', d, pick == 'X'), const SizedBox(width: 7),
          _prob('2', a, pick == '2'),
        ]),
        const SizedBox(height: 13),
        Row(children: [
          Expanded(child: Text('xG ' + _s(p['xgHome']) + ' – ' + _s(p['xgAway']) + '   ·   HT ' + _s(p['ht']), style: TextStyle(color: muted, fontSize: 10, fontWeight: FontWeight.w600))),
          const Icon(Icons.chevron_right, color: cyan, size: 18),
        ]),
      ]),
    ));
  }

  Widget _prob(String label, double value, bool selected) => Expanded(child: Container(
    padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 6),
    decoration: BoxDecoration(color: selected ? lime.withOpacity(.12) : const Color(0xFF0A1220), borderRadius: BorderRadius.circular(11), border: Border.all(color: selected ? lime.withOpacity(.55) : line)),
    child: Column(children: [
      Text(label, style: TextStyle(color: selected ? lime : muted, fontSize: 10, fontWeight: FontWeight.w900)),
      const SizedBox(height: 3), Text(value.round().toString() + '%', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: selected ? lime : Colors.white)),
    ]),
  ));

  Widget _pill(String text, Color color) => Container(padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5), decoration: BoxDecoration(color: color.withOpacity(.12), borderRadius: BorderRadius.circular(20), border: Border.all(color: color.withOpacity(.35))), child: Text(text, style: TextStyle(color: color, fontSize: 8, fontWeight: FontWeight.w900, letterSpacing: .5)));

  Color _qualityColor(double q) => q >= 70 ? lime : (q >= 45 ? const Color(0xFFFFC66D) : const Color(0xFFFF8888));

  Widget _empty(String title, String body) => Container(margin: const EdgeInsets.all(16), padding: const EdgeInsets.all(20), decoration: BoxDecoration(color: panel, borderRadius: BorderRadius.circular(18), border: Border.all(color: line)), child: Column(children: [const Icon(Icons.query_stats, size: 32, color: cyan), const SizedBox(height: 12), Text(title, style: const TextStyle(fontWeight: FontWeight.w800)), const SizedBox(height: 6), Text(body, textAlign: TextAlign.center, style: const TextStyle(color: muted, fontSize: 12))]));

  Widget _methodPanel() => Padding(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    _sectionTitle('SPE-1 · SUPER PREDICTION ENGINE', 'Motore spiegabile, non una scatola nera'),
    _methodStep('01', 'Forma recente', 'Ultimi risultati della stessa squadra nella stessa competizione, con peso maggiore alle gare più recenti.'),
    _methodStep('02', 'Modello dei gol', 'Distribuzione di Poisson per calcolare 1-X-2, risultato esatto, Over 2.5 e Goal/No Goal.'),
    _methodStep('03', 'Segnali secondari', 'Tiri in porta e favorito di mercato possono correggere la stima solo entro limiti stretti.'),
    _methodStep('04', 'Qualità del campione', 'Le partite con pochi dati mostrano una fiducia inferiore; non vengono promosse automaticamente come migliori.'),
    const SizedBox(height: 12),
    Container(padding: const EdgeInsets.all(16), decoration: BoxDecoration(color: panel, borderRadius: BorderRadius.circular(16), border: Border.all(color: line)), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Text('STATO DELLE FONTI', style: TextStyle(color: cyan, fontWeight: FontWeight.w900, letterSpacing: 1)),
      const SizedBox(height: 8), Text(feedStatus + ' · ' + source, style: const TextStyle(fontWeight: FontWeight.w700)),
      const SizedBox(height: 6), Text('Un feed ridotto non viene presentato come copertura completa. I risultati storici possono essere insufficienti per alcuni campionati.', style: TextStyle(color: muted, fontSize: 12, height: 1.45)),
    ])),
  ]));

  Widget _methodStep(String number, String title, String body) => Container(margin: const EdgeInsets.only(bottom: 10), padding: const EdgeInsets.all(15), decoration: BoxDecoration(color: panel, borderRadius: BorderRadius.circular(16), border: Border.all(color: line)), child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
    Container(width: 34, height: 34, decoration: BoxDecoration(color: lime.withOpacity(.12), borderRadius: BorderRadius.circular(10)), alignment: Alignment.center, child: Text(number, style: const TextStyle(color: lime, fontWeight: FontWeight.w900))),
    const SizedBox(width: 12), Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(title, style: const TextStyle(fontWeight: FontWeight.w800)), const SizedBox(height: 5), Text(body, style: TextStyle(color: muted, fontSize: 12, height: 1.45))])),
  ]));

  void _showDetails(Map<String,dynamic> m) {
    final p = _prediction(m);
    showModalBottomSheet(context: context, isScrollControlled: true, backgroundColor: bg, shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(26))), builder: (context) => DraggableScrollableSheet(
      expand: false, initialChildSize: .84, maxChildSize: .95, builder: (context, scroll) => ListView(controller: scroll, padding: const EdgeInsets.fromLTRB(20,14,20,30), children: [
        Center(child: Container(width: 42, height: 4, decoration: BoxDecoration(color: line, borderRadius: BorderRadius.circular(5)))),
        const SizedBox(height: 20),
        Text(_s(m['league']).toUpperCase(), textAlign: TextAlign.center, style: const TextStyle(color: cyan, fontSize: 10, fontWeight: FontWeight.w900, letterSpacing: 1.4)),
        const SizedBox(height: 10),
        Text(_s(m['home']) + '  vs  ' + _s(m['away']), textAlign: TextAlign.center, style: const TextStyle(fontSize: 21, fontWeight: FontWeight.w900)),
        const SizedBox(height: 16),
        Container(padding: const EdgeInsets.all(18), decoration: BoxDecoration(color: panel, borderRadius: BorderRadius.circular(18), border: Border.all(color: line)), child: Column(children: [
          Text(_s(p['score']), style: const TextStyle(fontSize: 42, color: lime, fontWeight: FontWeight.w900)),
          Text('Risultato esatto più probabile · probabilità ' + _s(p['scoreP']) + '%', style: const TextStyle(color: muted, fontSize: 11)),
          const SizedBox(height: 18),
          Row(children: [
            _detailMetric('xG casa', _s(p['xgHome'])), _detailMetric('xG ospite', _s(p['xgAway'])), _detailMetric('HT stimato', _s(p['ht'])),
          ]),
        ])),
        const SizedBox(height: 18), const Text('PROBABILITÀ 1-X-2', style: TextStyle(color: cyan, fontSize: 10, fontWeight: FontWeight.w900, letterSpacing: 1.2)),
        const SizedBox(height: 10), Row(children: [_prob('1', _num(p['home']) ?? 0, p['pick'] == '1'), const SizedBox(width: 7), _prob('X', _num(p['draw']) ?? 0, p['pick'] == 'X'), const SizedBox(width: 7), _prob('2', _num(p['away']) ?? 0, p['pick'] == '2')]),
        const SizedBox(height: 18), const Text('MERCATI GOL', style: TextStyle(color: cyan, fontSize: 10, fontWeight: FontWeight.w900, letterSpacing: 1.2)),
        const SizedBox(height: 10),
        Row(children: [_detailMetric('Over 1.5', _s(p['over15']) + '%'), _detailMetric('Over 2.5', _s(p['over25']) + '%'), _detailMetric('Over 3.5', _s(p['over35']) + '%')]),
        const SizedBox(height: 12),
        Row(children: [_detailMetric('Under 2.5', _s(p['under25']) + '%'), _detailMetric('Goal', _s(p['btts']) + '%'), _detailMetric('No Goal', _s(p['noBtts']) + '%')]),
        const SizedBox(height: 12),
        Row(children: [_detailMetric('Qualità dati', _s(p['quality']) + '%'), _detailMetric('Campione casa', _s(p['samplesHome'])), _detailMetric('Campione ospite', _s(p['samplesAway']))]),
        const SizedBox(height: 18), const Text('ALTRI RISULTATI POSSIBILI', style: TextStyle(color: cyan, fontSize: 10, fontWeight: FontWeight.w900, letterSpacing: 1.2)),
        const SizedBox(height: 8),
        ...((p['scores'] as List? ?? const []).whereType<Map>().map((s) => Padding(padding: const EdgeInsets.symmetric(vertical: 5), child: Row(children: [
          Expanded(child: Text(_s(s['score']), style: const TextStyle(fontWeight: FontWeight.w800))),
          Expanded(flex: 4, child: ClipRRect(borderRadius: BorderRadius.circular(8), child: LinearProgressIndicator(value: ((_num(s['p']) ?? 0) / 100).clamp(0,1), minHeight: 7, backgroundColor: line, color: cyan))),
          const SizedBox(width: 12), Text(_s(s['p']) + '%', style: const TextStyle(fontWeight: FontWeight.w800)),
        ])))),
        const SizedBox(height: 18), const Text('PERCHÉ IL MOTORE PENSA COSÌ', style: TextStyle(color: cyan, fontSize: 10, fontWeight: FontWeight.w900, letterSpacing: 1.2)),
        const SizedBox(height: 8),
        ...((p['reasons'] as List? ?? const []).map((r) => Padding(padding: const EdgeInsets.only(bottom: 8), child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [const Icon(Icons.check_circle_outline, color: lime, size: 16), const SizedBox(width: 8), Expanded(child: Text(r.toString(), style: const TextStyle(color: Colors.white70, fontSize: 12, height: 1.4)))])))),
        const SizedBox(height: 14), Text(_s(p['model']) + ' · Campione casa ' + _s(p['samplesHome']) + ', ospite ' + _s(p['samplesAway']), style: const TextStyle(color: muted, fontSize: 10)),
      ]),
    ));
  }

  Widget _detailMetric(String label, String value) => Expanded(child: Column(children: [Text(value, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w900)), const SizedBox(height: 4), Text(label, textAlign: TextAlign.center, style: const TextStyle(color: muted, fontSize: 9))]));
}
