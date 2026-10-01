"use client";
import {useEffect,useState} from "react";
import {createClient} from "@/lib/supabase-browser";
export default function Estoque(){
 const [products,setProducts]=useState<any[]>([]);
 useEffect(()=>{createClient().from("products").select("id,name,unit,stock_quantity,min_stock,average_cost,sale_price").eq("active",true).order("name").then(({data})=>setProducts(data||[]))},[]);
 return <div className="main"><h1 className="title">Estoque</h1><p className="subtitle">Saldo, custo médio e alertas</p><div className="section"><table className="table"><thead><tr><th>Produto</th><th>Un.</th><th>Saldo</th><th>Custo médio</th><th>Preço</th><th>Status</th></tr></thead><tbody>{products.map(p=><tr key={p.id}><td>{p.name}</td><td>{p.unit}</td><td>{p.stock_quantity}</td><td>UYU {Number(p.average_cost).toFixed(2)}</td><td>UYU {Number(p.sale_price).toFixed(2)}</td><td>{Number(p.stock_quantity)<=Number(p.min_stock)?"Reposição":"Normal"}</td></tr>)}</tbody></table></div></div>
}