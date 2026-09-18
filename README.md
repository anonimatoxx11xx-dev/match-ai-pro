# Match AI Pro

Flutter Android app per analisi calcistica con dati reali.

## Dati reali

L'app usa **API-Football / API-SPORTS** per:
- partite della giornata;
- stato LIVE e risultato;
- statistiche partita quando disponibili;
- tiri, tiri in porta, corner, falli, cartellini, rimesse e parate.

Per il piano gratuito è importante non interrogare continuamente il feed: la schermata principale carica la giornata con una chiamata e le statistiche dettagliate vengono richieste quando si apre una partita live o terminata.

## Configurazione API key

1. Crea un account gratuito su API-Football.
2. Recupera la tua API key personale.
3. Nel repository GitHub apri **Settings → Secrets and variables → Actions**.
4. Crea il repository secret:
   `API_FOOTBALL_KEY`
5. Avvia il workflow **Build Match AI Pro APK**.

Il workflow passa la chiave alla build tramite `--dart-define`; la chiave non viene scritta nel repository.

## Build

L'APK prodotto dal workflow si chiama **MatchAIPro.apk**.

Nota: per una futura distribuzione pubblica conviene spostare le chiamate API dietro un backend/proxy, così la chiave non viene incorporata nell'APK.
