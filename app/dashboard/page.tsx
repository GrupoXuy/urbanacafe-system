"use client";
import {useEffect,useState} from "react";
import Link from "next/link";
import {createClient} from "@/lib/supabase-browser";

const links=[
  ["Dashboard","/dashboard"],["Vendas / POS","/dashboard/pos"],["Caixa","/dashboard/caixa"],["Estoque","/dashboard/estoque"],
  ["Produtos","/dashboard/produtos"],["Compras","/dashboard/compras"],["Despesas","/dashboard/despesas"],["Clientes","/dashboard/clientes"],
  ["Mesas","/dashboard/mesas"],["Relatórios","/dashboard/relatorios"],["Funcionários","/dashboard/funcionarios"]
];

export default function Dashboard(){
  const [email,setEmail]=useState("");
  const [loading,setLoading]=useState(true);
  const [metrics,setMetrics]=useState<any>(null);

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

  async function logout(){await createClient().auth.signOut();location.href="/login"}
  if(loading)return <main className="main"><p>Carregando...</p></main>;

  const revenue=Number(metrics?.revenue||0);
  const cogs=Number(metrics?.cogs||0);
  const gross=revenue-cogs;

  return <div className="shell">
    <aside className="sidebar">
      <div className="brand">URBANA <span>CAFÉ</span></div>
      <nav className="nav">{links.map(([label,href])=><Link className={label==="Dashboard"?"active":""} key={label} href={href}>{label}</Link>)}</nav>
      <button onClick={logout} style={{marginTop:24,width:"100%",padding:10,borderRadius:8,border:"1px solid #555",background:"#151515",color:"#fff",cursor:"pointer"}}>Sair</button>
    </aside>

    <main className="main">
      <div className="topbar"><div><h1 className="title">Dashboard</h1><div className="subtitle">Visão geral da operação — hoje</div></div><div>{email}</div></div>
      <div className="grid">
        {[["Faturamento","UYU "+revenue.toFixed(2)],["CMV","UYU "+cogs.toFixed(2)],["Lucro bruto","UYU "+gross.toFixed(2)],["Vendas",String(metrics?.sales_count||0)]].map(([label,value])=><div className="card" key={label}><div className="label">{label}</div><div className="value">{value}</div></div>)}
      </div>

      <div className="section">
        <h2>Operação</h2>
        <table className="table">
          <thead><tr><th>Módulo</th><th>Status</th><th>Ação</th></tr></thead>
          <tbody>
            {[
              ["POS","Operacional","/dashboard/pos","Abrir vendas"],
              ["Caixa","Operacional","/dashboard/caixa","Gerenciar caixa"],
              ["Estoque","Operacional","/dashboard/estoque","Consultar estoque"],
              ["Produtos","Operacional","/dashboard/produtos","Gerenciar produtos"],
              ["Compras","Operacional","/dashboard/compras","Consultar compras"],
              ["Despesas","Operacional","/dashboard/despesas","Lançar despesa"],
              ["Clientes","Operacional","/dashboard/clientes","Gerenciar clientes"],
              ["Mesas","Operacional","/dashboard/mesas","Gerenciar mesas"],
              ["Relatórios","Gerencial","/dashboard/relatorios","Ver resultados"],
              ["Funcionários","Administrativo","/dashboard/funcionarios","Gerenciar equipe"]
            ].map(([module,status,href,action])=><tr key={module}><td>{module}</td><td>{status}</td><td><Link href={href}>{action}</Link></td></tr>)}
          </tbody>
        </table>
      </div>
    </main>
  </div>
}
