type Props={
  active:boolean;guardias:any[];items:any[];days:Date[];config:any;
  onCreate:(guardia:any,date:Date)=>void;onEdit:(shift:any)=>void;
};

const key=(d:Date)=>`${d.getFullYear()}-${String(d.getMonth()+1).padStart(2,'0')}-${String(d.getDate()).padStart(2,'0')}`;
const localDate=(value:string)=>{const p=String(value).slice(0,10).split('-').map(Number);return new Date(p[0],p[1]-1,p[2])};
const same=(a:Date,b:Date)=>a.getFullYear()===b.getFullYear()&&a.getMonth()===b.getMonth()&&a.getDate()===b.getDate();

export default function WeeklyGrid({active,guardias,items,days,config,onCreate,onEdit}:Props){
  if(!active)return null;
  const weekly=items.filter(x=>days.some(d=>same(localDate(x.fecha),d)));
  const occupied=new Set(weekly.map(x=>`${x.guardia_id}-${key(localDate(x.fecha))}`)).size;
  return <section className="mb-5 rounded-2xl border border-slate-200 bg-white p-4 shadow-sm dark:border-slate-700 dark:bg-slate-800/80">
    <div className="mb-4 flex flex-wrap items-center justify-between gap-3">
      <div><h2 className="font-bold">Planificación semanal</h2><p className="text-xs text-slate-500">Selecciona una celda para programar o editar el turno.</p></div>
      <div className="flex flex-wrap gap-2 text-xs font-bold"><span className="rounded-full bg-slate-100 px-3 py-1.5 dark:bg-slate-700">{guardias.length} guardias</span><span className="rounded-full bg-teal-50 px-3 py-1.5 text-teal-700 dark:bg-teal-900/50 dark:text-teal-100">{weekly.length} turnos</span><span className="rounded-full bg-slate-100 px-3 py-1.5 text-slate-500 dark:bg-slate-700 dark:text-slate-300">{Math.max(0,guardias.length*7-occupied)} libres</span></div>
    </div>
    <div className="overflow-x-auto rounded-xl border border-slate-200 dark:border-slate-700">
      <table className="w-full min-w-[980px] border-collapse text-xs">
        <thead><tr className="bg-slate-50 text-slate-500 dark:bg-slate-700/80 dark:text-slate-200"><th className="sticky left-0 z-20 w-44 border-b border-r bg-slate-50 p-3 text-left uppercase tracking-wide dark:border-slate-700 dark:bg-slate-700">Guardias</th>{days.map(d=><th key={key(d)} className={`min-w-28 border-b border-r p-3 text-center dark:border-slate-700 ${same(d,new Date())?'bg-teal-50 text-teal-700 dark:bg-teal-900/40 dark:text-teal-100':''}`}><span className="block uppercase">{d.toLocaleDateString('es-CL',{weekday:'short'})}</span><span className="mt-1 block text-base text-slate-900 dark:text-slate-100">{d.getDate()}</span></th>)}</tr></thead>
        <tbody>{guardias.map(g=><tr key={g.id}><th className="sticky left-0 z-10 border-b border-r bg-white p-3 text-left dark:border-slate-700 dark:bg-slate-800"><span className="block truncate font-bold text-slate-900 dark:text-slate-100">{g.nombre}</span><span className="mt-1 block truncate font-normal text-slate-400 dark:text-slate-300">{g.rango||'Guardia'}</span></th>{days.map(d=>{
          const shifts=items.filter(x=>x.guardia_id===g.id&&same(localDate(x.fecha),d)).sort((a,b)=>String(a.hora_inicio).localeCompare(String(b.hora_inicio))),shift=shifts[0];
          if(!shift)return <td key={key(d)} className="border-b border-r p-1.5 text-center dark:border-slate-700"><button onClick={()=>onCreate(g,d)} className="min-h-16 w-full rounded-lg border border-dashed border-slate-200 text-[11px] font-semibold text-slate-400 transition hover:border-teal-400 hover:bg-teal-50 hover:text-teal-700 dark:border-slate-600 dark:text-slate-300 dark:hover:bg-teal-900/30 dark:hover:text-teal-100">Libre<br/><span className="font-normal">+ Programar</span></button></td>;
          const color=shift.tipo_turno==='Noche'?config.turno_noche_color:shift.tipo_turno==='Dia'?config.turno_dia_color:config.turno_personalizado_color;
          return <td key={key(d)} className="border-b border-r p-1.5 dark:border-slate-700"><button onClick={()=>onEdit(shift)} style={{backgroundColor:`${color}18`,borderColor:color,color}} className="min-h-16 w-full rounded-lg border-l-4 p-2 text-left transition hover:shadow-sm"><b className="block truncate">{shift.tipo_turno}</b><span className="mt-1 block whitespace-nowrap text-[10px]">{shift.hora_inicio}–{shift.hora_fin}</span>{shifts.length>1&&<span className="mt-1 block text-[9px] font-bold">+{shifts.length-1} turno</span>}</button></td>;
        })}</tr>)}</tbody>
      </table>
    </div>
  </section>;
}
