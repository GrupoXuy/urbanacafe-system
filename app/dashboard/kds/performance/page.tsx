"use client";
import {useCallback,useEffect,useMemo,useState} from "react";
import Link from "next/link";
import {createClient} from "@/lib/supabase-browser";
type Station="kitchen"|"bar";
type StationMetric={station:Station;served:number;delayed:number;avg_wait_seconds:number;avg_prep_seconds:number;avg_total_seconds:number;sla_percent:number};
type ProductMetric={product_id:string;product_name:string;station:Station;quantity:number;tickets:number;delayed_tickets:number;avg_prep_seconds:number;avg_total_seconds:number};
type HourMetric={hour:number;served:number;avg_total_seconds:number};
type Performance={served:number;delayed:number;avg_wait_seconds:number;avg_prep_seconds:number;avg_total_seconds:number;throughput_per_hour:number;sla_percent:number;stations:StationMetric[];products:ProductMetric[];hours:HourMetric[]};
const empty:Performance={served:0,delayed:0,avg_wait_seconds:0,avg_prep_seconds:0,avg_total_seconds:0,throughput_per_hour:0,sla_percent:0,stations:[],products:[],hours:[]};
const labels:Record<Station,string>={kitchen:"Cozinha",bar:"Bar"};
const duration=(s:number)=>{const n=Math.max(0,Math.round(Number(s||0)));return Math.floor(n/60)+"m "+String(n%60).padStart(2,"0")+"s";};
export default function KDSPerformance(){
 const [business,setBusiness]=useState(""),[range,setRange]=useState<1|7|30>(7),[data,setData]=useState<Performance>(empty),[loading,setLoading]=useState(true),[message,setMessage]=useState("");
 const load=useCallback(async(days=range,target=business)=>{if(!target)return;const c=createClient(),to=new Date(),from=new Date(to.getTime()-days*86400000);const {data,error}=await c.rpc("get_kds_performance",{p_business_id:target,p_from:from.toISOString(),p_to:to.toISOString()});if(error){setMessage(error.message);return;}setData((data||empty) as Performance);},[business,range]);
 useEffect(()=>{async function boot(){const c=createClient(),{data:{user}}=await c.auth.getUser();if(!user){setLoading(false);return;}const {data:m,error}=await c.from("business_memberships").select("business_id").eq("user_id",user.id).eq("active",true).limit(1).maybeSingle();if(error||!m){setMessage(error?.message||"Negócio não encontrado");setLoading(false);return;}setBusiness(m.business_id);await load(range,m.business_id);setLoading(false);}void boot();},[load,range]);
 useEffect(()=>{if(business)void load(range,business);},[business,range,load]);
 const peak=useMemo(()=>data.hours.reduce((best,h)=>!best||h.served>best.served?h:best,null as HourMetric|null),[data.hours]);
 const bottleneck=useMemo(()=>data.stations.reduce((best,s)=>!best||s.avg_prep_seconds>best.avg_prep_seconds?s:best,null as StationMetric|null),[data.stations]);
 if(loading)return <main className="main"><p>Carregando Central de Performance...</p></main>;
 return <main className="main">
  <div className="topbar"><div><h1 className="title">KDS — Central de Performance</h1><p className="subtitle">Histórico de produção, SLA, gargalos, produtos críticos e horários de pico.</p></div><div style={{display:"flex",gap:8,flexWrap:"wrap",alignItems:"center"}}>{[1,7,30].map(days=><button key={days} type="button" onClick={()=>setRange(days as 1|7|30)} className="btn" style={{width:"auto",background:range===days?"#151515":"#fff",color:range===days?"#fff":"#151515"}}>{days===1?"Hoje":days+" dias"}</button>)}<Link href="/dashboard/kds" className="btn" style={{width:"auto",textDecoration:"none"}}>KDS ao vivo</Link></div></div>
  {message&&<div className="notice">{message}</div>}
  <div className="grid">
   <div className="card"><div className="label">SLA de produção</div><div className="value">{data.served?data.sla_percent.toFixed(1):"—"}%</div><div className="subtitle">tickets concluídos dentro do tempo-alvo</div></div>
   <div className="card"><div className="label">Produção/hora</div><div className="value">{data.throughput_per_hour.toFixed(1)}</div><div className="subtitle">{data.served} tickets entregues</div></div>
   <div className="card"><div className="label">Preparo médio</div><div className="value">{duration(data.avg_prep_seconds)}</div><div className="subtitle">início → pronto</div></div>
   <div className="card"><div className="label">Atrasos</div><div className="value">{data.delayed}</div><div className="subtitle">tickets acima do alvo</div></div>
  </div>
  <div className="grid" style={{marginTop:14}}>
   <div className="card"><div className="label">Espera média</div><div className="value">{duration(data.avg_wait_seconds)}</div></div>
   <div className="card"><div className="label">Tempo total médio</div><div className="value">{duration(data.avg_total_seconds)}</div></div>
   <div className="card"><div className="label">Horário de pico</div><div className="value">{peak?String(peak.hour).padStart(2,"0")+":00":"—"}</div><div className="subtitle">{peak?peak.served+" tickets":""}</div></div>
   <div className="card"><div className="label">Gargalo provável</div><div className="value">{bottleneck?labels[bottleneck.station]:"—"}</div><div className="subtitle">{bottleneck?duration(bottleneck.avg_prep_seconds)+" de preparo médio":"dados insuficientes"}</div></div>
  </div>
  <section className="section"><div className="card"><h2 style={{marginTop:0}}>Desempenho por estação</h2><div className="table-wrap" style={{overflowX:"auto"}}><table className="table"><thead><tr><th>Estação</th><th>Entregues</th><th>Atrasos</th><th>SLA</th><th>Espera</th><th>Preparo</th><th>Total</th></tr></thead><tbody>{data.stations.map(s=><tr key={s.station}><td><b>{labels[s.station]}</b></td><td>{s.served}</td><td>{s.delayed}</td><td>{s.sla_percent.toFixed(1)}%</td><td>{duration(s.avg_wait_seconds)}</td><td>{duration(s.avg_prep_seconds)}</td><td>{duration(s.avg_total_seconds)}</td></tr>)}{!data.stations.length&&<tr><td colSpan={7}>Ainda não há histórico no período.</td></tr>}</tbody></table></div></div></section>
  <section className="section"><div className="card"><h2 style={{marginTop:0}}>Produtos que exigem atenção</h2><p className="subtitle">Ordenados por atrasos e tempo médio de preparo. Use estes dados para revisar ficha técnica, tempo-alvo ou capacidade da estação.</p><div className="table-wrap" style={{overflowX:"auto"}}><table className="table"><thead><tr><th>Produto</th><th>Estação</th><th>Qtd.</th><th>Tickets</th><th>Atrasos</th><th>Preparo médio</th><th>Total médio</th></tr></thead><tbody>{data.products.map(p=><tr key={p.product_id}><td><b>{p.product_name}</b></td><td>{labels[p.station]}</td><td>{Number(p.quantity).toFixed(0)}</td><td>{p.tickets}</td><td>{p.delayed_tickets}</td><td>{duration(p.avg_prep_seconds)}</td><td>{duration(p.avg_total_seconds)}</td></tr>)}{!data.products.length&&<tr><td colSpan={7}>Ainda não há produtos concluídos no período.</td></tr>}</tbody></table></div></div></section>
  <section className="section"><div className="card"><h2 style={{marginTop:0}}>Mapa de demanda por hora</h2><div style={{display:"grid",gridTemplateColumns:"repeat(12,minmax(42px,1fr))",gap:6,overflowX:"auto"}}>{data.hours.map(h=><div key={h.hour} style={{border:"1px solid #ddd",borderRadius:8,padding:8,textAlign:"center",minWidth:42}}><div className="label">{String(h.hour).padStart(2,"0")}h</div><b>{h.served}</b><div className="subtitle">{duration(h.avg_total_seconds)}</div></div>)}</div></div></section>
 </main>;
}
