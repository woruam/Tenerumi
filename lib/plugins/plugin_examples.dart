import 'dart:convert';

final _advancedPluginExamples = <Map<String, dynamic>>[
  {
    'apiVersion': 1,
    'id': 'example.latex',
    'name': 'Formule LaTeX',
    'version': '2.0.0',
    'description':
        'Anteprima matematica e inserimento di una formula nel foglio.',
    'runtime': 'javascript',
    'permissions': ['document.write', 'ui'],
    'modules': {
      'main.js': r'''
export async function insert(context) {
  const input = await osipp.call('ui.form', { title: 'Formula LaTeX', fields: [
    {id:'formula', label:'Formula', type:'text', multiline:true, required:true, default:'\\frac{a}{b} = \\sqrt{x}'},
    {id:'size', label:'Dimensione', type:'number', default:24}
  ]});
  if (!input) return;
  if (!await osipp.call('ui.preview', {type:'latex', text:input.formula, title:'Anteprima formula'})) return;
  const image = await osipp.call('latex.render', {text:input.formula, size:input.size});
  await osipp.call('image.add', {...image, x:40, y:40});
}
''',
    },
    'commands': [
      {'id': 'insert', 'label': 'Inserisci formula', 'handler': 'insert'},
    ],
  },
  {
    'apiVersion': 1,
    'id': 'example.anki',
    'name': 'Flashcard per Anki',
    'version': '2.0.0',
    'description':
        'Crea una flashcard o importa una lista JSON; esporta TSV per Anki.',
    'runtime': 'javascript',
    'permissions': ['ui', 'export', 'storage', 'files.read'],
    'modules': {
      'main.js': r'''
export async function add(context) {
  const card = await osipp.call('ui.form', {title:'Nuova flashcard', fields:[
    {id:'front', label:'Domanda', type:'text', multiline:true, required:true},
    {id:'back', label:'Risposta', type:'text', multiline:true, required:true}
  ]});
  if (!card) return;
  const cards = await osipp.call('state.get', {key:'cards'}) || [];
  cards.push(card);
  await osipp.call('state.set', {key:'cards', value:cards});
  await osipp.call('message', {text:`Flashcard conservate: ${cards.length}`});
}
export async function importCards(context) {
  const file = await osipp.call('files.open', {encoding:'utf8'});
  if (!file) return;
  const cards = JSON.parse(file.text);
  if (!Array.isArray(cards) || cards.some(c => typeof c.front !== 'string' || typeof c.back !== 'string')) throw new Error('Il JSON deve contenere [{front, back}]');
  await osipp.call('state.set', {key:'cards', value:cards});
  await osipp.call('message', {text:`Importate ${cards.length} flashcard`});
}
export async function exportCards(context) {
  const cards = await osipp.call('state.get', {key:'cards'}) || [];
  await osipp.call('anki.export', {cards, deck:'OSIpp', name:'flashcard.tsv'});
}
''',
    },
    'commands': [
      {'id': 'add', 'label': 'Aggiungi flashcard', 'handler': 'add'},
      {
        'id': 'import',
        'label': 'Importa flashcard JSON',
        'handler': 'importCards',
      },
      {'id': 'export', 'label': 'Esporta per Anki', 'handler': 'exportCards'},
    ],
  },
  {
    'apiVersion': 1,
    'id': 'example.ocr',
    'name': 'OCR immagini',
    'version': '2.0.0',
    'description': 'Riconosce il testo da una foto, permette di correggerlo e lo inserisce nel foglio. OCR locale Android.',
    'runtime': 'javascript',
    'permissions': ['files.read', 'ocr', 'ui', 'document.write'],
    'modules': {
      'main.js': r'''
export async function recognize(context) {
  const capabilities = await osipp.call('capabilities');
  if (!capabilities.ocr) throw new Error('Questo esempio richiede Android. Per un OCR remoto crea un provider http.request.');
  const image = await osipp.call('files.open', {type:'image'});
  if (!image) return;
  const result = await osipp.call('ocr.recognize', {base64:image.base64});
  if (!result.text.trim()) { await osipp.call('message', {text:'Nessun testo riconosciuto'}); return; }
  const edited = await osipp.call('ui.form', {title:'Correggi testo riconosciuto', fields:[
    {id:'text', label:'Testo', type:'text', multiline:true, required:true, default:result.text}
  ]});
  if (edited) await osipp.call('text.add', {text:edited.text, x:40, y:40, size:16});
}
''',
    },
    'commands': [
      {
        'id': 'recognize',
        'label': 'Leggi testo da immagine',
        'handler': 'recognize',
      },
    ],
  },
];

final _simplePluginExamples = <Map<String, dynamic>>[
  {
    'apiVersion': 1,
    'id': 'example.date-stamp',
    'name': 'Timbro data',
    'version': '1.0.0',
    'description': 'Aggiunge una data e un titolo personalizzato al foglio.',
    'permissions': ['document.write'],
    'commands': [
      {
        'id': 'stamp',
        'label': 'Inserisci timbro',
        'inputs': [
          {
            'id': 'title',
            'label': 'Titolo',
            'type': 'text',
            'default': 'Appunti',
          },
        ],
        'steps': [
          {
            'action': 'text.add',
            'args': {
              'text': r'${input.title} — ${today}',
              'x': 40,
              'y': 40,
              'size': 20,
            },
          },
        ],
      },
    ],
  },
  {
    'apiVersion': 1,
    'id': 'example.weekly-planner',
    'name': 'Planner settimanale',
    'version': '1.0.0',
    'description': 'Genera sette riquadri adattati alle dimensioni del foglio.',
    'permissions': ['document.write'],
    'commands': [
      {
        'id': 'generate',
        'label': 'Crea settimana',
        'steps': [
          {
            'set': 'spacing',
            'value': {
              'op': 'div',
              'args': [
                {
                  'op': 'sub',
                  'args': [
                    {'var': 'page.height'},
                    80,
                  ],
                },
                7,
              ],
            },
          },
          {
            'set': 'days',
            'value': [
              'Lunedì',
              'Martedì',
              'Mercoledì',
              'Giovedì',
              'Venerdì',
              'Sabato',
              'Domenica',
            ],
          },
          {
            'repeat': 7,
            'as': 'i',
            'steps': [
              {
                'set': 'y',
                'value': {
                  'op': 'add',
                  'args': [
                    40,
                    {
                      'op': 'mul',
                      'args': [
                        {'var': 'i'},
                        {'var': 'spacing'},
                      ],
                    },
                  ],
                },
              },
              {
                'action': 'shape.add',
                'args': {
                  'kind': 'rectangle',
                  'x': 30,
                  'y': {'var': 'y'},
                  'width': {
                    'op': 'sub',
                    'args': [
                      {'var': 'page.width'},
                      60,
                    ],
                  },
                  'height': {
                    'op': 'sub',
                    'args': [
                      {'var': 'spacing'},
                      6,
                    ],
                  },
                  'color': '#78909C',
                },
              },
              {
                'action': 'text.add',
                'args': {
                  'text': {
                    'op': 'at',
                    'args': [
                      {'var': 'days'},
                      {'var': 'i'},
                    ],
                  },
                  'x': 40,
                  'y': {
                    'op': 'add',
                    'args': [
                      {'var': 'y'},
                      8,
                    ],
                  },
                  'size': 16,
                },
              },
            ],
          },
        ],
      },
    ],
  },
  {
    'apiVersion': 1,
    'id': 'example.study-tools',
    'name': 'Strumenti studio',
    'version': '1.0.0',
    'description':
        'Preset penna ed evidenziatore e contatore persistente di utilizzi.',
    'permissions': ['tool.write', 'storage'],
    'commands': [
      {
        'id': 'highlight',
        'label': 'Evidenziatore giallo',
        'steps': [
          {
            'action': 'tool.set',
            'args': {'tool': 'highlighter', 'width': 18, 'color': '#FFF59D'},
          },
          {
            'action': 'state.get',
            'args': {'key': 'uses'},
            'as': 'uses',
          },
          {
            'action': 'state.set',
            'args': {
              'key': 'uses',
              'value': {
                'op': 'add',
                'args': [
                  1,
                  {
                    'op': 'coalesce',
                    'args': [
                      {'var': 'uses'},
                      0,
                    ],
                  },
                ],
              },
            },
          },
        ],
      },
      {
        'id': 'pen',
        'label': 'Penna blu',
        'steps': [
          {
            'action': 'tool.set',
            'args': {'tool': 'pen', 'width': 2.5, 'color': '#1565C0'},
          },
        ],
      },
    ],
  },
];

final pluginExamples = [..._simplePluginExamples, ..._advancedPluginExamples];

String exampleSource(int index) =>
    const JsonEncoder.withIndent('  ').convert(pluginExamples[index]);
