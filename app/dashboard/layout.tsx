"use client";
import Link from "next/link";
import {usePathname} from "next/navigation";
import {createClient} from "@/lib/supabase-browser";

const links=[
  ["Dashboard","/dashboard"],
  ["Vendas / POS","/dashboard/pos"],
  ["Histórico de vendas","/dashboard/vendas"],
  ["Caixa","/dashboard/caixa"],
  ["Estoque","/dashboard/estoque"],
  ["Produtos","/dashboard/produtos"],
  ["Fichas técnicas","/dashboard/receitas"],
  ["Compras","/dashboard/compras"],
  ["Fornecedores","/dashboard/fornecedores"],
  ["Despesas","/dashboard/despesas"],
  ["Clientes","/dashboard/clientes"],
  ["Mesas","/dashboard/mesas"],
  ["Reservas","/dashboard/reservas"],
  ["Relatórios","/dashboard/relatorios"],
  ["Funcionários","/dashboard/funcionarios"],
  ["Configurações","/dashboard/configuracoes"]
];

export default function DashboardLayout({children}:{children:React.ReactNode}){
  const pathname=usePathname();

  async function logout(){
    await createClient().auth.signOut();
    window.location.href="/login";
  }

  return <div className="shell">
    <aside className="sidebar">
      <div className="brand">URBANA <span>CAFÉ</span></div>
      <nav className="nav" aria-label="Navegação principal">
        {links.map(([label,href])=>{
          const active=href==="/dashboard"
            ? pathname==="/dashboard"
            : pathname===href||pathname.startsWith(href+"/");
          return <Link
            className={active?"active":""}
            aria-current={active?"page":undefined}
            key={href}
            href={href}
          >{label}</Link>;
        })}
      </nav>
      <button
        type="button"
        onClick={logout}
        style={{marginTop:24,width:"100%",padding:10,borderRadius:8,border:"1px solid #555",background:"#151515",color:"#fff",cursor:"pointer"}}
      >Sair</button>
    </aside>
    {children}
  </div>;
}
