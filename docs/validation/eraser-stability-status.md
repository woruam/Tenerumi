# Gomma: blocco Android — 2026-10-06

Utente conferma il messaggio Android "L'app non risponde", con ATTENDI/CHIUDI:
si tratta di ANR. Non e' disponibile un trace del dispositivo. Il codice
precedente eseguiva Path.combine ripetuti su percorsi crescenti per ogni evento.

Modifiche:

- Nessun Path.combine in input, hit test, rendering ed esportazione dei tagli.
- Distanze fra segmenti per hit test; maschera alpha isolata per tratto.
- Layer limitato alla clip visibile e maschere fuori viewport escluse.
- Nessuna cache delle versioni native dei tagli precedenti.
- Sweep collineari compattati, contatti ridondanti ignorati.
- Campioni condivisi durante la cancellazione; copy-on-write nelle trasformazioni.
- Cache rettangoli solo per gesto, azzerata su inizio/fine/cancel/dispose.
- Quattro regressioni aggiunte, incluse sequenze di 4.000 eventi.

Nessuna build eseguita. I test non sono stati eseguiti per il precedente rifiuto
di accesso alla cache SDK; non e' stata ripetuta la richiesta. L'analisi statica
e' riuscita con exit 0, senza errori o warning (restano informazioni sullo stile),
ed e' registrata in eraser-stability-analyze.txt. La risoluzione dell'ANR sul
dispositivo resta da confermare: questi test non sono una misura dei frame
o della memoria Android. Gli screenshot predisposti rimangono da generare.
