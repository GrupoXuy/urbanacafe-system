"use client";

import {useEffect,useState} from "react";
import Link from "next/link";
import {createClient} from "@/lib/supabase-browser";

type Sale={
  id:string;
  created_at:string;
  total:number;
  status:"open"|"completed"|"cancelled"|"refunded";
  table_name:string;
  customer_name:string;
};

export default function ImpressaoOperacional(){
  const [items,setItems]=useState<Sale[]>([]);
  const [message,setMessage]=useState("");
  const [loading,setLoading]=useState(true);

  async function load(){
    const c=createClient();
    const {data:{user}}=await c.auth.getUser();
    if(!user){setLoading(false);return}
    const {data:m,error:me}=await c.from("business_memberships").select("business_id")
      .eq("user_id",user.id).eq("active",true).limit(1).maybeSingle();
    if(me||!m){
      setMessage(me?.message||"Negócio não encontrado");
      setLoading(false);
      return;
    }

    const {data,error}=await c.from("sales")
      .select("id,created_at,total,status,cafe_tables(name),customers(name)")
      .eq("business_id",m.business_id)
      .in("status",["open","completed"])
      .order("created_at",{ascending:false})
      .limit(30);

    if(error){
      setMessage(error.message);
    }else{
      const rows=(data||[]) as unknown as Array<{
        id:string;created_at:string;total:number;status:Sale["status"];
        cafe_tables?:{name:string}[]|null;customers?:{name:string}[]|null;
      }>;
      setItems(rows.map(row=>({
        id:row.id,created_at:row.created_at,total:Number(row.total||0),status:row.status,
        table_name:row.cafe_tables?.[0]?.name||"Balcão",
        customer_name:row.customers?.[0]?.name||"Consumidor final"
      })));
    }
    setLoading(false);
  }

  useEffect(()=>{load()},[]);

  if(loading)return <main className="main"><p>Carregando impressão...</p></main>;

  return <main className="main">
    <div className="topbar print-controls">
      <div><h1 className="title">Impressão operacional</h1><p className="subtitle">Selecione uma comanda ou venda para gerar o ticket de impressão.</p></div>
      <div style={{display:"flex",gap:8}}>
        <Link href="/dashboard/kds" className="btn" style={{width:"auto",textDecoration:"none"}}>KDS</Link>
        <Link href="/dashboard/comandas" className="btn" style={{width:"auto",textDecoration:"none"}}>Comandas</Link>
      </div>
    </div>

    {message&&<div className="notice print-controls">{message}</div>}

    <div className="card print-controls">
      <table className="table">
        <thead><tr><th>Horário</th><th>Mesa</th><th>Cliente</th><th>Total</th><th>Status</th><th>Ação</th></tr></thead>
        <tbody>
          {items.map(item=><tr key={item.id}>
            <td>{new Date(item.created_at).toLocaleString("es-UY")}</td>
            <td>{item.table_name}</td>
            <td>{item.customer_name}</td>
            <td>UYU {item.total.toFixed(2)}</td>
            <td>{item.status==="open"?"Aberta":"Paga"}</td>
            <td><Link href={"/dashboard/comandas/imprimir/"+item.id}>Abrir ticket</Link></td>
          </tr>)}
          {!items.length&&<tr><td colSpan={6}>Nenhuma comanda ou venda disponível.</td></tr>}
        </tbody>
      </table>
    </div>
  </main>;
}
