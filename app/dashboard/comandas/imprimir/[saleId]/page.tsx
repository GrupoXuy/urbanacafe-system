"use client";

import {useEffect,useState} from "react";
import {useParams} from "next/navigation";
import Link from "next/link";
import {createClient} from "@/lib/supabase-browser";

type Sale={
  id:string;
  created_at:string;
  total:number;
  status:"open"|"completed"|"cancelled"|"refunded";
  notes:string|null;
  table_name:string;
  customer_name:string;
};
type Line={
  id:string;
  quantity:number;
  unit_price:number;
  product_name:string;
};

export default function PrintTicket(){
  const params=useParams<{saleId:string}>();
  const saleId=params?.saleId;
  const [sale,setSale]=useState<Sale|null>(null);
  const [lines,setLines]=useState<Line[]>([]);
  const [message,setMessage]=useState("");
  const [loading,setLoading]=useState(true);

  useEffect(()=>{
    async function load(){
      if(!saleId){setMessage("Comanda inválida.");setLoading(false);return}
      const c=createClient();
      const {data,error}=await c.from("sales")
        .select("id,created_at,total,status,notes,cafe_tables(name),customers(name)")
        .eq("id",saleId)
        .maybeSingle();
      if(error||!data){
        setMessage(error?.message||"Comanda não encontrada.");
        setLoading(false);
        return;
      }
      const row=data as unknown as {
        id:string;created_at:string;total:number;status:Sale["status"];notes:string|null;
        cafe_tables?:{name:string}[]|null;customers?:{name:string}[]|null;
      };
      setSale({
        id:row.id,
        created_at:row.created_at,
        total:Number(row.total||0),
        status:row.status,
        notes:row.notes,
        table_name:row.cafe_tables?.[0]?.name||"Balcão",
        customer_name:row.customers?.[0]?.name||"Consumidor final"
      });

      const {data:items,error:ie}=await c.from("sale_items")
        .select("id,quantity,unit_price,products(name)")
        .eq("sale_id",saleId);
      if(ie){
        setMessage(ie.message);
      }else{
        const rows=(items||[]) as unknown as Array<{
          id:string;quantity:number;unit_price:number;products?:{name:string}[]|null;
        }>;
        setLines(rows.map(item=>({
          id:item.id,
          quantity:Number(item.quantity||0),
          unit_price:Number(item.unit_price||0),
          product_name:item.products?.[0]?.name||"Produto"
        })));
      }
      setLoading(false);
    }
    load();
  },[saleId]);

  useEffect(()=>{
    if(!loading&&sale){
      const timer=window.setTimeout(()=>window.print(),250);
      return ()=>window.clearTimeout(timer);
    }
  },[loading,sale]);

  if(loading)return <main className="main"><p>Preparando ticket...</p></main>;
  if(!sale)return <main className="main"><div className="notice">{message}</div></main>;

  return <main className="main">
    <div className="print-controls" style={{display:"flex",justifyContent:"space-between",alignItems:"center",marginBottom:18}}>
      <div><b>Ticket de impressão</b><div className="subtitle">{sale.id}</div></div>
      <div style={{display:"flex",gap:8}}>
        <button type="button" className="btn" style={{width:"auto"}} onClick={()=>window.print()}>Imprimir</button>
        <Link href="/dashboard/comandas/imprimir" className="btn" style={{width:"auto",textDecoration:"none"}}>Voltar</Link>
      </div>
    </div>

    <section className="ticket-paper">
      <div style={{textAlign:"center"}}>
        <div style={{fontSize:24,fontWeight:800}}>URBANA CAFÉ</div>
        <div>COMANDA / PRODUÇÃO</div>
      </div>

      <div style={{borderTop:"1px dashed #111",borderBottom:"1px dashed #111",margin:"16px 0",padding:"10px 0"}}>
        <div><b>Mesa:</b> {sale.table_name}</div>
        <div><b>Cliente:</b> {sale.customer_name}</div>
        <div><b>Data:</b> {new Date(sale.created_at).toLocaleString("pt-BR")}</div>
        <div><b>Status:</b> {sale.status==="open"?"Aberta":sale.status==="completed"?"Paga":sale.status==="cancelled"?"Cancelada":"Estornada"}</div>
      </div>

      <div>
        {lines.map(item=><div key={item.id} style={{display:"flex",justifyContent:"space-between",gap:12,padding:"7px 0"}}>
          <span><b>{item.quantity}×</b> {item.product_name}</span>
          <span>UYU {item.quantity*item.unit_price}</span>
        </div>)}
      </div>

      {sale.notes&&<div style={{marginTop:12,paddingTop:10,borderTop:"1px dashed #111"}}><b>Obs.:</b> {sale.notes}</div>}

      <div style={{borderTop:"1px dashed #111",marginTop:16,paddingTop:10,display:"flex",justifyContent:"space-between",fontWeight:800,fontSize:18}}>
        <span>Total</span><span>UYU {sale.total.toFixed(2)}</span>
      </div>
      <div style={{textAlign:"center",marginTop:18,fontSize:12}}>Gerado pelo Urbana Café System</div>
    </section>
  </main>;
}
