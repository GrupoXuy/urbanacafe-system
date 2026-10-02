"use client";
import {useEffect,useMemo,useState} from "react";
import {createClient} from "@/lib/supabase-browser";

type Product={
  id:string;
  name:string;
  unit:string;
  stock_quantity:number;
  min_stock:number;
  average_cost:number;
  sale_price:number;
  is_stock_item:boolean;
  is_sellable:boolean;
};

export default function Estoque(){
  const [products,setProducts]=useState<Product[]>([]);
  const [loading,setLoading]=useState(true);
  const [message,setMessage]=useState("");

  async function load(){
    setLoading(true);
    setMessage("");
    const c=createClient();
    const {data:{user}}=await c.auth.getUser();
    if(!user){setLoading(false);return}

    const {data:membership,error:membershipError}=await c
      .from("business_memberships")
      .select("business_id")
      .eq("user_id",user.id)
      .eq("active",true)
      .limit(1)
      .maybeSingle();

    if(membershipError||!membership){
      setMessage(membershipError?.message||"Negócio não encontrado.");
      setLoading(false);
      return;
    }

    const {data,error}=await c
      .from("products")
      .select("id,name,unit,stock_quantity,min_stock,average_cost,sale_price,is_stock_item,is_sellable")
      .eq("business_id",membership.business_id)
      .eq("active",true)
      .eq("is_stock_item",true)
      .order("name");

    if(error)setMessage(error.message);
    setProducts((data||[]) as Product[]);
    setLoading(false);
  }

  useEffect(()=>{load()},[]);

  const totals=useMemo(()=>({
    items:products.length,
    low:products.filter(p=>Number(p.stock_quantity)<=Number(p.min_stock)).length,
    value:products.reduce((sum,p)=>sum+Number(p.stock_quantity||0)*Number(p.average_cost||0),0)
  }),[products]);

  return <div className="main">
    <div className="topbar">
      <div>
        <h1 className="title">Estoque</h1>
        <p className="subtitle">Saldo, custo médio e alertas de reposição</p>
      </div>
    </div>

    {message&&<div className="notice">{message}</div>}

    <div className="grid section">
      <div className="card"><div className="label">Itens controlados</div><div className="value">{totals.items}</div></div>
      <div className="card"><div className="label">Abaixo do mínimo</div><div className="value">{totals.low}</div></div>
      <div className="card"><div className="label">Valor do estoque</div><div className="value">UYU {totals.value.toFixed(2)}</div></div>
    </div>

    <div className="section">
      {loading?<div className="card">Carregando estoque...</div>:
      <div className="card" style={{overflowX:"auto"}}>
        <table className="table">
          <thead><tr><th>Produto</th><th>Un.</th><th>Saldo</th><th>Mínimo</th><th>Custo médio</th><th>Preço</th><th>Status</th></tr></thead>
          <tbody>
            {products.map(p=><tr key={p.id}>
              <td><b>{p.name}</b></td>
              <td>{p.unit}</td>
              <td>{Number(p.stock_quantity).toFixed(3)}</td>
              <td>{Number(p.min_stock).toFixed(3)}</td>
              <td>UYU {Number(p.average_cost).toFixed(4)}</td>
              <td>UYU {Number(p.sale_price).toFixed(2)}</td>
              <td>{Number(p.stock_quantity)<=Number(p.min_stock)?"Reposição":"Normal"}</td>
            </tr>)}
            {!products.length&&<tr><td colSpan={7}>Nenhum item com controle de estoque cadastrado.</td></tr>}
          </tbody>
        </table>
      </div>}
    </div>
  </div>;
}
