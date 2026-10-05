"use client";
import {useEffect,useState} from "react";
import Link from "next/link";
import {createClient} from "@/lib/supabase-browser";

const money=(value:number)=>"UYU "+Number(value||0).toFixed(2);

export default function Dashboard(){
  const [email,setEmail]=useState("");
  const [loading,setLoading]=useState(true);
  type DashboardMetrics={
    business_id:string;
    report_date:string;
    revenue:number;
    cogs:number;
    sales_count:number;
    refunds_count:number;
    expenses:number;
    gross_profit:number;
    net_profit:number;
    stock_value:number;
    stock_items:number;
    low_stock_count:number;
    out_of_stock_count:number;
    open_cash_sessions:number;
  };

  const [metrics,setMetrics]=useState<DashboardMetrics|null>(null);

  useEffect(()=>{
    async function load(){
      const c=createClient();
      const {data:{user}}=await c.auth.getUser();
      setEmail(user?.email??"");
      if(user){
        const {data:m}=await c.from("business_memberships").select("business_id").eq("user_id",user.id).eq("active",true).limit(1).maybeSingle();
        if(m){
          const {data:d}=await c.from("business_dashboard").select("*").eq("business_id",m.business_id).maybeSingle();
          setMetrics(d);
        }
      }
      setLoading(false);
    }
    load();
  },[]);

  if(loading)return <main className="main"><p>Carregando...</p></main>;

  const revenue=Number(metrics?.revenue||0);
  const cogs=Number(metrics?.cogs||0);
  const gross=Number(metrics?.gross_profit||0);
  const net=Number(metrics?.net_profit||0);
  const refunds=Number(metrics?.refunds_count||0);
  const expenses=Number(metrics?.expenses||0);
  const stockValue=Number(metrics?.stock_value||0);

  return <main className="main">
      <div className="topbar"><div><h1 className="title">Dashboard</h1><div className="subtitle">Visão geral da operação — hoje</div></div><div>{email}</div></div>
      <div className="grid">
        {[
          ["Faturamento",money(revenue)],
          ["CMV",money(cogs)],
          ["Lucro bruto",money(gross)],
          ["Lucro líquido",money(net)],
          ["Despesas",money(expenses)],
          ["Vendas",String(metrics?.sales_count||0)],
          ["Estornos",String(refunds)],
          ["Valor do estoque",money(stockValue)],
          ["Itens em estoque",String(metrics?.stock_items||0)],
          ["Abaixo do mínimo",String(metrics?.low_stock_count||0)],
          ["Sem estoque",String(metrics?.out_of_stock_count||0)],
          ["Caixas abertos",String(metrics?.open_cash_sessions||0)]
        ].map(([label,value])=><div className="card" key={label}><div className="label">{label}</div><div className="value">{value}</div></div>)}
      </div>

      {(Number(metrics?.low_stock_count||0)>0 || Number(metrics?.out_of_stock_count||0)>0) &&
        <div className="notice">Atenção: {Number(metrics?.out_of_stock_count||0)} item(ns) sem estoque e {Number(metrics?.low_stock_count||0)} item(ns) abaixo do mínimo. <Link href="/dashboard/estoque">Revisar estoque</Link></div>}

      <div className="section">
        <h2>Operação</h2>
        <table className="table">
          <thead><tr><th>Módulo</th><th>Status</th><th>Ação</th></tr></thead>
          <tbody>
            {[
              ["POS","Operacional","/dashboard/pos","Abrir vendas"],
              ["Histórico de vendas","Operacional","/dashboard/vendas","Consultar e estornar vendas"],
              ["Caixa","Operacional","/dashboard/caixa","Gerenciar caixa"],
              ["Estoque","Operacional","/dashboard/estoque","Consultar estoque"],
              ["Produtos","Operacional","/dashboard/produtos","Gerenciar produtos"],
              ["Fichas técnicas","Operacional","/dashboard/receitas","Gerenciar receitas"],
              ["Compras","Operacional","/dashboard/compras","Consultar compras"],
              ["Fornecedores","Operacional","/dashboard/fornecedores","Gerenciar fornecedores"],
              ["Despesas","Operacional","/dashboard/despesas","Lançar despesa"],
              ["Clientes","Operacional","/dashboard/clientes","Gerenciar clientes"],
              ["Mesas","Operacional","/dashboard/mesas","Gerenciar mesas"],
              ["Reservas","Operacional","/dashboard/reservas","Gerenciar reservas"],
              ["Relatórios","Gerencial","/dashboard/relatorios","Ver resultados"],
              ["Funcionários","Administrativo","/dashboard/funcionarios","Gerenciar equipe"],
              ["Configurações","Administrativo","/dashboard/configuracoes","Configurar negócio"]
            ].map(([module,status,href,action])=><tr key={module}><td>{module}</td><td>{status}</td><td><Link href={href}>{action}</Link></td></tr>)}
          </tbody>
        </table>
      </div>
    </main>
}