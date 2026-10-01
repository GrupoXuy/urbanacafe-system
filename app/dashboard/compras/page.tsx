"use client";
import {useEffect,useMemo,useState} from "react";
import {createClient} from "@/lib/supabase-browser";

type Product={id:string;name:string;unit:string;average_cost:number};
type Line=Product&{quantity:number;unit_cost:number};

export default function Compras(){
 const [business,setBusiness]=useState(""),[products,setProducts]=useState<Product[]>([]),[suppliers,setSuppliers]=useState<any[]>([]),[lines,setLines]=useState<Line[]>([]),[selected,setSelected]=useState(""),[quantity,setQuantity]=useState("1"),[unitCost,setUnitCost]=useState(""),[supplier,setSupplier]=useState(""),[invoice,setInvoice]=useState(""),[paymentMethod,setPaymentMethod]=useState("cash"),[message,setMessage]=useState(""),[saving,setSaving]=useState(false),[items,setItems]=useState<any[]>([]);
 async function load(){
   const c=createClient();const {data:{user}}=await c.auth.getUser();if(!user)return;
   const {data:m}=await c.from("business_memberships").select("business_id").eq("user_id",user.id).eq("active",true).limit(1).maybeSingle();
   if(!m)return;
   setBusiness(m.business_id);
   const [{data:p},{data:s},{data:list}]=await Promise.all([
     c.from("products").select("id,name,unit,average_cost").eq("business_id",m.business_id).eq("active",true).order("name"),
     c.from("suppliers").select("id,name").eq("business_id",m.business_id).eq("active",true).order("name"),
     c.from("purchases").select("id,invoice_number,total,status,purchased_at,payment_method").eq("business_id",m.business_id).order("purchased_at",{ascending:false}).limit(30)
   ]);
   setProducts((p||[]) as Product[]);setSuppliers(s||[]);setItems(list||[]);
 }
 useEffect(()=>{load()},[]);
 const total=useMemo(()=>lines.reduce((s,l)=>s+l.quantity*l.unit_cost,0),[lines]);
 function addLine(){
   const p=products.find(x=>x.id===selected);const q=Number(quantity),cost=Number(unitCost||p?.average_cost||0);
   if(!p||q<=0||cost<0){setMessage("Selecione um produto e informe quantidade/custo válidos.");return}
   setLines(old=>{const found=old.find(x=>x.id===p.id);return found?old.map(x=>x.id===p.id?{...x,quantity:x.quantity+q,unit_cost:cost}:x):[...old,{...p,quantity:q,unit_cost:cost}]});
   setQuantity("1");setUnitCost("");
 }
 function removeLine(id:string){setLines(old=>old.filter(x=>x.id!==id))}
 async function saveAndPost(){
   if(!business||!lines.length){setMessage("Adicione pelo menos um item.");return}
   setSaving(true);setMessage("");
   const c=createClient();
   const {data:purchase,error}=await c.from("purchases").insert({
     business_id:business,supplier_id:supplier||null,invoice_number:invoice||null,
     status:"draft",payment_method:paymentMethod,total:0
   }).select("id").single();
   if(error){setMessage(error.message);setSaving(false);return}
   const {error:itemError}=await c.from("purchase_items").insert(lines.map(l=>({
     purchase_id:purchase.id,product_id:l.id,quantity:l.quantity,unit_cost:l.unit_cost
   })));
   if(itemError){setMessage(itemError.message);setSaving(false);return}
   const {error:postError}=await c.rpc("post_purchase",{p_purchase_id:purchase.id});
   if(postError)setMessage(postError.message);
   else{setMessage("Compra lançada: estoque e custo médio atualizados.");setLines([]);setInvoice("");load()}
   setSaving(false);
 }
 return <div className="main"><h1 className="title">Compras</h1><p className="subtitle">Entrada de estoque, fornecedor e custo médio ponderado</p>
 <div className="card section"><h2>Nova compra</h2>
   <div className="grid" style={{gridTemplateColumns:"repeat(4,minmax(0,1fr))"}}>
     <label className="field"><span>Fornecedor</span><select value={supplier} onChange={e=>setSupplier(e.target.value)}><option value="">Sem fornecedor</option>{suppliers.map(s=><option key={s.id} value={s.id}>{s.name}</option>)}</select></label>
     <label className="field"><span>Nota/fatura</span><input value={invoice} onChange={e=>setInvoice(e.target.value)} placeholder="Opcional"/></label>
     <label className="field"><span>Pagamento</span><select value={paymentMethod} onChange={e=>setPaymentMethod(e.target.value)}><option value="cash">Dinheiro</option><option value="debit">Débito</option><option value="credit">Crédito</option><option value="transfer">Transferência</option><option value="mercado_pago">Mercado Pago</option><option value="other">Outro</option></select></label>
     <div className="field"><span>Total</span><div className="value">UYU {total.toFixed(2)}</div></div>
   </div>
   <div className="grid" style={{gridTemplateColumns:"2fr 1fr 1fr auto"}}>
     <label className="field"><span>Produto</span><select value={selected} onChange={e=>{setSelected(e.target.value);const p=products.find(x=>x.id===e.target.value);if(p)setUnitCost(String(p.average_cost||0))}}><option value="">Selecione</option>{products.map(p=><option key={p.id} value={p.id}>{p.name} ({p.unit})</option>)}</select></label>
     <label className="field"><span>Quantidade</span><input type="number" min="0.001" step="0.001" value={quantity} onChange={e=>setQuantity(e.target.value)}/></label>
     <label className="field"><span>Custo unitário</span><input type="number" min="0" step="0.0001" value={unitCost} onChange={e=>setUnitCost(e.target.value)}/></label>
     <div className="field"><span>&nbsp;</span><button className="btn" style={{width:"auto"}} onClick={addLine}>Adicionar</button></div>
   </div>
   {lines.length>0&&<table className="table"><thead><tr><th>Produto</th><th>Qtd.</th><th>Custo</th><th>Total</th><th></th></tr></thead><tbody>{lines.map(l=><tr key={l.id}><td>{l.name}</td><td>{l.quantity} {l.unit}</td><td>UYU {l.unit_cost.toFixed(4)}</td><td>UYU {(l.quantity*l.unit_cost).toFixed(2)}</td><td><button onClick={()=>removeLine(l.id)}>Remover</button></td></tr>)}</tbody></table>}
   <button className="btn" onClick={saveAndPost} disabled={!lines.length||saving}>{saving?"Lançando...":"Lançar compra"}</button>{paymentMethod==="cash"&&<p className="subtitle">Pagamento em dinheiro exige caixa aberto.</p>}{message&&<div className="notice">{message}</div>}
 </div>
 <div className="section"><h2>Últimas compras</h2><table className="table"><thead><tr><th>Data</th><th>Nota</th><th>Pagamento</th><th>Total</th><th>Status</th></tr></thead><tbody>{items.map(x=><tr key={x.id}><td>{new Date(x.purchased_at).toLocaleDateString("pt-BR")}</td><td>{x.invoice_number||"—"}</td><td>{x.payment_method||"—"}</td><td>UYU {Number(x.total).toFixed(2)}</td><td>{x.status}</td></tr>)}</tbody></table></div>
 </div>
}