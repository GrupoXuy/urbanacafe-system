"use client";

import {useCallback,useEffect,useMemo,useState} from "react";
import Link from "next/link";
import {createClient} from "@/lib/supabase-browser";

type Station="kitchen"|"bar";
type TicketStatus="pending"|"preparing"|"ready";
type Ticket={
  id:string;
  sale_id:string;
  station:Station;
  status:TicketStatus;
  sent_at:string;
  started_at:string|null;
  ready_at:string|null;
  served_at:string|null;
};
type Sale={
  id:string;
  table_id:string|null;
  customer_id:string|null;
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
type Card=Ticket&{sale:Sale;items:Line[]};

const stationLabel:Record<Station,string>={kitchen:"Cozinha",bar:"Bar"};
const statusLabel:Record<TicketStatus,string>={pending:"Na fila",preparing:"Em preparo",ready:"Pronto"};

const money=(value:number)=>"UYU "+Number(value||0).toFixed(2);

export default function KDS(){
  const [business,setBusiness]=useState("");
  const [tickets,setTickets]=useState<Card[]>([]);
  const [filter,setFilter]=useState<"all"|Station>("all");
  const [message,setMessage]=useState("");
  const [loading,setLoading]=useState(true);
  const [busy,setBusy]=useState("");
  const [now,setNow]=useState(Date.now());

  const load=useCallback(async(targetBusiness=business)=>{
    if(!targetBusiness)return;
    const c=createClient();
    const {data,error}=await c.from("production_tickets")
      .select("id,sale_id,station,status,sent_at,started_at,ready_at,served_at")
      .eq("business_id",targetBusiness)
      .in("status",["pending","preparing","ready"])
      .order("sent_at",{ascending:true});

    if(error){setMessage(error.message);return}

    const rawTickets=(data||[]) as Ticket[];
    const saleIds=[...new Set(rawTickets.map(t=>t.sale_id))];
    if(!saleIds.length){
      setTickets([]);
      return;
    }

    const [{data:sales,error:se},{data:items,error:ie}]=await Promise.all([
      c.from("sales").select("id,table_id,customer_id,total,notes,created_at,status,cafe_tables(name),customers(name)")
        .in("id",saleIds),
      c.from("sale_items").select("sale_id,product_id,quantity,unit_price,products(name,production_station)")
        .in("sale_id",saleIds)
    ]);

    if(se||ie){
      setMessage(se?.message||ie?.message||"Não foi possível carregar a produção.");
      return;
    }

    const saleMap=new Map<string,Sale>();
    for(const row of (sales||[]) as unknown as Array<{
      id:string;table_id:string|null;customer_id:string|null;total:number;notes:string|null;created_at:string;status:"open"|"completed";
      cafe_tables?:{name:string}[]|null;customers?:{name:string}[]|null;
    }>){
      saleMap.set(row.id,{
        id:row.id,
        table_id:row.table_id,
        customer_id:row.customer_id,
        total:Number(row.total||0),
        notes:row.notes,
        created_at:row.created_at,
        status:row.status,
        table_name:row.cafe_tables?.[0]?.name||"Balcão",
        customer_name:row.customers?.[0]?.name||"Consumidor final"
      });
    }

    const itemRows=(items||[]) as unknown as Array<{
      sale_id:string;product_id:string;quantity:number;unit_price:number;
      products?:{name:string;production_station:"none"|Station}[]|null;
    }>;
    const itemMap=new Map<string,Line[]>();
    for(const row of itemRows){
      const list=itemMap.get(row.sale_id)||[];
      list.push({
        product_id:row.product_id,
        quantity:Number(row.quantity||0),
        unit_price:Number(row.unit_price||0),
        product_name:row.products?.[0]?.name||"Produto",
        production_station:row.products?.[0]?.production_station||"none"
      });
      itemMap.set(row.sale_id,list);
    }

    setTickets(rawTickets.map(ticket=>({
      ...ticket,
      sale:saleMap.get(ticket.sale_id)||{
        id:ticket.sale_id,table_id:null,customer_id:null,total:0,notes:null,
        created_at:ticket.sent_at,status:"open",table_name:"Balcão",customer_name:"Consumidor final"
      },
      items:(itemMap.get(ticket.sale_id)||[]).filter(i=>i.production_station===ticket.station)
    })));
  },[business]);

  useEffect(()=>{
    async function bootstrap(){
      const c=createClient();
      const {data:{user}}=await c.auth.getUser();
      if(!user){setLoading(false);return}
      const {data:m,error}=await c.from("business_memberships").select("business_id")
        .eq("user_id",user.id).eq("active",true).limit(1).maybeSingle();
      if(error||!m){setMessage(error?.message||"Negócio não encontrado");setLoading(false);return}
      setBusiness(m.business_id);
      await load(m.business_id);
      setLoading(false);
    }
    bootstrap();
  },[load]);

  useEffect(()=>{
    if(!business)return;
    const timer=setInterval(()=>load(),6000);
    return ()=>clearInterval(timer);
  },[business,load]);

  useEffect(()=>{
    const timer=setInterval(()=>setNow(Date.now()),1000);
    return ()=>clearInterval(timer);
  },[]);

  async function transition(ticket:Card,next:TicketStatus){
    setBusy(ticket.id);setMessage("");
    const {error}=await createClient().rpc("update_production_ticket_status",{
      p_ticket_id:ticket.id,
      p_status:next
    });
    if(error)setMessage(error.message);
    else await load();
    setBusy("");
  }

  const visible=useMemo(
    ()=>tickets.filter(ticket=>filter==="all"||ticket.station===filter),
    [tickets,filter]
  );

  const stats=useMemo(()=>({
    kitchen:tickets.filter(t=>t.station==="kitchen").length,
    bar:tickets.filter(t=>t.station==="bar").length,
    ready:tickets.filter(t=>t.status==="ready").length
  }),[tickets]);

  function elapsed(sentAt:string){
    const seconds=Math.max(0,Math.floor((now-new Date(sentAt).getTime())/1000));
    const min=Math.floor(seconds/60);
    const sec=seconds%60;
    return min+"m "+String(sec).padStart(2,"0")+"s";
  }

  if(loading)return <main className="main"><p>Carregando KDS...</p></main>;

  return <main className="main">
    <div className="topbar">
      <div>
        <h1 className="title">KDS — Cozinha e Bar</h1>
        <p className="subtitle">Produção em tempo real a partir das comandas · atualização automática a cada 6 segundos</p>
      </div>
      <div style={{display:"flex",gap:8}}>
        <Link href="/dashboard/comandas" className="btn" style={{width:"auto",textDecoration:"none"}}>Comandas</Link>
        <Link href="/dashboard" className="btn" style={{width:"auto",textDecoration:"none"}}>Dashboard</Link>
      </div>
    </div>

    {message&&<div className="notice">{message}</div>}

    <div className="grid">
      <div className="card"><div className="label">Cozinha</div><div className="value">{stats.kitchen}</div></div>
      <div className="card"><div className="label">Bar</div><div className="value">{stats.bar}</div></div>
      <div className="card"><div className="label">Prontos</div><div className="value">{stats.ready}</div></div>
      <div className="card"><div className="label">Fila total</div><div className="value">{tickets.length}</div></div>
    </div>

    <div className="section" style={{display:"flex",gap:8,flexWrap:"wrap"}}>
      {([
        ["all","Todos"],
        ["kitchen","Cozinha"],
        ["bar","Bar"]
      ] as const).map(([value,label])=><button
        type="button"
        key={value}
        onClick={()=>setFilter(value)}
        style={{
          padding:"10px 14px",
          borderRadius:9,
          border:"1px solid #ddd",
          background:filter===value?"#151515":"#fff",
          color:filter===value?"#fff":"#171717",
          cursor:"pointer"
        }}
      >{label}</button>)}
      <Link href="/dashboard/comandas/imprimir" className="btn" style={{width:"auto",textDecoration:"none",marginLeft:"auto"}}>Impressão operacional</Link>
    </div>

    <div className="section kds-grid" style={{display:"grid",gridTemplateColumns:"repeat(3,minmax(0,1fr))",gap:14}}>
      {visible.map(ticket=>{
        const canStart=ticket.status==="pending";
        const canReady=ticket.status==="preparing";
        const canServe=ticket.status==="ready";
        return <article className="card" key={ticket.id} style={{borderTop:"5px solid #151515"}}>
          <div style={{display:"flex",justifyContent:"space-between",gap:10}}>
            <div>
              <div className="label">{stationLabel[ticket.station]}</div>
              <h2 style={{margin:"5px 0"}}>{ticket.sale.table_name}</h2>
              <div className="subtitle">{ticket.sale.customer_name} · {elapsed(ticket.sent_at)}</div>
            </div>
            <div style={{textAlign:"right"}}>
              <b>{statusLabel[ticket.status]}</b>
              <div className="subtitle">{ticket.sale.status==="completed"?"Pago":"Em aberto"}</div>
            </div>
          </div>

          <div style={{marginTop:14}}>
            {ticket.items.map(item=><div key={item.product_id} style={{display:"flex",justifyContent:"space-between",gap:10,padding:"9px 0",borderBottom:"1px solid #eee"}}>
              <span><b>{item.quantity}×</b> {item.product_name}</span>
              <span>{money(item.quantity*item.unit_price)}</span>
            </div>)}
          </div>

          {ticket.sale.notes&&<div className="notice" style={{marginTop:12}}><b>Observação:</b> {ticket.sale.notes}</div>}

          <div style={{display:"grid",gridTemplateColumns:"1fr auto",gap:8,marginTop:14,alignItems:"center"}}>
            <div className="subtitle">Enviado {new Date(ticket.sent_at).toLocaleTimeString("pt-BR",{hour:"2-digit",minute:"2-digit"})}</div>
            {canStart&&<button type="button" className="btn" disabled={busy===ticket.id} onClick={()=>transition(ticket,"preparing")}>{busy===ticket.id?"Processando...":"Iniciar preparo"}</button>}
            {canReady&&<button type="button" className="btn" disabled={busy===ticket.id} onClick={()=>transition(ticket,"ready")}>{busy===ticket.id?"Processando...":"Marcar pronto"}</button>}
            {canServe&&<button type="button" className="btn" disabled={busy===ticket.id} onClick={()=>transition(ticket,"served")}>{busy===ticket.id?"Processando...":"Marcar entregue"}</button>}
          </div>
          <Link href={"/dashboard/comandas/imprimir/"+ticket.sale_id} target="_blank" style={{display:"inline-block",marginTop:10}}>Imprimir comanda</Link>
        </article>;
      })}
      {!visible.length&&<div className="card" style={{gridColumn:"1/-1"}}>
        <h2>Produção limpa</h2>
        <p className="subtitle">Não há tickets pendentes nesta estação. Novas comandas aparecerão automaticamente.</p>
      </div>}
    </div>
  </main>;
}
