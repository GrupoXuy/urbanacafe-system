"use client";

import {useCallback,useEffect,useMemo,useState} from "react";
import Link from "next/link";
import {createClient} from "@/lib/supabase-browser";

type Station="kitchen"|"bar";
type TicketStatus="pending"|"preparing"|"ready"|"served";
type Priority="low"|"normal"|"high"|"urgent";
type Ticket={
  id:string;
  sale_id:string;
  station:Station;
  status:TicketStatus;
  priority:Priority;
  target_seconds:number;
  sent_at:string;
  started_at:string|null;
  ready_at:string|null;
  served_at:string|null;
};
type Sale={
  id:string;
  total:number;
  notes:string|null;
  created_at:string;
  status:"open"|"completed";
  table_name:string;
  customer_name:string;
};
type Line={
  product_id:string;
  quantity:number;
  unit_price:number;
  product_name:string;
  production_station:"none"|Station;
};
type Card=Ticket&{sale:Sale;items:Line[];queuePosition:number};
type StationMetric={
  station:Station;
  active:number;
  pending:number;
  preparing:number;
  ready:number;
  delayed:number;
  served:number;
  avg_wait_seconds:number;
  avg_prep_seconds:number;
  avg_total_seconds:number;
};
type Metrics={
  active:number;
  pending:number;
  preparing:number;
  ready:number;
  delayed:number;
  served:number;
  avg_wait_seconds:number;
  avg_prep_seconds:number;
  avg_total_seconds:number;
  throughput_per_hour:number;
  stations:StationMetric[];
};
type OperationalStation={station:Station;capacity_units:number;active:number;pending:number;preparing:number;ready:number;queue_work_seconds:number;estimated_wait_seconds:number;pressure_percent:number;capacity_tickets_per_hour:number;predicted_delay_count:number;max_predicted_delay_seconds:number};
type OperationalAlert={id:string;station:Station;severity:"warning"|"critical";title:string;message:string;metric_value:number|null;threshold:number|null;last_triggered_at:string};
type OperationalControl={stations:OperationalStation[];alerts:OperationalAlert[]};

const stationLabel:Record<Station,string>={kitchen:"Cozinha",bar:"Bar"};
const statusLabel:Record<TicketStatus,string>={pending:"Na fila",preparing:"Em preparo",ready:"Pronto",served:"Entregue"};
const priorityLabel:Record<Priority,string>={low:"Baixa",normal:"Normal",high:"Alta",urgent:"Urgente"};

const emptyMetrics:Metrics={
  active:0,pending:0,preparing:0,ready:0,delayed:0,served:0,
  avg_wait_seconds:0,avg_prep_seconds:0,avg_total_seconds:0,throughput_per_hour:0,stations:[]
};

const formatDuration=(seconds:number)=>{
  const total=Math.max(0,Math.round(Number(seconds||0)));
  const min=Math.floor(total/60);
  const sec=total%60;
  return min+"m "+String(sec).padStart(2,"0")+"s";
};

const money=(value:number)=>"UYU "+Number(value||0).toFixed(2);

export default function KDS(){
  const [business,setBusiness]=useState("");
  const [tickets,setTickets]=useState<Card[]>([]);
  const [filter,setFilter]=useState<"all"|Station>("all");
  const [metrics,setMetrics]=useState<Metrics>(emptyMetrics);
  const [message,setMessage]=useState("");
  const [loading,setLoading]=useState(true);
  const [busy,setBusy]=useState("");
  const [now,setNow]=useState(Date.now());
  const [realtime,setRealtime]=useState(false);
  const [control,setControl]=useState<OperationalControl>({stations:[],alerts:[]});

  const load=useCallback(async(targetBusiness=business)=>{
    if(!targetBusiness)return;
    const c=createClient();
    const {data,error}=await c.from("production_tickets")
      .select("id,sale_id,station,status,priority,target_seconds,sent_at,started_at,ready_at,served_at")
      .eq("business_id",targetBusiness)
      .in("status",["pending","preparing","ready"])
      .order("priority",{ascending:false})
      .order("sent_at",{ascending:true});

    if(error){setMessage(error.message);return;}

    const rawTickets=(data||[]) as Ticket[];
    const saleIds=[...new Set(rawTickets.map(t=>t.sale_id))];
    if(!saleIds.length){setTickets([]);return;}

    const [{data:sales,error:se},{data:items,error:ie}]=await Promise.all([
      c.from("sales").select("id,total,notes,created_at,status,cafe_tables(name),customers(name)").in("id",saleIds),
      c.from("sale_items").select("sale_id,product_id,quantity,unit_price,products(name,production_station)").in("sale_id",saleIds)
    ]);

    if(se||ie){setMessage(se?.message||ie?.message||"Não foi possível carregar a produção.");return;}

    const saleMap=new Map<string,Sale>();
    for(const row of (sales||[]) as unknown as Array<{
      id:string;total:number;notes:string|null;created_at:string;status:"open"|"completed";
      cafe_tables?:{name:string}[]|null;customers?:{name:string}[]|null;
    }>){
      saleMap.set(row.id,{
        id:row.id,total:Number(row.total||0),notes:row.notes,created_at:row.created_at,status:row.status,
        table_name:row.cafe_tables?.[0]?.name||"Balcão",
        customer_name:row.customers?.[0]?.name||"Consumidor final"
      });
    }

    const itemMap=new Map<string,Line[]>();
    for(const row of (items||[]) as unknown as Array<{
      sale_id:string;product_id:string;quantity:number;unit_price:number;
      products?:{name:string;production_station:"none"|Station}[]|null;
    }>){
      const list=itemMap.get(row.sale_id)||[];
      list.push({
        product_id:row.product_id,quantity:Number(row.quantity||0),unit_price:Number(row.unit_price||0),
        product_name:row.products?.[0]?.name||"Produto",
        production_station:row.products?.[0]?.production_station||"none"
      });
      itemMap.set(row.sale_id,list);
    }

    const counters:Record<Station,number>={kitchen:0,bar:0};
    const nextTickets=rawTickets.map(ticket=>{
      counters[ticket.station]+=1;
      return {
        ...ticket,
        sale:saleMap.get(ticket.sale_id)||{
          id:ticket.sale_id,total:0,notes:null,created_at:ticket.sent_at,status:"open",
          table_name:"Balcão",customer_name:"Consumidor final"
        },
        items:(itemMap.get(ticket.sale_id)||[]).filter(i=>i.production_station===ticket.station),
        queuePosition:counters[ticket.station]
      };
    });
    setTickets(nextTickets);
  },[business]);

  const loadMetrics=useCallback(async(targetBusiness=business)=>{
    if(!targetBusiness)return;
    const c=createClient();
    const from=new Date();
    from.setHours(0,0,0,0);
    const {data,error}=await c.rpc("get_kds_metrics",{
      p_business_id:targetBusiness,
      p_from:from.toISOString(),
      p_to:new Date().toISOString()
    });
    if(error){setMessage(error.message);return;}
    setMetrics((data||emptyMetrics) as Metrics);
  },[business]);

  const loadControl=useCallback(async(targetBusiness=business)=>{
    if(!targetBusiness)return;
    const {data,error}=await createClient().rpc("get_kds_operational_control",{p_business_id:targetBusiness});
    if(error){setMessage(error.message);return;}
    setControl((data||{stations:[],alerts:[]}) as OperationalControl);
  },[business]);

  useEffect(()=>{
    async function bootstrap(){
      const c=createClient();
      const {data:{user}}=await c.auth.getUser();
      if(!user){setLoading(false);return;}
      const {data:m,error}=await c.from("business_memberships").select("business_id")
        .eq("user_id",user.id).eq("active",true).limit(1).maybeSingle();
      if(error||!m){setMessage(error?.message||"Negócio não encontrado");setLoading(false);return;}
      setBusiness(m.business_id);
      await Promise.all([load(m.business_id),loadMetrics(m.business_id),loadControl(m.business_id)]);
      setLoading(false);
    }
    bootstrap();
  },[load,loadMetrics,loadControl]);

  useEffect(()=>{
    if(!business)return;
    const c=createClient();
    const channel=c.channel("kds-production-"+business)
      .on("postgres_changes",{
        event:"*",
        schema:"public",
        table:"production_tickets",
        filter:"business_id=eq."+business
      },()=>{
        void load(business);
        void loadMetrics(business);
        void loadControl(business);
      })
      .subscribe((status)=>{
        setRealtime(status==="SUBSCRIBED");
      });

    const fallback=setInterval(()=>{
      void load(business);
      void loadMetrics(business);
      void loadControl(business);
    },30000);

    return ()=>{
      clearInterval(fallback);
      void c.removeChannel(channel);
      setRealtime(false);
    };
  },[business,load,loadMetrics,loadControl]);

  useEffect(()=>{
    const timer=setInterval(()=>setNow(Date.now()),1000);
    return ()=>clearInterval(timer);
  },[]);

  async function transition(ticket:Card,next:TicketStatus){
    setBusy(ticket.id);
    setMessage("");
    const {error}=await createClient().rpc("update_production_ticket_status",{
      p_ticket_id:ticket.id,p_status:next
    });
    if(error)setMessage(error.message);
    else await Promise.all([load(),loadMetrics()]);
    setBusy("");
  }

  async function changePriority(ticket:Card,priority:Priority){
    setBusy(ticket.id);
    setMessage("");
    const {error}=await createClient().rpc("set_production_ticket_priority",{
      p_ticket_id:ticket.id,p_priority:priority
    });
    if(error)setMessage(error.message);
    else await load();
    setBusy("");
  }

  function elapsed(ticket:Ticket){
    const base=ticket.status==="preparing"&&ticket.started_at
      ?ticket.started_at
      :ticket.sent_at;
    return formatDuration(Math.floor((now-new Date(base).getTime())/1000));
  }

  function isDelayed(ticket:Ticket){
    const base=ticket.status==="preparing"&&ticket.started_at
      ?ticket.started_at
      :ticket.sent_at;
    return ticket.status!=="ready" && now>new Date(base).getTime()+ticket.target_seconds*1000;
  }

  const visible=useMemo(
    ()=>tickets.filter(ticket=>filter==="all"||ticket.station===filter),
    [tickets,filter]
  );

  const grouped=useMemo(()=>({
    kitchen:visible.filter(t=>t.station==="kitchen"),
    bar:visible.filter(t=>t.station==="bar")
  }),[visible]);

  const stationMetric=(station:Station)=>metrics.stations.find(s=>s.station===station);
  const operationalStation=(station:Station)=>control.stations.find(s=>s.station===station);

  if(loading)return <main className="main"><p>Carregando KDS operacional...</p></main>;

  return <main className="main">
    <div className="topbar">
      <div>
        <h1 className="title">KDS — Controle Operacional</h1>
        <p className="subtitle">Prioridade, fila, tempo de preparo e desempenho de cozinha/bar em tempo real.</p>
      </div>
      <div style={{display:"flex",gap:8,alignItems:"center",flexWrap:"wrap"}}>
        <span className="subtitle">{realtime?"● Tempo real":"○ Reconectando..."}</span>
        <Link href="/dashboard/comandas" className="btn" style={{width:"auto",textDecoration:"none"}}>Comandas</Link><Link href="/dashboard/kds/performance" className="btn" style={{width:"auto",textDecoration:"none"}}>Performance</Link>
        <Link href="/dashboard" className="btn" style={{width:"auto",textDecoration:"none"}}>Dashboard</Link>
      </div>
    </div>

    {message&&<div className="notice">{message}</div>}
    {control.alerts.length>0&&<section className="section"><div className="card"><h2 style={{marginTop:0}}>Alertas operacionais</h2><div style={{display:"grid",gap:8}}>{control.alerts.map(a=><div key={a.id} style={{border:"1px solid #ddd",borderLeft:"5px solid #151515",borderRadius:9,padding:12}}><div style={{display:"flex",justifyContent:"space-between",gap:10,flexWrap:"wrap"}}><b>{a.title}</b><span className="label">{a.severity==="critical"?"CRÍTICO":"ATENÇÃO"}</span></div><div className="subtitle" style={{marginTop:4}}>{a.message}</div></div>)}</div></div></section>}

    <div className="grid">
      <div className="card"><div className="label">Fila ativa</div><div className="value">{metrics.active}</div><div className="subtitle">{metrics.pending} aguardando · {metrics.preparing} em preparo</div></div>
      <div className="card"><div className="label">Em atraso</div><div className="value">{metrics.delayed}</div><div className="subtitle">tickets acima do tempo-alvo</div></div>
      <div className="card"><div className="label">Tempo médio de preparo</div><div className="value">{formatDuration(metrics.avg_prep_seconds)}</div><div className="subtitle">tickets entregues hoje</div></div>
      <div className="card"><div className="label">Produção/hora</div><div className="value">{Number(metrics.throughput_per_hour||0).toFixed(1)}</div><div className="subtitle">{metrics.served} entregues hoje</div></div>
    </div>

    <div className="grid" style={{marginTop:14}}>
      <div className="card"><div className="label">Espera média</div><div className="value">{formatDuration(metrics.avg_wait_seconds)}</div><div className="subtitle">entrada → início do preparo</div></div>
      <div className="card"><div className="label">Tempo total médio</div><div className="value">{formatDuration(metrics.avg_total_seconds)}</div><div className="subtitle">entrada → entrega</div></div>
      <div className="card"><div className="label">Prontos aguardando</div><div className="value">{metrics.ready}</div><div className="subtitle">produção concluída</div></div>
      <div className="card"><div className="label">SLA atual</div><div className="value">{metrics.active?Math.max(0,Math.round(100*(1-(metrics.delayed/metrics.active)))):"—"}%</div><div className="subtitle">fila ativa dentro do tempo-alvo</div></div>
    </div>

    <div className="section" style={{display:"flex",gap:8,flexWrap:"wrap",alignItems:"center"}}>
      {([
        ["all","Todos"],
        ["kitchen","Cozinha"],
        ["bar","Bar"]
      ] as const).map(([value,label])=><button
        type="button" key={value} onClick={()=>setFilter(value)}
        style={{
          padding:"10px 14px",borderRadius:9,border:"1px solid #ddd",
          background:filter===value?"#151515":"#fff",color:filter===value?"#fff":"#171717",cursor:"pointer"
        }}
      >{label}</button>)}
      <Link href="/dashboard/comandas/imprimir" className="btn" style={{width:"auto",textDecoration:"none",marginLeft:"auto"}}>Impressão operacional</Link>
    </div>

    <div className="section" style={{display:"grid",gridTemplateColumns:"repeat(2,minmax(0,1fr))",gap:14}}>
      {(["kitchen","bar"] as Station[]).map(station=>{
        const list=grouped[station];
        const sm=stationMetric(station);
        const oc=operationalStation(station);
        if(filter!=="all"&&filter!==station)return null;
        return <section key={station} className="card">
          <div style={{display:"flex",justifyContent:"space-between",gap:12,alignItems:"center",marginBottom:12}}>
            <div>
              <h2 style={{margin:0}}>{stationLabel[station]}</h2>
              <div className="subtitle">Fila operacional · {list.length} tickets</div>
            </div>
            <div style={{textAlign:"right"}}>
              <b>{sm?.delayed||0} atrasados</b>
              <div className="subtitle">{sm?.pending||0} aguardando · {sm?.preparing||0} preparando</div>
              {oc&&<div className="subtitle">Pressão {oc.pressure_percent.toFixed(0)}% · capacidade {oc.capacity_units} slot(s)/{oc.capacity_tickets_per_hour.toFixed(1)} t/h</div>}
              {oc&&oc.predicted_delay_count>0&&<div className="subtitle">Atraso previsto: {oc.predicted_delay_count} · máx. {formatDuration(oc.max_predicted_delay_seconds)}</div>}
            </div>
          </div>

          <div style={{display:"grid",gap:10}}>
            {list.map(ticket=>{
              const delayed=isDelayed(ticket);
              const canStart=ticket.status==="pending";
              const canReady=ticket.status==="preparing";
              const canServe=ticket.status==="ready";
              return <article key={ticket.id} style={{
                border:"1px solid #ddd",borderLeft:"5px solid #151515",borderRadius:10,padding:12,
                background:delayed?"#fff5f5":"#fff"
              }}>
                <div style={{display:"flex",justifyContent:"space-between",gap:10}}>
                  <div>
                    <div className="label">#{ticket.queuePosition} · {priorityLabel[ticket.priority]}</div>
                    <h3 style={{margin:"4px 0"}}>{ticket.sale.table_name}</h3>
                    <div className="subtitle">{ticket.sale.customer_name} · {statusLabel[ticket.status]}</div>
                  </div>
                  <div style={{textAlign:"right"}}>
                    <b>{elapsed(ticket)}</b>
                    <div className="subtitle">alvo {formatDuration(ticket.target_seconds)}</div>
                    {delayed&&<div style={{fontWeight:700}}>ATRASADO</div>}
                  </div>
                </div>

                <div style={{marginTop:10}}>
                  {ticket.items.map(item=><div key={item.product_id} style={{display:"flex",justifyContent:"space-between",gap:10,padding:"7px 0",borderBottom:"1px solid #eee"}}>
                    <span><b>{item.quantity}×</b> {item.product_name}</span>
                    <span>{money(item.quantity*item.unit_price)}</span>
                  </div>)}
                </div>

                {ticket.sale.notes&&<div className="notice" style={{marginTop:10}}><b>Observação:</b> {ticket.sale.notes}</div>}

                <div style={{display:"flex",gap:6,flexWrap:"wrap",marginTop:10}}>
                  {(["urgent","high","normal","low"] as Priority[]).map(priority=>
                    <button
                      key={priority}
                      type="button"
                      disabled={busy===ticket.id}
                      onClick={()=>changePriority(ticket,priority)}
                      style={{
                        padding:"6px 8px",borderRadius:7,border:"1px solid #ddd",cursor:"pointer",
                        background:ticket.priority===priority?"#151515":"#fff",
                        color:ticket.priority===priority?"#fff":"#171717"
                      }}
                    >{priorityLabel[priority]}</button>
                  )}
                </div>

                <div style={{display:"flex",justifyContent:"space-between",gap:8,alignItems:"center",marginTop:10}}>
                  <div className="subtitle">Enviado {new Date(ticket.sent_at).toLocaleTimeString("pt-BR",{hour:"2-digit",minute:"2-digit"})}</div>
                  <div style={{display:"flex",gap:8}}>
                    {canStart&&<button type="button" className="btn" disabled={busy===ticket.id} onClick={()=>transition(ticket,"preparing")}>{busy===ticket.id?"...":"Iniciar preparo"}</button>}
                    {canReady&&<button type="button" className="btn" disabled={busy===ticket.id} onClick={()=>transition(ticket,"ready")}>{busy===ticket.id?"...":"Marcar pronto"}</button>}
                    {canServe&&<button type="button" className="btn" disabled={busy===ticket.id} onClick={()=>transition(ticket,"served")}>{busy===ticket.id?"...":"Marcar entregue"}</button>}
                  </div>
                </div>
                <Link href={"/dashboard/comandas/imprimir/"+ticket.sale_id} target="_blank" style={{display:"inline-block",marginTop:8}}>Imprimir comanda</Link>
              </article>;
            })}
            {!list.length&&<div className="subtitle" style={{padding:"18px 0",textAlign:"center"}}>Fila limpa.</div>}
          </div>
        </section>;
      })}
    </div>

    <div className="section">
      <div className="card">
        <h2 style={{marginTop:0}}>Indicadores por estação</h2>
        <div className="table-wrap" style={{overflowX:"auto"}}>
          <table className="table">
            <thead><tr><th>Estação</th><th>Fila</th><th>Preparo</th><th>Prontos</th><th>Atrasados</th><th>Entregues</th><th>Espera média</th><th>Preparo médio</th><th>Total médio</th></tr></thead>
            <tbody>
              {metrics.stations.map(s=><tr key={s.station}>
                <td><b>{stationLabel[s.station]}</b></td>
                <td>{s.pending}</td><td>{s.preparing}</td><td>{s.ready}</td><td>{s.delayed}</td><td>{s.served}</td>
                <td>{formatDuration(s.avg_wait_seconds)}</td><td>{formatDuration(s.avg_prep_seconds)}</td><td>{formatDuration(s.avg_total_seconds)}</td>
              </tr>)}
              {!metrics.stations.length&&<tr><td colSpan={9}>Ainda não há produção registrada hoje.</td></tr>}
            </tbody>
          </table>
        </div>
      </div>
    </div>
  </main>;
}
