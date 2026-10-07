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
