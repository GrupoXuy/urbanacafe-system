"use client";
import type {ReactNode} from "react";
import Link from "next/link";
import {usePathname} from "next/navigation";
import {createClient} from "@/lib/supabase-browser";

const links=[
  ["Dashboard","/dashboard"],
  ["Ventas / POS","/dashboard/pos"],
  ["Comandas","/dashboard/comandas"],
  ["KDS Cocina/Bar","/dashboard/kds"],
  ["Historial de ventas","/dashboard/vendas"],
  ["Caja","/dashboard/caixa"],
  ["Inventario","/dashboard/estoque"],
  ["Productos","/dashboard/produtos"],
  ["Fichas técnicas","/dashboard/receitas"],
  ["Compras","/dashboard/compras"],
  ["Proveedores","/dashboard/fornecedores"],
  ["Gastos","/dashboard/despesas"],
  ["Clientes","/dashboard/clientes"],
  ["Mesas","/dashboard/mesas"],
  ["Reservas","/dashboard/reservas"],
  ["Informes","/dashboard/relatorios"],
  ["Empleados","/dashboard/funcionarios"],
  ["Configuración","/dashboard/configuracoes"]
];

export default function DashboardLayout({children}:{children:ReactNode}){
  const pathname=usePathname();

  async function logout(){
    await createClient().auth.signOut();
    window.location.href="/login";
  }

  return <div className="shell">
    <aside className="sidebar">
      <div className="brand">URBANA <span>CAFÉ</span></div>
      <nav className="nav" aria-label="Navegación principal">
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
      >Cerrar sesión</button>
    </aside>
    {children}
  </div>;
}
