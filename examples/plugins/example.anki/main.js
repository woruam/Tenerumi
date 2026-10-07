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
