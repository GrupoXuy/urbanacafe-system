"use client";
import {useEffect,useMemo,useState} from "react";
import Link from "next/link";
import {createClient} from "@/lib/supabase-browser";

type Row={report_date:string;revenue:number;cogs:number;expenses:number;cash_in:number;cash_out:number;gross_profit:number;net_profit:number;sales_count:number};
const pad=(n:number)=>String(n).padStart(2,"0");
function monthStart(){const d=new Date();return d.getFullYear()+"-"+pad(d.getMonth()+1)+"-01"}
function today(){const d=new Date();return d.getFullYear()+"-"+pad(d.getMonth()+1)+"-"+pad(d.getDate())}

export default function Relatorios(){
  const [start,setStart]=useState(monthStart()),[end,setEnd]=useState(today()),[rows,setRows]=useState<Row[]>([]),[loading,setLoading]=useState(true),[message,setMessage]=useState("");

  async function load(){
    setLoading(true);setMessage("");
    const c=createClient();
    const {data:{user}}=await c.auth.getUser();
    if(!user){setLoading(false);return}
    const {data:m,error:me}=await c.from("business_memberships").select("business_id").eq("user_id",user.id).eq("active",true).limit(1).maybeSingle();
    if(me||!m){setMessage(me?.message||"Negócio não encontrado");setLoading(false);return}
    const {data,error}=await c.from("business_financial_daily")
      .select("report_date,revenue,cogs,expenses,cash_in,cash_out,gross_profit,net_profit,sales_count")
      .eq("business_id",m.business_id).gte("report_date",start).lte("report_date",end).order("report_date",{ascending:false});
    if(error)setMessage(error.message);
    setRows((data||[]) as Row[]);
    setLoading(false);
  }

  useEffect(()=>{load()},[]);

  const totals=useMemo(()=>rows.reduce((a,r)=>({
    revenue:a.revenue+Number(r.revenue||0),cogs:a.cogs+Number(r.cogs||0),expenses:a.expenses+Number(r.expenses||0),
    cash_in:a.cash_in+Number(r.cash_in||0),cash_out:a.cash_out+Number(r.cash_out||0),
    gross_profit:a.gross_profit+Number(r.gross_profit||0),net_profit:a.net_profit+Number(r.net_profit||0),sales_count:a.sales_count+Number(r.sales_count||0)
  }),{revenue:0,cogs:0,expenses:0,cash_in:0,cash_out:0,gross_profit:0,net_profit:0,sales_count:0}),[rows]);
  const averageTicket=totals.sales_count?totals.revenue/totals.sales_count:0;

  return <div className="main">
    <div className="topbar"><div><h1 className="title">Relatórios</h1><p className="subtitle">Faturamento, CMV, despesas e caixa por período</p></div><Link href="/dashboard" className="btn" style={{width:"auto",textDecoration:"none"}}>Dashboard</Link></div>
    <div className="card section"><div className="grid" style={{gridTemplateColumns:"repeat(3,minmax(0,1fr))"}}>
      <label className="field"><span>De</span><input type="date" value={start} onChange={e=>setStart(e.target.value)}/></label>
      <label className="field"><span>Até</span><input type="date" value={end} onChange={e=>setEnd(e.target.value)}/></label>
      <div className="field"><span>&nbsp;</span><button className="btn" onClick={load}>Atualizar período</button></div>
    </div></div>
    {message&&<div className="notice">{message}</div>}
    <div className="grid section">{[
      ["Faturamento","UYU "+totals.revenue.toFixed(2)],["CMV","UYU "+totals.cogs.toFixed(2)],["Lucro bruto","UYU "+totals.gross_profit.toFixed(2)],
      ["Despesas","UYU "+totals.expenses.toFixed(2)],["Lucro líquido","UYU "+totals.net_profit.toFixed(2)],["Ticket médio","UYU "+averageTicket.toFixed(2)],
      ["Entradas de caixa","UYU "+totals.cash_in.toFixed(2)],["Saídas de caixa","UYU "+totals.cash_out.toFixed(2)]
    ].map(([label,value])=><div className="card" key={label}><div className="label">{label}</div><div className="value">{value}</div></div>)}</div>
    <div className="section"><h2>Fechamento diário</h2>{loading?<div className="card">Carregando relatório...</div>:
      <table className="table"><thead><tr><th>Data</th><th>Vendas</th><th>Faturamento</th><th>CMV</th><th>Lucro bruto</th><th>Despesas</th><th>Lucro líquido</th></tr></thead>
      <tbody>{rows.length?rows.map(r=><tr key={r.report_date}><td>{new Date(r.report_date+"T12:00:00").toLocaleDateString("pt-BR")}</td><td>{r.sales_count}</td><td>UYU {Number(r.revenue).toFixed(2)}</td><td>UYU {Number(r.cogs).toFixed(2)}</td><td>UYU {Number(r.gross_profit).toFixed(2)}</td><td>UYU {Number(r.expenses).toFixed(2)}</td><td>UYU {Number(r.net_profit).toFixed(2)}</td></tr>):<tr><td colSpan={7}>Nenhum movimento no período.</td></tr>}</tbody></table>}
    </div>
  </div>
}
