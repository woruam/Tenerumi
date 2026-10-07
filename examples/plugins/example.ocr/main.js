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
