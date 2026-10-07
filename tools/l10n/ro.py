#!/usr/bin/env python3
"""Romanian translations for the String Catalogs. Run after tools/l10n/sync.sh:
    python3 tools/l10n/ro.py
Keys missing here stay untranslated and tools/l10n/check.py reports them. Terms follow Apple Health
in Romanian (Sănătate, Ritm cardiac, Oxigen în sânge); Settings is "Configurări"."""
import json, pathlib

root = pathlib.Path(__file__).resolve().parents[2]

# Not translated: symbols, units, names and pure formats.
KEEP = {
    "%", "%@ - %@", "%@ - %@ · %@", "%@ /km", "%@ · %@", "%@ · %@ · %@ /km", "%@ · %lld / %lld", "%@ · %lld bpm, %@",
    "%@ · %lld%%", "%@%@", "%@, %@", "%lld", "%lld bpm", "%lld%%", "%lld-%lld bpm", "%lld/%lld %@", "+%lld", "+%lld %@",
    "-", "/%lld", "%lld s", "13-23%", "20-25%", "30 s", "75 s", "HRV", "Km %lld", "LIVE", "Live", "OK", "Pulse One", "REM", "bpm",
    "i", "km", "ms", "s", "v", "Max", "Min", "Sex", "Total", "Pulse Bridge",
}

T = {
    # App
    "%@ asleep": "%@ de somn",
    "%@ a day": "%@ pe zi",
    "%@ · next around %@": "%@ · următoarea în jur de %@",
    "%@ · score %lld": "%@ · scor %lld",
    "%@ · week of %@": "%@ · săptămâna din %@",
    "%@, +%lld every %@": "%@, +%lld în fiecare %@",
    "%@: %lld of %@": "%@: %lld din %@",
    "%@: %lld of %@, %lld to go": "%@: %lld din %@, mai sunt %lld",
    "%@: %lld of %@, done": "%@: %lld din %@, gata",
    "Daily target: %@": "Țintă zilnică: %@",
    "%@ this week": "%@ săptămâna aceasta",
    "%@ vs last week": "%@ față de săptămâna trecută",
    "%@ · %@ steps · %@": "%@ · %@ pași · %@",
    "%@ · %@ vs usual": "%@ · %@ față de obișnuit",
    "%@, last 14 days against the daily target": "%@, ultimele 14 zile față de ținta zilnică",
    "%@: %lld all time, %lld this week": "%@: %lld în total, %lld săptămâna aceasta",
    "%lld in the last 7 days": "%lld în ultimele 7 zile",
    "%lld of 100": "%lld din 100",
    "%lld of %lld days done": "Zile făcute: %lld din %lld",
    "%lld percent": "%lld la sută",
    "%lld percent of days hit": "%lld la sută din zile reușite",
    "%lldh %@m": "%lld h %@ min",
    "%lldm %@s": "%lld min %@ s",
    "D": "Z",
    "W": "S",
    "M": "L",
    "6M": "6L",
    "+%lld every week": "+%lld în fiecare săptămână",
    "3 buzzes above the zone, 2 below": "3 vibrații peste zonă, 2 sub",
    "85+ Optimal · 70-84 Good · 60-69 Fair · under 60 Pay attention": "85+ Optim · 70-84 Bun · 60-69 Acceptabil · sub 60 Atenție",
    "A rough number is fine: it's multiplied by the days done and added to each exercise's all-time total.":
        "Un număr aproximativ e suficient: se înmulțește cu zilele făcute și se adaugă la totalul fiecărui exercițiu.",
    "About %lld%% per day": "Cam %lld%% pe zi",
    "Above zone %lld": "Peste zona %lld",
    "Above zone %lld: ease off": "Peste zona %lld: încetinește",
    "Activities": "Activități",
    "Activity": "Activitate",
    "Activity balance": "Echilibrul activității",
    "Add %lld": "Adaugă %lld",
    "Add %lld %@": "Adaugă %lld %@",
    "Add exercise": "Adaugă exercițiu",
    "All time": "În total",
    "Allow location in Settings to record distance and the route.": "Permite localizarea în Configurări pentru a înregistra distanța și traseul.",
    "Allow location to record distance and the route.": "Permite localizarea pentru a înregistra distanța și traseul.",
    "An activity from %@ (%@) was not saved. Save it?": "O activitate din %@ (%@) nu a fost salvată. O salvezi?",
    "An estimate in the style of Oura's sleep score, with this app's own published formula. Each contributor scores 0-100; the score is their weighted average. Ranges follow the National Sleep Foundation's sleep quality recommendations (Ohayon 2017) and the AASM's 7+ hours. Stages count little because wrist bands can't tell deep sleep from REM reliably.":
        "O estimare în stilul scorului de somn Oura, cu formula publicată a acestei aplicații. Fiecare factor primește 0-100; scorul este media lor ponderată. Intervalele urmează recomandările National Sleep Foundation pentru calitatea somnului (Ohayon 2017) și cele 7+ ore ale AASM. Stadiile contează puțin, pentru că brățările nu pot deosebi sigur somnul profund de REM.",
    "Archive": "Arhivează",
    "Archive %@?": "Arhivezi %@?",
    "Archived exercises leave the card and the logger; their history stays.": "Exercițiile arhivate dispar de pe card și din jurnal; istoricul lor rămâne.",
    "Average": "Medie",
    "Average pace": "Ritm mediu",
    "Average per day": "Medie pe zi",
    "Averages": "Medii",
    "Avg/day": "Medie/zi",
    "Awake": "Treaz",
    "Awake time and wake-ups over 5 min; 20 min or less and 0-1 wake-ups is ideal": "Timp treaz și treziri de peste 5 min; ideal 20 min sau mai puțin și 0-1 treziri",
    "Awakenings": "Treziri",
    "Background sync": "Sincronizare în fundal",
    "Band": "Brățară",
    "Band not connected: GPS only, no heart rate.": "Brățara nu e conectată: doar GPS, fără ritm cardiac.",
    "Band traffic and sync events from recent syncs (%@). Useful when reporting a problem. It contains your raw band data, so share it only with people you trust.":
        "Traficul cu brățara și evenimentele din ultimele sincronizări (%@). Util când raportezi o problemă. Conține datele brute ale brățării, așa că trimite-l doar persoanelor în care ai încredere.",
    "Battery": "Baterie",
    "Battery %lld percent": "Baterie %lld la sută",
    "Bedtime consistency": "Regularitatea orei de culcare",
    "Before the app": "Înainte de aplicație",
    "Below zone %lld": "Sub zona %lld",
    "Below zone %lld: pick it up": "Sub zona %lld: accelerează",
    "Below zone 1": "Sub zona 1",
    "Best streak": "Cea mai lungă serie",
    "Birth year": "Anul nașterii",
    "Blood oxygen": "Oxigen în sânge",
    "Blood pressure (estimate)": "Tensiune arterială (estimare)",
    "Bluetooth not allowed": "Bluetooth nepermis",
    "Bluetooth off": "Bluetooth oprit",
    "Bluetooth unavailable": "Bluetooth indisponibil",
    "Body temperature": "Temperatura corpului",
    "Both update automatically from your band data.": "Ambele se actualizează automat din datele brățării.",
    "Cancel": "Anulează",
    "Cancel session": "Anulează sesiunea",
    "Challenge": "Provocare",
    "Challenge started": "Începutul provocării",
    "Clear": "Șterge",
    "Clear the diagnostics log?": "Ștergi jurnalul de diagnosticare?",
    "Collecting data for the daily estimate": "Se adună date pentru estimarea zilnică",
    "Collecting data: a reading is saved at each connection and sync.": "Se adună date: o citire se salvează la fiecare conectare și sincronizare.",
    "Connected": "Conectată",
    "Connecting": "Se conectează",
    "Connecting...": "Se conectează...",
    "Contributors": "Factori",
    "Core": "Esențial",
    "Couldn't load data: %@": "Datele nu s-au putut încărca: %@",
    "Count": "Număr",
    "Custom amount": "Altă valoare",
    "Daily average": "Medie zilnică",
    "Daily challenge": "Provocarea zilei",
    "Daily totals (stored only)": "Totaluri zilnice (doar stocate)",
    "Day": "Zi",
    "Days done": "Zile făcute",
    "Deep": "Profund",
    "Deep share of sleep (band estimate); 16% or more is typical": "Proporția de somn profund (estimarea brățării); de obicei 16% sau mai mult",
    "Deep sleep": "Somn profund",
    "Default until 3 nights of sleep data exist.": "Valoare implicită până există 3 nopți de date de somn.",
    "Diagnostics": "Diagnosticare",
    "Discard": "Renunță",
    "Discard this activity? It won't be saved or sent to Health.": "Renunți la această activitate? Nu va fi salvată și nici trimisă în Sănătate.",
    "Distance": "Distanță",
    "Done": "Gata",
    "Drag to reorder, switch off what you don't need. The rings and the day strip always stay on top.":
        "Trage pentru a reordona și oprește ce nu-ți trebuie. Inelele și banda zilelor rămân mereu sus.",
    "Edit Today": "Editează Azi",
    "Edit exercise": "Editează exercițiul",
    "Efficiency": "Eficiență",
    "End": "Sfârșit",
    "Estimated wake-up %@, %lld bpm": "Trezire estimată %@, %lld bpm",
    "Exercise": "Exercițiu",
    "Exercises": "Exerciții",
    "Exercises and targets": "Exerciții și ținte",
    "Export log": "Exportă jurnalul",
    "Export to Health now": "Exportă acum în Sănătate",
    "Exporting...": "Se exportă...",
    "Fell asleep": "Adormit la",
    "Female": "Femeie",
    "Finish": "Termină",
    "Finish this activity?": "Termini această activitate?",
    "Forget band": "Uită brățara",
    "Forget this band? You'll need to pair it again. Data on the phone stays.": "Uiți această brățară? Va trebui să o asociezi din nou. Datele de pe telefon rămân.",
    "Free": "Liber",
    "From heart-rate rises the band's stages explain; the band itself rarely marks waking in the night.":
        "Din creșterile pulsului pe care le explică stadiile brățării; brățara însăși marchează rar trezirile din timpul nopții.",
    "From your age (208 - 0.7 x age); a harder effort will raise it.": "Din vârstă (208 - 0,7 x vârsta); un efort mai intens îl va crește.",
    "Full colour: target reached. Dashed line: the daily target.": "Culoare plină: țintă atinsă. Linie punctată: ținta zilnică.",
    "Full marks: 7-9 h asleep; efficiency 90%+; 20 min or less awake after falling asleep and at most 1 wake-up over 5 min; sleep midpoint within 30 min of your usual (median of the last 14 nights; 00:00-03:00 until there are 3 nights); 5-30 min to fall asleep; REM 21-40%; deep 16%+. Nights under 6 h score at most 70.":
        "Punctaj maxim: 7-9 h de somn; eficiență 90%+; cel mult 20 min treaz după adormire și cel mult o trezire de peste 5 min; mijlocul somnului la cel mult 30 min de cel obișnuit (mediana ultimelor 14 nopți; 00:00-03:00 până există 3 nopți); 5-30 min până la adormire; REM 21-40%; profund 16%+. Nopțile sub 6 h primesc cel mult 70.",
    "Goal": "Obiectiv",
    "Grow automatically": "Crește automat",
    "HR %@": "Puls %@",
    "HRV (average asleep)": "HRV (medie în somn)",
    "HRV balance": "Echilibrul HRV",
    "Health data since": "Date în Sănătate din",
    "Health error": "Eroare Sănătate",
    "Health export": "Export în Sănătate",
    "Heart rate": "Ritm cardiac",
    "Heart rate %lld": "Ritm cardiac %lld",
    "Heart rate checks": "Măsurători de puls",
    "Height: %lld cm": "Înălțime: %lld cm",
    "Highest heart rate held in the last 6 months.": "Cel mai mare puls menținut în ultimele 6 luni.",
    "Highlights": "Repere",
    "Hike": "Drumeție",
    "Hour": "Oră",
    "Hours": "Ore",
    "In bed": "În pat",
    "In zone %lld": "În zona %lld",
    "In zone %lld: %@": "În zona %lld: %@",
    "Keep the band close to the phone and make sure no other app is connected to it.": "Ține brățara aproape de telefon și asigură-te că nicio altă aplicație nu e conectată la ea.",
    "Last 14 days": "Ultimele 14 zile",
    "Last night": "Azi-noapte",
    "Last sync": "Ultima sincronizare",
    "Latency": "Latență",
    "Log": "Notează",
    "Log %@": "Notează %@",
    "Log sets": "Notează seturi",
    "Looking for your band": "Se caută brățara",
    "Male": "Bărbat",
    "Max heart rate": "Puls maxim",
    "Measurement stopped.": "Măsurătoarea s-a oprit.",
    "Measuring %@... keep still": "Se măsoară %@... stai nemișcat",
    "Median of the last 14 nights.": "Mediana ultimelor 14 nopți.",
    "Middle of your sleep vs your last 14 nights; within 30 min is ideal": "Mijlocul somnului față de ultimele 14 nopți; ideal la cel mult 30 min",
    "Minutes": "Minute",
    "Month": "Lună",
    "More for %@": "Mai multe pentru %@",
    "Moving time": "Timp în mișcare",
    "Name": "Nume",
    "New exercise": "Exercițiu nou",
    "Next month": "Luna următoare",
    "Next week": "Săptămâna următoare",
    "Night": "Noapte",
    "Night average (asleep)": "Medie pe noapte (în somn)",
    "Night vitals": "Semne vitale nocturne",
    "No activities in the last 30 days": "Nicio activitate în ultimele 30 de zile",
    "No activities in the last 7 days": "Nicio activitate în ultimele 7 zile",
    "No band: no heart rate": "Fără brățară: fără puls",
    "No data": "Fără date",
    "No data today": "Nicio dată azi",
    "No heart rate": "Fără puls",
    "No heart-rate readings during the night": "Nicio citire de puls în timpul nopții",
    "No reading. Wear the band snug and keep still.": "Nicio citire. Poartă brățara strâns și stai nemișcat.",
    "No sleep data": "Fără date de somn",
    "No sleep data for last night": "Nicio dată de somn pentru azi-noapte",
    "No sleep data for this night": "Nicio dată de somn pentru această noapte",
    "Not allowed in Health": "Nepermis în Sănătate",
    "Not connected": "Neconectată",
    "Not enough data for this night.": "Date insuficiente pentru această noapte.",
    "Not enough data from last night yet. Sync after waking up.": "Încă nu sunt destule date de azi-noapte. Sincronizează după ce te trezești.",
    "Not enough data yet": "Încă nu sunt destule date",
    "Not on wrist?": "Nu e pe încheietură?",
    "Not synced yet": "Nesincronizat încă",
    "Nothing logged": "Nimic notat",
    "Nothing stands out yet. Highlights appear once there are a few nights and days to compare.": "Încă nu iese nimic în evidență. Reperele apar când există câteva nopți și zile de comparat.",
    "On": "Ziua",
    "On the next automatic sync": "La următoarea sincronizare automată",
    "Open Health": "Deschide Sănătate",
    "Open Settings": "Deschide Configurări",
    "Pair band": "Asociază brățara",
    "Partly done": "Parțial făcut",
    "Pause": "Pauză",
    "Previous month": "Luna anterioară",
    "Previous week": "Săptămâna anterioară",
    "Profile": "Profil",
    "Profile and zones": "Profil și zone",
    "Progress before the app": "Progres înainte de aplicație",
    "Pulse Bridge diagnostics": "Diagnosticare Pulse Bridge",
    "Push-ups": "Flotări",
    "REM share of sleep (band estimate); 21-40% is typical": "Proporția de somn REM (estimarea brățării); de obicei 21-40%",
    "REM sleep": "Somn REM",
    "Range": "Interval",
    "Range %@-%@ %@": "Interval %@-%@ %@",
    "Readiness": "Pregătire",
    "Readiness compares last night with your own baseline (average of up to 30 earlier nights): HRV 35%, resting heart rate 25%, sleep score 20%, yesterday's steps against your usual 10%, and night temperature 10% (warmer than usual lowers it). It needs 5 earlier nights to start.":
        "Pregătirea compară noaptea trecută cu nivelul tău de bază (media a până la 30 de nopți anterioare): HRV 35%, pulsul în repaus 25%, scorul de somn 20%, pașii de ieri față de obișnuit 10% și temperatura nopții 10% (mai cald decât de obicei o scade). Are nevoie de 5 nopți anterioare ca să înceapă.",
    "Recorded with GPS": "Înregistrată cu GPS",
    "Regularity": "Regularitate",
    "Remove": "Elimină",
    "Reps": "Repetări",
    "Restfulness": "Odihnă",
    "Resting HR": "Puls în repaus",
    "Resting heart rate": "Puls în repaus",
    "Resume": "Reia",
    "Ride": "Bicicletă",
    "Route map": "Harta traseului",
    "Run": "Alergare",
    "Save": "Salvează",
    "Saved on the band; it reaches Apple Health on the next sync.": "Salvată pe brățară; ajunge în Sănătate la următoarea sincronizare.",
    "Saved to Health": "Se salvează în Sănătate",
    "Scanning": "Se caută",
    "Score": "Scor",
    "Seconds": "Secunde",
    "Session options": "Opțiuni sesiune",
    "Set up challenge": "Configurează provocarea",
    "Set your age for accurate heart-rate zones": "Setează-ți vârsta pentru zone de puls corecte",
    "Set your age in Band > Profile for accurate zones.": "Setează-ți vârsta în Brățară > Profil pentru zone corecte.",
    "Share": "Distribuie",
    "Share of time in bed spent asleep; 90% or more for full marks": "Proporția din timpul în pat petrecută dormind; 90% sau mai mult pentru punctaj maxim",
    "Show month": "Arată luna",
    "Show week": "Arată săptămâna",
    "Sleep": "Somn",
    "Sleep score": "Scor de somn",
    "Sleep score (estimate)": "Scor de somn (estimare)",
    "Sleep stages": "Stadii de somn",
    "Splits": "Segmente",
    "Squats": "Genuflexiuni",
    "Stage": "Stadiu",
    "Stages (Deep/REM split is an estimate)": "Stadii (împărțirea Profund/REM e o estimare)",
    "Stages per night": "Stadii pe noapte",
    "Start": "Începe",
    "Start a streak today": "Începe o serie azi",
    "Start activity": "Începe o activitate",
    "Start live heart rate": "Pornește pulsul live",
    "Start timed session": "Începe o sesiune cronometrată",
    "Started before using Pulse Bridge? Bring over your days done and streaks.": "Ai început înainte de Pulse Bridge? Adu aici zilele făcute și seriile.",
    "Starting": "Pornire",
    "Starting the sensor...": "Pornește senzorul...",
    "Steps": "Pași",
    "Stop live heart rate": "Oprește pulsul live",
    "Streak": "Serie",
    "Stress": "Stres",
    "Sync": "Sincronizare",
    "Sync failed": "Sincronizarea a eșuat",
    "Synced %@": "Sincronizat %@",
    "Syncing...": "Se sincronizează...",
    "Target": "Țintă",
    "Temperature": "Temperatură",
    "The daily target is how many you aim for each day; a day counts as done when every exercise reaches it. Changes start today and past days keep the target they had. With growth on, the target goes up by itself every week.":
        "Ținta zilnică este cât îți propui să faci în fiecare zi; o zi contează ca făcută când fiecare exercițiu o atinge. Schimbările încep de azi, iar zilele trecute își păstrează ținta pe care o aveau. Cu creșterea pornită, ținta urcă singură în fiecare săptămână.",
    "This week": "Săptămâna aceasta",
    "This week vs last week": "Săptămâna aceasta față de cea trecută",
    "Time": "Timp",
    "Time asleep": "Timp de somn",
    "Time asleep; 7-9 h for full marks": "Timp de somn; 7-9 h pentru punctaj maxim",
    "Time in zone %lld": "Timp în zona %lld",
    "Time in zones": "Timp în zone",
    "Time to fall asleep": "Timp până la adormire",
    "Time to fall asleep; 5-30 min is ideal": "Timp până la adormire; ideal 5-30 min",
    "Times your sets and saves a Strength training workout with band heart rate to Apple Health.":
        "Cronometrează seturile și salvează în Sănătate un antrenament de forță cu pulsul de la brățară.",
    "Timing": "Program",
    "Today": "Azi",
    "Total sleep": "Somn total",
    "Totals": "Totaluri",
    "Track a daily goal like push-ups and squats, with streaks and history.": "Urmărește un obiectiv zilnic, ca flotări și genuflexiuni, cu serii și istoric.",
    "Trends": "Tendințe",
    "Turn on Background App Refresh for Pulse Bridge in Settings to sync without opening the app.":
        "Activează Reîmprospătare în fundal pentru Pulse Bridge în Configurări, ca să sincronizeze fără să deschizi aplicația.",
    "Turn on Precise Location for Pulse Bridge in Settings; approximate location can't measure distance.":
        "Activează Localizare precisă pentru Pulse Bridge în Configurări; localizarea aproximativă nu poate măsura distanța.",
    "Undo": "Anulează",
    "Undo %lld %@": "Anulează %lld %@",
    "Undo last set": "Anulează ultimul set",
    "Unfinished activity": "Activitate neterminată",
    "Unit": "Unitate",
    "Up to %@, the day before your first day in the app. Days you complete here add to these.":
        "Până la %@, ziua dinaintea primei zile în aplicație. Zilele pe care le completezi aici se adaugă la acestea.",
    "Vitals": "Semne vitale",
    "Waiting for GPS...": "Se așteaptă GPS...",
    "Wake-ups (estimated)": "Treziri (estimate)",
    "Walk": "Plimbare",
    "Week": "Săptămână",
    "Weight: %lld kg": "Greutate: %lld kg",
    "Woke up": "Trezit la",
    "Written to Health": "Scrise în Sănătate",
    "You can change targets any time, and let them grow every week.": "Poți schimba țintele oricând și le poți lăsa să crească în fiecare săptămână.",
    "Your first kilometre shows here.": "Primul kilometru apare aici.",
    "Zone": "Zonă",
    "Zone %lld": "Zona %lld",
    "Zone %lld · %@": "Zona %lld · %@",
    "Zone %lld · %lld-%lld bpm": "Zona %lld · %lld-%lld bpm",
    "Zone alerts on": "Alerte de zonă pornite",
    "Zone alerts on the band": "Alerte de zonă pe brățară",
    "Zones": "Zone",
    "about 50%": "circa 50%",
    "all time": "în total",
    "avg %lld bpm": "medie %lld bpm",
    "avg /km": "medie /km",
    "avg %@ · max %@ bpm": "medie %@ · max %@ bpm",
    "before the app": "înainte de aplicație",
    "best %lld": "record %lld",
    "coming out of REM": "la ieșirea din REM",
    "day streak": "zile la rând",
    "done": "gata",
    "easy": "ușor",
    "hard": "greu",
    "heart rate": "pulsul",
    "hit": "reușite",
    "max": "maxim",
    "midpoint %@": "mijloc %@",
    "midpoint %@ · usual %@": "mijloc %@ · de obicei %@",
    "moderate": "moderat",
    "no data": "fără date",
    "none": "niciunul",
    "not part of the challenge": "nu face parte din provocare",
    "nothing logged": "nimic notat",
    "of %@": "din %@",
    "out of deep sleep": "din somn profund",
    "pace /km": "ritm /km",
    "partial": "parțial",
    "reps": "repetări",
    "rest": "repaus",
    "resting %lld": "repaus %lld",
    "score %lld": "scor %lld",
    "steps": "pași",
    "the band marked awake": "brățara a marcat treaz",
    "today %lld-%lld": "azi %lld-%lld",
    "typical %@": "tipic %@",
    "under 10%": "sub 10%",
    "very easy": "foarte ușor",
    "well above the night's typical heart rate": "mult peste pulsul obișnuit al nopții",
    # Widget
    "Paused": "Pauză",
    "💪 Day %lld/%lld": "💪 Ziua %lld/%lld",
    "Never": "Niciodată",
    "Not yet": "Încă nu",
    "None": "Niciuna",
    # PulseKit
    "%@ °C vs usual": "%@ °C față de obișnuit",
    "%lld bpm · usual %lld": "%lld bpm · de obicei %lld",
    "%lld h ago": "acum %lld h",
    "%lld min ago": "acum %lld min",
    "%lld ms · usual %lld": "%lld ms · de obicei %lld",
    "A sync is already running.": "O sincronizare este deja în curs.",
    "Big activity day yesterday": "Zi foarte activă ieri",
    "Fair": "Acceptabil",
    "Good": "Bun",
    "HRV %lld ms, %lld%% higher than usual": "HRV %lld ms, cu %lld%% peste obișnuit",
    "HRV %lld ms, %lld%% lower than usual": "HRV %lld ms, cu %lld%% sub obișnuit",
    "HRV %lld%% below your usual": "HRV cu %lld%% sub obișnuit",
    "Night temperature %@ °C above your usual": "Temperatura nopții cu %@ °C peste obișnuit",
    "Night temperature %@ °C below your usual": "Temperatura nopții cu %@ °C sub obișnuit",
    "Optimal": "Optim",
    "Pay attention": "Atenție",
    "Resting heart rate %lld above your usual": "Pulsul în repaus cu %lld peste obișnuit",
    "Resting heart rate %lld bpm, %lld above your recent average": "Pulsul în repaus %lld bpm, cu %lld peste media recentă",
    "Resting heart rate %lld bpm, %lld below your recent average": "Pulsul în repaus %lld bpm, cu %lld sub media recentă",
    "Short or restless sleep": "Somn scurt sau agitat",
    "Sleep score %lld": "Scor de somn %lld",
    "Steady": "Constant",
    "Steps down %lld%% on the week before": "Cu %lld%% mai puțini pași decât săptămâna trecută",
    "Steps up %lld%% on the week before": "Cu %lld%% mai mulți pași decât săptămâna trecută",
    "Temperature %@ °C above your usual": "Temperatura cu %@ °C peste obișnuit",
    "The band did not answer command %@.": "Brățara nu a răspuns la comanda %@.",
    "The band disconnected.": "Brățara s-a deconectat.",
    "You slept %lld min less per night than the week before": "Ai dormit cu %lld min mai puțin pe noapte decât săptămâna trecută",
    "You slept %lld min more per night than the week before": "Ai dormit cu %lld min mai mult pe noapte decât săptămâna trecută",
    "You're recovered": "Ești refăcut",
    "just now": "chiar acum",
    "yesterday": "ieri",
    # PulseBLE
    "Band not found. Keep it close to the phone and make sure it is charged.": "Brățara nu a fost găsită. Ține-o aproape de telefon și asigură-te că e încărcată.",
    "Bluetooth access is not allowed. Enable it in Settings > Pulse Bridge.": "Accesul la Bluetooth nu este permis. Activează-l în Configurări > Pulse Bridge.",
    "Bluetooth is not available on this device.": "Bluetooth nu este disponibil pe acest dispozitiv.",
    "Bluetooth is off. Turn it on in Control Center.": "Bluetooth este oprit. Pornește-l din Centrul de control.",
    "No band paired yet.": "Nicio brățară asociată încă.",
    "The band stopped responding.": "Brățara nu mai răspunde.",
    "This iPhone no longer knows the band. Use Forget band, then pair it again.": "Acest iPhone nu mai recunoaște brățara. Folosește Uită brățara, apoi asociaz-o din nou.",
    "Unknown band": "Brățară necunoscută",
}

# Plurals on the only number: (en one, en other) or None, (ro one, ro few, ro other).
P = {
    "%lld steps": (("%lld step", "%lld steps"), ("%lld pas", "%lld pași", "%lld de pași")),
    "%lld reps": (("%lld rep", "%lld reps"), ("%lld repetare", "%lld repetări", "%lld de repetări")),
    "%lld days ago": (("%lld day ago", "%lld days ago"), ("acum %lld zi", "acum %lld zile", "acum %lld de zile")),
    "Calibrating: %lld more nights with the band to learn your baseline.": (
        ("Calibrating: %lld more night with the band to learn your baseline.", "Calibrating: %lld more nights with the band to learn your baseline."),
        ("Calibrare: încă %lld noapte cu brățara ca să-ți învețe nivelul de bază.",
         "Calibrare: încă %lld nopți cu brățara ca să-ți învețe nivelul de bază.",
         "Calibrare: încă %lld de nopți cu brățara ca să-ți învețe nivelul de bază.")),
    "Done for today · %lld-day streak": (None, ("Gata pentru azi · serie de %lld zi", "Gata pentru azi · serie de %lld zile", "Gata pentru azi · serie de %lld de zile")),
    "of %lld days": (("of %lld day", "of %lld days"), ("din %lld zi", "din %lld zile", "din %lld de zile")),
    "%lld days": (("%lld day", "%lld days"), ("%lld zi", "%lld zile", "%lld de zile")),
}

# Plurals on one of several numbers: arg number, (en one, other) or None, ro template with %#@n@, ro (one, few, other).
S = {
    # A formatted count ("1.234"), then the count again only to pick the noun's plural form.
    "%@ steps %lld": (2, ("%1$@ %#@n@", ("step", "steps")), ("%1$@ %#@n@", ("pas", "pași", "de pași"))),
    "%@ steps · usual %@ %lld": (3, ("%1$@ %#@n@ · usual %2$@", ("step", "steps")),
                                 ("%1$@ %#@n@ · de obicei %2$@", ("pas", "pași", "de pași"))),
    # The share message: day and streak.
    "💪 Day %lld/%lld. %lld-day streak": (3, None, ("💪 Ziua %1$lld/%2$lld. %#@n@", ("%arg zi la rând", "%arg zile la rând", "%arg de zile la rând"))),
    "🔥 %lld-day streak · best %lld": (1, None, ("🔥 Serie de %#@n@ · record %2$lld", ("%arg zi", "%arg zile", "%arg de zile"))),
    "%lld day streak, best %lld": (1, None, ("Serie de %#@n@, record %2$lld", ("%arg zi", "%arg zile", "%arg de zile"))),
    "%lld min awake · %lld wake-ups": (2, ("%1$lld min awake · %#@n@", ("%arg wake-up", "%arg wake-ups")),
                                       ("%1$lld min treaz · %#@n@", ("%arg trezire", "%arg treziri", "%arg de treziri"))),
    "Goal reached on %lld of %lld days": (2, ("Goal reached on %1$lld of %#@n@", ("%arg day", "%arg days")),
                                          ("Obiectiv atins în %1$lld din %#@n@", ("%arg zi", "%arg zile", "%arg de zile"))),
    "%lld years · female · %lld cm · %lld kg": (1, None, ("%#@n@ · femeie · %2$lld cm · %3$lld kg", ("%arg an", "%arg ani", "%arg de ani"))),
    "%lld years · male · %lld cm · %lld kg": (1, None, ("%#@n@ · bărbat · %2$lld cm · %3$lld kg", ("%arg an", "%arg ani", "%arg de ani"))),
}

# Permission prompts and the app name (Info.plist keys).
INFO = {
    "CFBundleDisplayName": ("Pulse Bridge", None),
    "NSBluetoothAlwaysUsageDescription": ("Pulse Bridge connects to your Pulse band to read your activity and health history.",
                                          "Pulse Bridge se conectează la brățara Pulse pentru a citi istoricul activității și al sănătății."),
    "NSHealthUpdateUsageDescription": ("Pulse Bridge writes steps, distance, heart rate, HRV, blood oxygen, sleep and workouts from your band to Apple Health.",
                                       "Pulse Bridge scrie în Sănătate pașii, distanța, ritmul cardiac, HRV, oxigenul din sânge, somnul și antrenamentele de la brățară."),
    "NSHealthShareUsageDescription": ("Pulse Bridge does not read your Health data.", "Pulse Bridge nu citește datele tale din Sănătate."),
    "NSLocationWhenInUseUsageDescription": ("Pulse Bridge records your route, distance and pace while an activity you started is running.",
                                            "Pulse Bridge înregistrează traseul, distanța și ritmul cât timp rulează o activitate pornită de tine."),
}


def unit(value):
    return {"stringUnit": {"state": "translated", "value": value}}


def plural(forms):
    keys = ("one", "other") if len(forms) == 2 else ("one", "few", "other")
    return {"variations": {"plural": {k: unit(v) for k, v in zip(keys, forms)}}}


def substituted(template, arg, forms):
    keys = ("one", "other") if len(forms) == 2 else ("one", "few", "other")
    return {"stringUnit": {"state": "translated", "value": template},
            "substitutions": {"n": {"argNum": arg, "formatSpecifier": "lld",
                                    "variations": {"plural": {k: unit(v) for k, v in zip(keys, forms)}}}}}


def apply(entry, key):
    loc = entry.setdefault("localizations", {})
    if key in KEEP:
        entry["shouldTranslate"] = False
        entry.pop("localizations", None)
        return True
    if key in P:
        en, ro = P[key]
        if en: loc["en"] = plural(en)
        loc["ro"] = plural(ro)
        return True
    if key in S:
        arg, en, ro = S[key]
        if en: loc["en"] = substituted(en[0], arg, en[1])
        loc["ro"] = substituted(ro[0], arg, ro[1])
        return True
    if key in T:
        loc["ro"] = unit(T[key])
        return True
    return False


catalogs = ["PulseBridge/Localizable.xcstrings", "PulseBridgeWidgets/Localizable.xcstrings",
            "PulseKit/Sources/PulseKit/Localizable.xcstrings", "PulseKit/Sources/PulseBLE/Localizable.xcstrings"]
missing = []
for name in catalogs:
    path = root / name
    data = json.loads(path.read_text())
    # Texts the code no longer uses (the catalogs are generated from the code and this file).
    data["strings"] = {k: e for k, e in data["strings"].items() if e.get("extractionState") != "stale"}
    for key, entry in data["strings"].items():
        if not apply(entry, key):
            missing.append(f"{name}: {key!r}")
    path.write_text(json.dumps(data, ensure_ascii=False, indent=2, sort_keys=True) + "\n")

info = {"sourceLanguage": "en", "strings": {}, "version": "1.0"}
for key, (en, ro) in INFO.items():
    entry = {"extractionState": "manual", "localizations": {"en": unit(en)}}
    if ro is None:
        entry["shouldTranslate"] = False
    else:
        entry["localizations"]["ro"] = unit(ro)
    info["strings"][key] = entry
(root / "PulseBridge/InfoPlist.xcstrings").write_text(json.dumps(info, ensure_ascii=False, indent=2, sort_keys=True) + "\n")

print("\n".join(missing) or "all keys translated")
