"use client";
import {useEffect,useMemo,useState} from "react";
import Link from "next/link";
import {createClient} from "@/lib/supabase-browser";

type Row={
  report_date:string;
  revenue:number;
  cogs:number;
  expenses:number;
  cash_in:number;
  cash_out:number;
  gross_profit:number;
  net_profit:number;
  sales_count:number;
  refunds_count:number;
};

type CashRow={
  cash_session_id:string;
  opened_at:string;
  closed_at:string|null;
  status:string;
  opening_amount:number;
  calculated_expected:number;
  counted_amount:number|null;
  calculated_difference:number|null;
  cash_sales:number;
  cash_refunds:number;
  cash_expenses:number;
  deposits:number;
  withdrawals:number;
  adjustments:number;
  movement_count:number;
};

const pad=(n:number)=>String(n).padStart(2,"0");
function monthStart(){const d=new Date();return d.getFullYear()+"-"+pad(d.getMonth()+1)+"-01"}
function today(){const d=new Date();return d.getFullYear()+"-"+pad(d.getMonth()+1)+"-"+pad(d.getDate())}

export default function Relatorios(){
  const [start,setStart]=useState(monthStart());
  const [end,setEnd]=useState(today());
  const [rows,setRows]=useState<Row[]>([]);
  const [cashRows,setCashRows]=useState<CashRow[]>([]);
  const [loading,setLoading]=useState(true);
  const [message,setMessage]=useState("");

  async function load(){
    setLoading(true);setMessage("");
    const c=createClient();
    const {data:{user}}=await c.auth.getUser();
    if(!user){setLoading(false);return}

    const {data:m,error:me}=await c.from("business_memberships")
      .select("business_id")
      .eq("user_id",user.id)
      .eq("active",true)
      .limit(1)
      .maybeSingle();

    if(me||!m){
      setMessage(me?.message||"Negócio não encontrado");
      setLoading(false);
      return;
    }

    const [{data:daily,error:dailyError},{data:cash,error:cashError}]=await Promise.all([
      c.from("business_financial_daily")
        .select("report_date,revenue,cogs,expenses,cash_in,cash_out,gross_profit,net_profit,sales_count,refunds_count")
        .eq("business_id",m.business_id)
        .gte("report_date",start)
        .lte("report_date",end)
        .order("report_date",{ascending:false}),
      c.from("business_cash_reconciliation")
        .select("cash_session_id,opened_at,closed_at,status,opening_amount,calculated_expected,counted_amount,calculated_difference,cash_sales,cash_refunds,cash_expenses,deposits,withdrawals,adjustments,movement_count")
        .eq("business_id",m.business_id)
        .order("opened_at",{ascending:false})
        .limit(30)
    ]);

    if(dailyError||cashError)setMessage(dailyError?.message||cashError?.message||"Não foi possível carregar a reconciliação");
    setRows((daily||[]) as Row[]);
    setCashRows((cash||[]) as CashRow[]);
    setLoading(false);
  }

  useEffect(()=>{load()},[]);

  const totals=useMemo(()=>rows.reduce((a,r)=>({
    revenue:a.revenue+Number(r.revenue||0),
    cogs:a.cogs+Number(r.cogs||0),
    expenses:a.expenses+Number(r.expenses||0),
    cash_in:a.cash_in+Number(r.cash_in||0),
    cash_out:a.cash_out+Number(r.cash_out||0),
    gross_profit:a.gross_profit+Number(r.gross_profit||0),
    net_profit:a.net_profit+Number(r.net_profit||0),
    sales_count:a.sales_count+Number(r.sales_count||0),
    refunds_count:a.refunds_count+Number(r.refunds_count||0)
  }),{
    revenue:0,cogs:0,expenses:0,cash_in:0,cash_out:0,
    gross_profit:0,net_profit:0,sales_count:0,refunds_count:0
  }),[rows]);

  const averageTicket=totals.sales_count?totals.revenue/totals.sales_count:0;
  const closedDifferences=cashRows.filter(r=>r.counted_amount!==null && Number(r.calculated_difference||0)!==0);
  const openSessions=cashRows.filter(r=>r.status==="open");

  return <div className="main">
    <div className="topbar">
      <div>
        <h1 className="title">Relatórios</h1>
        <p className="subtitle">DRE operacional, caixa e reconciliação por sessão</p>
      </div>
      <Link href="/dashboard" className="btn" style={{width:"auto",textDecoration:"none"}}>Dashboard</Link>
    </div>

    <div className="card section">
      <div className="grid" style={{gridTemplateColumns:"repeat(3,minmax(0,1fr))"}}>
        <label className="field"><span>De</span><input type="date" value={start} onChange={e=>setStart(e.target.value)}/></label>
        <label className="field"><span>Até</span><input type="date" value={end} onChange={e=>setEnd(e.target.value)}/></label>
        <div className="field"><span>&nbsp;</span><button className="btn" onClick={load}>Atualizar período</button></div>
      </div>
    </div>

    {message&&<div className="notice">{message}</div>}

    <div className="grid section">{[
      ["Faturamento líquido","UYU "+totals.revenue.toFixed(2)],
      ["CMV líquido","UYU "+totals.cogs.toFixed(2)],
      ["Lucro bruto","UYU "+totals.gross_profit.toFixed(2)],
      ["Despesas","UYU "+totals.expenses.toFixed(2)],
      ["Lucro líquido","UYU "+totals.net_profit.toFixed(2)],
      ["Ticket médio","UYU "+averageTicket.toFixed(2)],
      ["Vendas concluídas",String(totals.sales_count)],
      ["Estornos",String(totals.refunds_count)],
      ["Entradas de caixa","UYU "+totals.cash_in.toFixed(2)],
      ["Saídas de caixa","UYU "+totals.cash_out.toFixed(2)]
    ].map(([label,value])=><div className="card" key={label}><div className="label">{label}</div><div className="value">{value}</div></div>)}</div>

    <div className="section">
      <h2>Fechamento diário</h2>
      {loading?<div className="card">Carregando relatório...</div>:
      <table className="table">
        <thead><tr><th>Data</th><th>Vendas</th><th>Estornos</th><th>Faturamento</th><th>CMV</th><th>Lucro bruto</th><th>Despesas</th><th>Lucro líquido</th></tr></thead>
        <tbody>{rows.length?rows.map(r=><tr key={r.report_date}>
          <td>{new Date(r.report_date+"T12:00:00").toLocaleDateString("pt-BR")}</td>
          <td>{r.sales_count}</td>
          <td>{r.refunds_count}</td>
          <td>UYU {Number(r.revenue).toFixed(2)}</td>
          <td>UYU {Number(r.cogs).toFixed(2)}</td>
          <td>UYU {Number(r.gross_profit).toFixed(2)}</td>
          <td>UYU {Number(r.expenses).toFixed(2)}</td>
          <td>UYU {Number(r.net_profit).toFixed(2)}</td>
        </tr>):<tr><td colSpan={8}>Nenhum movimento no período.</td></tr>}</tbody>
      </table>}
    </div>

    <div className="section">
      <div className="topbar" style={{padding:0}}>
        <div><h2>Reconciliação de caixa</h2><p className="subtitle">{openSessions.length} caixa(s) aberto(s) · {closedDifferences.length} fechamento(s) com diferença</p></div>
      </div>
      {loading?<div className="card">Carregando sessões...</div>:
      <div className="card" style={{overflowX:"auto"}}>
        <table className="table">
          <thead><tr><th>Abertura</th><th>Status</th><th>Esperado</th><th>Contado</th><th>Diferença</th><th>Vendas</th><th>Estornos</th><th>Despesas</th><th>Movimentos</th></tr></thead>
          <tbody>{cashRows.length?cashRows.map(r=><tr key={r.cash_session_id}>
            <td>{new Date(r.opened_at).toLocaleString("pt-BR")}</td>
            <td>{r.status==="open"?"Aberto":"Fechado"}</td>
            <td>UYU {Number(r.calculated_expected).toFixed(2)}</td>
            <td>{r.counted_amount===null?"—":"UYU "+Number(r.counted_amount).toFixed(2)}</td>
            <td>{r.calculated_difference===null?"—":"UYU "+Number(r.calculated_difference).toFixed(2)}</td>
            <td>UYU {Number(r.cash_sales).toFixed(2)}</td>
            <td>UYU {Number(r.cash_refunds).toFixed(2)}</td>
            <td>UYU {Number(r.cash_expenses).toFixed(2)}</td>
            <td>{r.movement_count}</td>
          </tr>):<tr><td colSpan={9}>Nenhuma sessão de caixa encontrada.</td></tr>}</tbody>
        </table>
      </div>}
    </div>
  </div>
}
