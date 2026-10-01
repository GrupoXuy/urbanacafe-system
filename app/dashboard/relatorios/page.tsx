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

type PaymentRow={
  report_date:string;
  method:string;
  gross_amount:number;
  refunded_amount:number;
  net_amount:number;
  transactions:number;
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

type InventoryRow={
  product_id:string;
  product_name:string;
  sku:string|null;
  unit:string;
  average_cost:number;
  stock_quantity:number;
  min_stock:number;
  active:boolean;
  is_sellable:boolean;
  stock_value:number;
  below_minimum:boolean;
  out_of_stock:boolean;
};

type ProductDailyRow={
  report_date:string;
  product_id:string;
  product_name:string;
  unit:string;
  gross_quantity:number;
  gross_revenue:number;
  gross_cogs:number;
  refunded_quantity:number;
  refunded_revenue:number;
  refunded_cogs:number;
  net_quantity:number;
  net_revenue:number;
  net_cogs:number;
  gross_margin:number;
  gross_sales_count:number;
  refunds_count:number;
};

type MovementRow={
  report_date:string;
  product_id:string;
  product_name:string;
  unit:string;
  movement_type:string;
  movement_count:number;
  quantity:number;
  value:number;
  absolute_value:number;
};

const methodLabel:Record<string,string>={
  cash:"Dinheiro",debit:"Débito",credit:"Crédito",transfer:"Transferência",mercado_pago:"Mercado Pago",other:"Outro"
};

const movementLabel:Record<string,string>={
  purchase:"Compra",sale:"Venda",adjustment:"Ajuste",waste:"Perda",transfer_in:"Transferência +",transfer_out:"Transferência −",production:"Produção"
};

const pad=(n:number)=>String(n).padStart(2,"0");
function monthStart(){const d=new Date();return d.getFullYear()+"-"+pad(d.getMonth()+1)+"-01"}
function today(){const d=new Date();return d.getFullYear()+"-"+pad(d.getMonth()+1)+"-"+pad(d.getDate())}
const money=(value:number)=>"UYU "+Number(value||0).toFixed(2);
const dateLabel=(value:string)=>new Date(value+"T12:00:00").toLocaleDateString("pt-BR");

export default function Relatorios(){
  const [start,setStart]=useState(monthStart());
  const [end,setEnd]=useState(today());
  const [rows,setRows]=useState<Row[]>([]);
  const [cashRows,setCashRows]=useState<CashRow[]>([]);
  const [paymentRows,setPaymentRows]=useState<PaymentRow[]>([]);
  const [inventoryRows,setInventoryRows]=useState<InventoryRow[]>([]);
  const [productRows,setProductRows]=useState<ProductDailyRow[]>([]);
  const [movementRows,setMovementRows]=useState<MovementRow[]>([]);
  const [loading,setLoading]=useState(true);
  const [message,setMessage]=useState("");

  async function load(){
    setLoading(true);setMessage("");
    if(start>end){
      setMessage("O período inicial não pode ser posterior ao período final.");
      setLoading(false);
      return;
    }

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

    const [{data:daily,error:dailyError},{data:cash,error:cashError},{data:payments,error:paymentError},{data:inventory,error:inventoryError},{data:products,error:productError},{data:movements,error:movementError}]=await Promise.all([
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
        .limit(30),
      c.from("business_payment_daily")
        .select("report_date,method,gross_amount,refunded_amount,net_amount,transactions,refunds_count")
        .eq("business_id",m.business_id)
        .gte("report_date",start)
        .lte("report_date",end)
        .order("report_date",{ascending:false}),
      c.from("business_inventory_summary")
        .select("product_id,product_name,sku,unit,average_cost,stock_quantity,min_stock,active,is_sellable,stock_value,below_minimum,out_of_stock")
        .eq("business_id",m.business_id)
        .order("product_name"),
      c.from("business_product_sales_daily")
        .select("report_date,product_id,product_name,unit,gross_quantity,gross_revenue,gross_cogs,refunded_quantity,refunded_revenue,refunded_cogs,net_quantity,net_revenue,net_cogs,gross_margin,gross_sales_count,refunds_count")
        .eq("business_id",m.business_id)
        .gte("report_date",start)
        .lte("report_date",end)
        .order("net_revenue",{ascending:false}),
      c.from("business_stock_movement_daily")
        .select("report_date,product_id,product_name,unit,movement_type,movement_count,quantity,value,absolute_value")
        .eq("business_id",m.business_id)
        .gte("report_date",start)
        .lte("report_date",end)
        .in("movement_type",["waste","adjustment"])
        .order("report_date",{ascending:false})
    ]);

    const errors=[dailyError,cashError,paymentError,inventoryError,productError,movementError].filter(Boolean);
    if(errors.length)setMessage(errors[0]?.message||"Não foi possível carregar todos os relatórios");

    setRows((daily||[]) as Row[]);
    setCashRows((cash||[]) as CashRow[]);
    setPaymentRows((payments||[]) as PaymentRow[]);
    setInventoryRows((inventory||[]) as InventoryRow[]);
    setProductRows((products||[]) as ProductDailyRow[]);
    setMovementRows((movements||[]) as MovementRow[]);
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

  const inventoryTotals=useMemo(()=>({
    stockValue:inventoryRows.reduce((sum,r)=>sum+Number(r.stock_value||0),0),
    itemCount:inventoryRows.length,
    lowStock:inventoryRows.filter(r=>r.active&&r.below_minimum).length,
    outOfStock:inventoryRows.filter(r=>r.active&&r.out_of_stock).length
  }),[inventoryRows]);

  const topProducts=useMemo(()=>{
    const grouped=new Map<string,{product_id:string;product_name:string;unit:string;net_quantity:number;net_revenue:number;net_cogs:number;gross_margin:number;sales_count:number;refunds_count:number}>();
    productRows.forEach(r=>{
      const current=grouped.get(r.product_id)||{
        product_id:r.product_id,product_name:r.product_name,unit:r.unit,
        net_quantity:0,net_revenue:0,net_cogs:0,gross_margin:0,sales_count:0,refunds_count:0
      };
      current.net_quantity+=Number(r.net_quantity||0);
      current.net_revenue+=Number(r.net_revenue||0);
      current.net_cogs+=Number(r.net_cogs||0);
      current.gross_margin+=Number(r.gross_margin||0);
      current.sales_count+=Number(r.gross_sales_count||0);
      current.refunds_count+=Number(r.refunds_count||0);
      grouped.set(r.product_id,current);
    });
    return Array.from(grouped.values()).sort((a,b)=>b.net_revenue-a.net_revenue).slice(0,10);
  },[productRows]);

  const lowStockRows=useMemo(()=>inventoryRows
    .filter(r=>r.active&&r.below_minimum)
    .sort((a,b)=>Number(a.stock_quantity)-Number(b.stock_quantity))
    .slice(0,30),[inventoryRows]);

  const losses=useMemo(()=>movementRows.reduce((a,r)=>{
    if(r.movement_type==="waste")return {quantity:a.quantity+Math.abs(Number(r.quantity||0)),value:a.value+Math.abs(Number(r.value||0))};
    if(r.movement_type==="adjustment"&&Number(r.quantity||0)<0)return {quantity:a.quantity+Math.abs(Number(r.quantity||0)),value:a.value+Math.abs(Number(r.value||0))};
    return a;
  },{quantity:0,value:0}),[movementRows]);

  const netAdjustments=useMemo(()=>movementRows
    .filter(r=>r.movement_type==="adjustment")
    .reduce((a,r)=>({quantity:a.quantity+Number(r.quantity||0),value:a.value+Number(r.value||0)}),{quantity:0,value:0}),[movementRows]);

  const averageTicket=totals.sales_count?totals.revenue/totals.sales_count:0;
  const closedDifferences=cashRows.filter(r=>r.counted_amount!==null&&Number(r.calculated_difference||0)!==0);
  const openSessions=cashRows.filter(r=>r.status==="open");

  return <div className="main">
    <div className="topbar">
      <div>
        <h1 className="title">Relatórios</h1>
        <p className="subtitle">DRE, caixa, pagamentos, estoque e desempenho operacional</p>
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
      ["Faturamento líquido",money(totals.revenue)],
      ["CMV líquido",money(totals.cogs)],
      ["Lucro bruto",money(totals.gross_profit)],
      ["Despesas",money(totals.expenses)],
      ["Lucro líquido",money(totals.net_profit)],
      ["Ticket médio",money(averageTicket)],
      ["Vendas concluídas",String(totals.sales_count)],
      ["Estornos",String(totals.refunds_count)],
      ["Entradas de caixa",money(totals.cash_in)],
      ["Saídas de caixa",money(totals.cash_out)]
    ].map(([label,value])=><div className="card" key={label}><div className="label">{label}</div><div className="value">{value}</div></div>)}</div>

    <div className="section">
      <div className="topbar" style={{padding:0}}>
        <div><h2>Visão operacional do estoque</h2><p className="subtitle">Posição atual do inventário e alertas de reposição</p></div>
      </div>
      <div className="grid">{[
        ["Valor do estoque",money(inventoryTotals.stockValue)],
        ["Itens controlados",String(inventoryTotals.itemCount)],
        ["Abaixo do mínimo",String(inventoryTotals.lowStock)],
        ["Sem estoque",String(inventoryTotals.outOfStock)],
        ["Perdas / ajustes negativos",money(losses.value)],
        ["Ajuste líquido",inventoryTotals.itemCount+" itens · "+Number(netAdjustments.quantity||0).toFixed(3)+" "+(inventoryRows[0]?.unit||"un")]
      ].map(([label,value])=><div className="card" key={label}><div className="label">{label}</div><div className="value">{value}</div></div>)}</div>
    </div>

    <div className="section">
      <h2>Alertas de estoque</h2>
      {loading?<div className="card">Carregando estoque...</div>:
      <div className="card" style={{overflowX:"auto"}}>
        <table className="table">
          <thead><tr><th>Produto</th><th>Estoque</th><th>Mínimo</th><th>Custo médio</th><th>Valor</th><th>Status</th></tr></thead>
          <tbody>{lowStockRows.length?lowStockRows.map(r=><tr key={r.product_id}>
            <td><b>{r.product_name}</b>{r.sku&&<div className="subtitle">{r.sku}</div>}</td>
            <td>{Number(r.stock_quantity).toFixed(3)} {r.unit}</td>
            <td>{Number(r.min_stock).toFixed(3)} {r.unit}</td>
            <td>{money(Number(r.average_cost))}</td>
            <td>{money(Number(r.stock_value))}</td>
            <td>{r.out_of_stock?"Sem estoque":"Reposição"}</td>
          </tr>):<tr><td colSpan={6}>Nenhum item abaixo do estoque mínimo.</td></tr>}</tbody>
        </table>
      </div>}
    </div>

    <div className="section">
      <h2>Desempenho por produto</h2>
      {loading?<div className="card">Carregando produtos...</div>:
      <div className="card" style={{overflowX:"auto"}}>
        <table className="table">
          <thead><tr><th>Produto</th><th>Qtde líquida</th><th>Faturamento líquido</th><th>CMV</th><th>Margem bruta</th><th>Vendas</th><th>Estornos</th></tr></thead>
          <tbody>{topProducts.length?topProducts.map(r=><tr key={r.product_id}>
            <td><b>{r.product_name}</b><div className="subtitle">{r.unit}</div></td>
            <td>{Number(r.net_quantity).toFixed(3)}</td>
            <td>{money(r.net_revenue)}</td>
            <td>{money(r.net_cogs)}</td>
            <td>{money(r.gross_margin)}</td>
            <td>{r.sales_count}</td>
            <td>{r.refunds_count}</td>
          </tr>):<tr><td colSpan={7}>Nenhuma venda de produto no período.</td></tr>}</tbody>
        </table>
      </div>}
    </div>

    <div className="section">
      <h2>Perdas e ajustes de estoque</h2>
      {loading?<div className="card">Carregando perdas...</div>:
      <div className="card" style={{overflowX:"auto"}}>
        <table className="table">
          <thead><tr><th>Data</th><th>Produto</th><th>Tipo</th><th>Quantidade</th><th>Valor</th></tr></thead>
          <tbody>{movementRows.length?movementRows.slice(0,50).map((r,index)=><tr key={r.report_date+"-"+r.product_id+"-"+r.movement_type+"-"+index}>
            <td>{dateLabel(r.report_date)}</td>
            <td>{r.product_name}</td>
            <td>{movementLabel[r.movement_type]||r.movement_type}</td>
            <td>{r.movement_type==="waste"?Math.abs(Number(r.quantity)).toFixed(3):Number(r.quantity).toFixed(3)} {r.unit}</td>
            <td>{money(r.movement_type==="waste"?Math.abs(Number(r.value)):Number(r.value))}</td>
          </tr>):<tr><td colSpan={5}>Nenhuma perda ou correção registrada no período.</td></tr>}</tbody>
        </table>
      </div>}
    </div>

    <div className="section">
      <h2>Fechamento diário</h2>
      {loading?<div className="card">Carregando relatório...</div>:
      <table className="table">
        <thead><tr><th>Data</th><th>Vendas</th><th>Estornos</th><th>Faturamento</th><th>CMV</th><th>Lucro bruto</th><th>Despesas</th><th>Lucro líquido</th></tr></thead>
        <tbody>{rows.length?rows.map(r=><tr key={r.report_date}>
          <td>{dateLabel(r.report_date)}</td>
          <td>{r.sales_count}</td>
          <td>{r.refunds_count}</td>
          <td>{money(r.revenue)}</td>
          <td>{money(r.cogs)}</td>
          <td>{money(r.gross_profit)}</td>
          <td>{money(r.expenses)}</td>
          <td>{money(r.net_profit)}</td>
        </tr>):<tr><td colSpan={8}>Nenhum movimento no período.</td></tr>}</tbody>
      </table>}
    </div>

    <div className="section">
      <h2>Reconciliação por meio de pagamento</h2>
      {loading?<div className="card">Carregando pagamentos...</div>:
      <div className="card" style={{overflowX:"auto"}}>
        <table className="table">
          <thead><tr><th>Data</th><th>Meio</th><th>Bruto</th><th>Estornos</th><th>Líquido</th><th>Vendas</th><th>Estornos</th></tr></thead>
          <tbody>{paymentRows.length?paymentRows.map((r,index)=><tr key={r.report_date+"-"+r.method+"-"+index}>
            <td>{dateLabel(r.report_date)}</td>
            <td>{methodLabel[r.method]||r.method}</td>
            <td>{money(r.gross_amount)}</td>
            <td>{money(r.refunded_amount)}</td>
            <td>{money(r.net_amount)}</td>
            <td>{r.transactions}</td>
            <td>{r.refunds_count}</td>
          </tr>):<tr><td colSpan={7}>Nenhum pagamento no período.</td></tr>}</tbody>
        </table>
      </div>}
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
            <td>{money(r.calculated_expected)}</td>
            <td>{r.counted_amount===null?"—":money(r.counted_amount)}</td>
            <td>{r.calculated_difference===null?"—":money(r.calculated_difference)}</td>
            <td>{money(r.cash_sales)}</td>
            <td>{money(r.cash_refunds)}</td>
            <td>{money(r.cash_expenses)}</td>
            <td>{r.movement_count}</td>
          </tr>):<tr><td colSpan={9}>Nenhuma sessão de caixa encontrada.</td></tr>}</tbody>
        </table>
      </div>}
    </div>
  </div>
}
